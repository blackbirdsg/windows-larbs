$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$cliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
if (-not $cliResult) {
  Show-DesktopProfileError -Message 'GlazeWM CLI was not found.'
  return
}

$cli = $cliResult.Value
$logPath = Join-Path $env:LOCALAPPDATA 'glzr-startup\codex-launcher.log'

function Write-LauncherLog {
  param([string]$Message)

  try {
    $logDirectory = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $logDirectory)) {
      New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    Add-Content -LiteralPath $logPath -Value ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message)
  } catch {
    # Logging must never prevent the shortcut from working.
  }
}

function Start-CodexVimium {
  $configuredLauncher = Get-DesktopProfileSetting -Section 'Codex' -Name 'VimiumLauncher' -Default ''
  $launchers = @(
    $configuredLauncher,
    (Join-Path $env:USERPROFILE 'plugins\codex-vimium\scripts\companion\run.ps1')
  ) | Where-Object { $_ }
  $launcher = $launchers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $launcher) {
    return
  }

  $alreadyRunning = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*codex-vimium*run.ps1*' }).Count -gt 0
  if ($alreadyRunning) {
    return
  }

  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden',
    '-File', ('"{0}"' -f $launcher)
  )
}

function Invoke-GlazeQuery {
  param([string[]]$Arguments)

  $json = & $cli @Arguments 2>$null
  if (-not $json) {
    return $null
  }

  return $json | ConvertFrom-Json
}

function Get-CodexWindows {
  $windowsResult = Invoke-GlazeQuery @('query', 'windows')
  if (-not $windowsResult) {
    return @()
  }

  @(
    $windowsResult.data.windows |
      Where-Object {
        $_.processName -in @('Codex', 'codex', 'ChatGPT') -or
        ($_.className -eq 'Chrome_WidgetWin_1' -and $_.title -in @('Codex', 'ChatGPT'))
      }
  )
}

function Find-NewCodexWindow {
  param([string[]]$BeforeIds)

  Get-CodexWindows |
    Where-Object { $_.id -notin $BeforeIds } |
    Select-Object -First 1
}

