$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$cliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
if (-not $cliResult) {
  Show-DesktopProfileError -Message 'GlazeWM CLI was not found.'
  return
}

$cli = $cliResult.Value
$codexProtocol = 'codex://threads/new'
$codexAppId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
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

function Select-CodexWindowForCommand {
  param([string]$TargetWorkspaceId)

  $windows = @(Get-CodexWindows)

  $workspaceWindow = $windows |
    Where-Object {
      $_.parentId -eq $TargetWorkspaceId -and
      $_.state.type -ne 'minimized'
    } |
    Select-Object -First 1

  if ($workspaceWindow) {
    return $workspaceWindow
  }

  $shownWindow = $windows |
    Where-Object { $_.displayState -eq 'shown' -and $_.state.type -ne 'minimized' } |
    Select-Object -First 1

  if ($shownWindow) {
    return $shownWindow
  }

  return $windows | Select-Object -First 1
}

function Invoke-CodexNewWindowShortcut {
  param([string]$WindowId)

  & $cli command focus --container-id $WindowId | Out-Null

  for ($i = 0; $i -lt 15; $i++) {
    $focusedWindow = Get-CodexWindows | Where-Object { $_.id -eq $WindowId } | Select-Object -First 1
    if ($focusedWindow.hasFocus) {
      break
    }
    Start-Sleep -Milliseconds 100
  }

  Start-Sleep -Milliseconds 300
  $shell = New-Object -ComObject WScript.Shell
  $shell.SendKeys('^+n')
}

function Start-CodexFromStableRegistration {
  try {
    Start-Process -FilePath $codexProtocol
  } catch {
    Start-Process -FilePath 'explorer.exe' -ArgumentList @("shell:AppsFolder\$codexAppId")
  }
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
  & $cli command focus --workspace $TargetWorkspace | Out-Null
  & $cli command focus --container-id $WindowId | Out-Null

  return $placed
}

function Return-ToTargetWorkspace {
  param(
    [string]$TargetWorkspace,
    [string]$TargetContainerId
  )

  & $cli command focus --workspace $TargetWorkspace | Out-Null
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

  $beforeCodexIds = @(Get-CodexWindows | ForEach-Object { $_.id })
  $existingCodexWindow = Select-CodexWindowForCommand $targetWorkspaceObject.id
  $newWindow = $null

  Write-LauncherLog "Alt+C requested from workspace '$targetWorkspace'; existing windows: $($beforeCodexIds.Count)."

  if ($existingCodexWindow) {
    Invoke-CodexNewWindowShortcut $existingCodexWindow.id
    $newWindow = Wait-ForNewCodexWindow $beforeCodexIds 10000

    if (-not $newWindow) {
      Write-LauncherLog 'First Ctrl+Shift+N attempt produced no managed window; retrying once.'
      $existingCodexWindow = Select-CodexWindowForCommand $targetWorkspaceObject.id
      if ($existingCodexWindow) {
        Invoke-CodexNewWindowShortcut $existingCodexWindow.id
        $newWindow = Wait-ForNewCodexWindow $beforeCodexIds 10000
      }
    }
  } else {
    Start-CodexFromStableRegistration
    $newWindow = Wait-ForNewCodexWindow $beforeCodexIds 30000
  }

  if ($newWindow) {
    $placed = Move-CodexWindowToTarget $newWindow.id $targetWorkspace $targetWorkspaceObject.id
    if ($placed) {
      Write-LauncherLog "Created window '$($newWindow.id)' in workspace '$targetWorkspace'."
    } else {
      Write-LauncherLog "Created window '$($newWindow.id)', but GlazeWM did not confirm placement in workspace '$targetWorkspace'."
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