function Wait-ForNewCodexWindow {
  param(
    [string[]]$BeforeIds,
    [int]$TimeoutMilliseconds
  )

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  do {
    Start-Sleep -Milliseconds 250
    $newWindow = Find-NewCodexWindow $BeforeIds
    if ($newWindow) {
      return $newWindow
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  return $null
}

function Initialize-CodexAutomation {
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
}

function Test-CodexWindowHasStartupError {
  param($Window)

  try {
    Initialize-CodexAutomation
    $root = [Windows.Automation.AutomationElement]::FromHandle(
      [IntPtr]::new([int64]$Window.handle)
    )
    if (-not $root) {
      return $false
    }

    $errorCondition = [Windows.Automation.PropertyCondition]::new(
      [Windows.Automation.AutomationElement]::NameProperty,
      'Oops, an error has occurred'
    )
    return $null -ne $root.FindFirst(
      [Windows.Automation.TreeScope]::Descendants,
      $errorCondition
    )
  } catch {
    return $false
  }
}

function Get-UsableCodexWindowInWorkspace {
  param([string]$WorkspaceId)

  $candidates = @(Get-CodexWindows | Where-Object { $_.parentId -eq $WorkspaceId })
  foreach ($candidate in $candidates) {
    if (Test-CodexWindowHasStartupError $candidate) {
      Write-LauncherLog "Closing failed Codex window '$($candidate.id)' before relaunch."
      & $cli command --id $candidate.id close | Out-Null
      Start-Sleep -Milliseconds 250
      continue
    }

    return $candidate
  }

  return $null
}

function Resolve-CodexExecutable {
  $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
  if ($package) {
    $candidate = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  $runningExecutable = Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath } |
    Select-Object -First 1 -ExpandProperty ExecutablePath
  if ($runningExecutable -and (Test-Path -LiteralPath $runningExecutable)) {
    return $runningExecutable
  }

  throw 'The installed ChatGPT executable was not found.'
}

function Start-CodexWorkspaceInstance {
  param([string]$WorkspaceName)

  $profileKey = ($WorkspaceName -replace '[^A-Za-z0-9._-]', '_').Trim('_')
  if (-not $profileKey) {
    $profileKey = 'default'
  }

  $instancePath = Join-Path $env:LOCALAPPDATA "larbs-windows-state\codex-instances\workspace-$profileKey"
  New-Item -ItemType Directory -Path $instancePath -Force | Out-Null

  $executable = Resolve-CodexExecutable
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $executable
  $startInfo.Arguments = '--user-data-dir="{0}"' -f $instancePath
  $startInfo.WorkingDirectory = Split-Path -Parent $executable
  $startInfo.UseShellExecute = $false
  $startInfo.EnvironmentVariables['CODEX_ELECTRON_USER_DATA_PATH'] = $instancePath

  $process = [Diagnostics.Process]::Start($startInfo)
  if (-not $process) {
    throw "Failed to start the Codex instance for workspace '$WorkspaceName'."
  }

  Write-LauncherLog "Started isolated Codex process '$($process.Id)' for workspace '$WorkspaceName'."
}

function Enable-CodexWorkMode {
  param(
    $Window,
    [int]$TimeoutMilliseconds = 30000
  )

  Initialize-CodexAutomation
  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)

  do {
    try {
      $root = [Windows.Automation.AutomationElement]::FromHandle(
        [IntPtr]::new([int64]$Window.handle)
      )
      if ($root) {
        $errorCondition = [Windows.Automation.PropertyCondition]::new(
          [Windows.Automation.AutomationElement]::NameProperty,
          'Oops, an error has occurred'
        )
        if ($root.FindFirst([Windows.Automation.TreeScope]::Descendants, $errorCondition)) {
          throw 'The isolated Codex window entered the renderer error screen.'
        }

        $workCondition = [Windows.Automation.AndCondition]::new(@(
          [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::NameProperty,
            'Work'
          ),
          [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::Button
          )
        ))
        $workButton = $root.FindFirst(
          [Windows.Automation.TreeScope]::Descendants,
          $workCondition
        )
        if ($workButton) {
          $toggle = $workButton.GetCurrentPattern(
            [Windows.Automation.TogglePattern]::Pattern
          )
          if ($toggle.Current.ToggleState -ne [Windows.Automation.ToggleState]::On) {
            $toggle.Toggle()
            Start-Sleep -Milliseconds 750
          }
          return $true
        }
      }
    } catch [Windows.Automation.ElementNotAvailableException] {
      # The renderer can replace its accessibility tree while loading.
    }

    Start-Sleep -Milliseconds 350
  } while ([DateTime]::UtcNow -lt $deadline)

  return $false
}

function Focus-WorkspaceIfNeeded {
  param([string]$WorkspaceName)

  $workspace = (Invoke-GlazeQuery @('query', 'workspaces')).data.workspaces |
    Where-Object { $_.name -eq $WorkspaceName } |
    Select-Object -First 1
  if (-not $workspace) {
    return $false
  }

  if (-not $workspace.hasFocus) {
    & $cli command focus --workspace $WorkspaceName | Out-Null
  }

  return $true
}

function Move-CodexWindowToTarget {
  param(
    [string]$WindowId,
    [string]$TargetWorkspace,
    [string]$TargetWorkspaceId
  )

  # Electron announces the window before its initial placement has fully settled.
  # Recheck the parent after each move so a late app event cannot pull it back.
  Start-Sleep -Milliseconds 600
  $placed = $false
  for ($i = 0; $i -lt 5; $i++) {
    & $cli command --id $WindowId move --workspace $TargetWorkspace | Out-Null
    Start-Sleep -Milliseconds 300

    $managedWindow = Get-CodexWindows |
      Where-Object { $_.id -eq $WindowId } |
      Select-Object -First 1
    if ($managedWindow.parentId -eq $TargetWorkspaceId) {
      $placed = $true
      break
    }
  }

  & $cli command --id $WindowId set-tiling | Out-Null
  Focus-WorkspaceIfNeeded $TargetWorkspace | Out-Null
  & $cli command focus --container-id $WindowId | Out-Null

  return $placed
}

function Return-ToTargetWorkspace {
  param(
    [string]$TargetWorkspace,
    [string]$TargetContainerId
  )

  Focus-WorkspaceIfNeeded $TargetWorkspace | Out-Null
  if ($TargetContainerId) {
    & $cli command focus --container-id $TargetContainerId | Out-Null
  }
}

$mutex = [System.Threading.Mutex]::new($false, 'Local\GlazeWM-Codex-Launcher')
$lockTaken = $false

try {
  try {
    $lockTaken = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $lockTaken = $true
  }

  if (-not $lockTaken) {
    Write-LauncherLog 'Ignored overlapping Alt+C invocation.'
    return
  }

  Start-CodexVimium

  $workspacesResult = Invoke-GlazeQuery @('query', 'workspaces')
  $targetWorkspaceObject = $workspacesResult.data.workspaces |
    Where-Object { $_.hasFocus } |
    Select-Object -First 1

  if (-not $targetWorkspaceObject) {
    throw 'GlazeWM did not report a focused workspace.'
  }

  $targetWorkspace = $targetWorkspaceObject.name
  $targetContainerId = $null
  if ($targetWorkspaceObject.childFocusOrder.Count -gt 0) {
    $targetContainerId = $targetWorkspaceObject.childFocusOrder[0]
  }

  $existingCodexWindow = Get-UsableCodexWindowInWorkspace $targetWorkspaceObject.id
  if ($existingCodexWindow) {
    Focus-WorkspaceIfNeeded $targetWorkspace | Out-Null
    & $cli command focus --container-id $existingCodexWindow.id | Out-Null
    Write-LauncherLog "Focused existing Codex window '$($existingCodexWindow.id)' in workspace '$targetWorkspace'."
    return
  }

  $beforeCodexIds = @(Get-CodexWindows | ForEach-Object { $_.id })
  $newWindow = $null

  Write-LauncherLog "Alt+C requested from workspace '$targetWorkspace'; existing windows: $($beforeCodexIds.Count)."

  Start-CodexWorkspaceInstance $targetWorkspace
  $newWindow = Wait-ForNewCodexWindow $beforeCodexIds 45000

  if ($newWindow) {
    $placed = Move-CodexWindowToTarget $newWindow.id $targetWorkspace $targetWorkspaceObject.id
    $workModeReady = Enable-CodexWorkMode $newWindow
    if (-not $workModeReady) {
      Write-LauncherLog "Created window '$($newWindow.id)', but its Work mode control did not become ready."
    } elseif ($placed) {
      Write-LauncherLog "Created isolated Work window '$($newWindow.id)' in workspace '$targetWorkspace'."
    } else {
      Write-LauncherLog "Created isolated Work window '$($newWindow.id)', but GlazeWM did not confirm placement in workspace '$targetWorkspace'."
    }
  } else {
    Return-ToTargetWorkspace $targetWorkspace $targetContainerId
    Write-LauncherLog "No new managed ChatGPT window appeared for workspace '$targetWorkspace'."
  }
} catch {
  Write-LauncherLog "Launcher error: $($_.Exception.Message)"
} finally {
  if ($lockTaken) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
