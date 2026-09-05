[CmdletBinding()]
param([string] $TargetWorkspace = '')

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

function Initialize-CodexWindowProcessApi {
  if ('CodexWindowNativeMethods' -as [type]) {
    return
  }

  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CodexWindowNativeMethods {
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")]
  private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

  public static void NewWindow(IntPtr expectedWindow) {
    if (GetForegroundWindow() != expectedWindow)
      throw new InvalidOperationException("ChatGPT is no longer focused; native shortcut cancelled.");
    keybd_event(0x11, 0, 0, UIntPtr.Zero);
    keybd_event(0x10, 0, 0, UIntPtr.Zero);
    try {
      keybd_event(0x7B, 0, 0, UIntPtr.Zero);
      keybd_event(0x7B, 0, 2, UIntPtr.Zero);
    } finally {
      keybd_event(0x10, 0, 2, UIntPtr.Zero);
      keybd_event(0x11, 0, 2, UIntPtr.Zero);
    }
  }
}
'@
}

function Get-CodexWindowProcessId {
  param($Window)

  if (-not $Window.handle) {
    return 0
  }

  try {
    Initialize-CodexWindowProcessApi
    [uint32]$processId = 0
    [void][CodexWindowNativeMethods]::GetWindowThreadProcessId(
      [IntPtr]::new([int64]$Window.handle),
      [ref]$processId
    )
    if (-not $processId) {
      return 0
    }

    return [int]$processId
  } catch {
    Write-LauncherLog "Could not inspect ChatGPT window '$($Window.id)': $($_.Exception.Message)"
    return 0
  }
}

function Get-PrimaryCodexProcess {
  # Legacy per-workspace profiles must never be used as the shared app instance.
  Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" -ErrorAction Stop |
    Where-Object {
      $_.CommandLine -and $_.CommandLine -notmatch '(?i)--type=|--user-data-dir' -and
      $_.ExecutablePath -match '(?i)\\(app\\)?(ChatGPT|Codex)\.exe$' -and
      $_.ExecutablePath -match '(?i)WindowsApps\\OpenAI\.'
    } | Sort-Object CreationDate | Select-Object -First 1
}

function Test-CodexContainerContains {
  param($Container, [string]$WindowId)
  if ($Container.id -eq $WindowId) { return $true }
  foreach ($child in $Container.children) {
    if (Test-CodexContainerContains $child $WindowId) { return $true }
  }
  return $false
}

function Get-PrimaryCodexWindows {
  param([int]$PrimaryProcessId)
  @(Get-CodexWindows | Where-Object { (Get-CodexWindowProcessId $_) -eq $PrimaryProcessId })
}

function Wait-ForNewCodexWindow {
  param(
    [string[]]$BeforeIds,
    [int]$PrimaryProcessId,
    [int]$TimeoutMilliseconds
  )

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  do {
    Start-Sleep -Milliseconds 250
    $newWindow = Get-PrimaryCodexWindows $PrimaryProcessId |
      Where-Object { $_.id -notin $BeforeIds } | Select-Object -First 1
    if ($newWindow) {
      return $newWindow
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  return $null
}

function Resolve-CodexExecutable {
  $packages = @(
    Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
    Get-AppxPackage -Name 'OpenAI.ChatGPT' -ErrorAction SilentlyContinue
    Get-AppxPackage -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^OpenAI\.(Codex|ChatGPT)' }
  ) | Sort-Object Version -Descending -Unique

  foreach ($package in $packages) {
    foreach ($relativePath in @('app\ChatGPT.exe', 'ChatGPT.exe', 'app\Codex.exe')) {
      $candidate = Join-Path $package.InstallLocation $relativePath
      if (Test-Path -LiteralPath $candidate) {
        return $candidate
      }
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

function Start-PrimaryCodexInstance {
  $executable = Resolve-CodexExecutable
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $executable
  $startInfo.WorkingDirectory = Split-Path -Parent $executable
  $startInfo.UseShellExecute = $false
  $startInfo.EnvironmentVariables.Remove('CODEX_ELECTRON_USER_DATA_PATH')

  $process = [Diagnostics.Process]::Start($startInfo)
  if (-not $process) {
    throw 'Failed to start the shared ChatGPT instance.'
  }

  Write-LauncherLog "Requested shared ChatGPT startup (PID $($process.Id))."
}

function Request-NativeCodexWindow {
  param($SourceWindow)
  Initialize-CodexWindowProcessApi
  # The physical Alt+C chord must be released before sending an app shortcut.
  $deadline = [DateTime]::UtcNow.AddSeconds(3)
  do {
    $held = @(0x12, 0x11, 0x10, 0x43 | Where-Object {
      ([CodexWindowNativeMethods]::GetAsyncKeyState($_) -band 0x8000) -ne 0
    })
    if ($held.Count -eq 0) { break }
    Start-Sleep -Milliseconds 40
  } while ([DateTime]::UtcNow -lt $deadline)
  if ($held.Count -gt 0) { throw 'Release Alt+C before requesting a native window.' }

  & $cli command focus --container-id $SourceWindow.id | Out-Null
  $deadline = [DateTime]::UtcNow.AddSeconds(2)
  while ([CodexWindowNativeMethods]::GetForegroundWindow().ToInt64() -ne $SourceWindow.handle) {
    if ([DateTime]::UtcNow -ge $deadline) { throw 'Could not focus the shared ChatGPT window.' }
    Start-Sleep -Milliseconds 50
  }
  [CodexWindowNativeMethods]::NewWindow([IntPtr]::new([int64]$SourceWindow.handle))
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

    $workspace = (Invoke-GlazeQuery @('query', 'workspaces')).data.workspaces |
      Where-Object { $_.name -eq $TargetWorkspace } | Select-Object -First 1
    if ($workspace -and (Test-CodexContainerContains $workspace $WindowId)) {
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

  & (Join-Path $PSScriptRoot 'configure-codex-native-window.ps1')

  if ($TargetWorkspace) {
    $requested = (Invoke-GlazeQuery @('query', 'workspaces')).data.workspaces |
      Where-Object { $_.name -eq $TargetWorkspace } | Select-Object -First 1
    # With toggle_workspace_on_refocus enabled, focusing the active workspace leaves it.
    if (-not $requested.hasFocus) {
      & $cli command focus --workspace $TargetWorkspace | Out-Null
    }
  }

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

  $primary = Get-PrimaryCodexProcess
  if (-not $primary) {
    Start-PrimaryCodexInstance
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
      Start-Sleep -Milliseconds 250
      $primary = Get-PrimaryCodexProcess
      $primaryWindows = if ($primary) { @(Get-PrimaryCodexWindows $primary.ProcessId) } else { @() }
    } while ($primaryWindows.Count -eq 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($primaryWindows.Count -eq 0) { throw 'The shared ChatGPT instance did not expose a window.' }
    $placed = Move-CodexWindowToTarget $primaryWindows[0].id $targetWorkspace $targetWorkspaceObject.id
    if (-not $placed) { throw 'The first shared ChatGPT window could not be placed in the requested workspace.' }
    Write-LauncherLog "Started shared ChatGPT window '$($primaryWindows[0].id)' in workspace '$targetWorkspace'."
    return
  }

  $primaryWindows = @(Get-PrimaryCodexWindows $primary.ProcessId)
  if ($primaryWindows.Count -eq 0) {
    # A tray-only instance is activated by a normal second launch, still using one profile.
    Start-PrimaryCodexInstance
    $window = Wait-ForNewCodexWindow @() $primary.ProcessId 15000
    if (-not $window) { throw 'The shared ChatGPT instance did not restore a window.' }
    $placed = Move-CodexWindowToTarget $window.id $targetWorkspace $targetWorkspaceObject.id
    if (-not $placed) { throw 'The restored ChatGPT window could not be placed in the requested workspace.' }
    Write-LauncherLog "Restored shared ChatGPT window '$($window.id)' in workspace '$targetWorkspace'."
    return
  }

  $existingCodexWindow = $primaryWindows | Where-Object {
    Test-CodexContainerContains $targetWorkspaceObject $_.id
  } | Select-Object -First 1
  if ($existingCodexWindow) {
    & $cli command focus --container-id $existingCodexWindow.id | Out-Null
    Write-LauncherLog "Reused shared ChatGPT window '$($existingCodexWindow.id)' in workspace '$targetWorkspace'."
    return
  }

  $beforeCodexIds = @(Get-CodexWindows | ForEach-Object { $_.id })
  $newWindow = $null

  Write-LauncherLog "Alt+C requested from workspace '$targetWorkspace'; shared process: $($primary.ProcessId)."

  Request-NativeCodexWindow $primaryWindows[0]
  $newWindow = Wait-ForNewCodexWindow $beforeCodexIds $primary.ProcessId 15000

  if ($newWindow) {
    $placed = Move-CodexWindowToTarget $newWindow.id $targetWorkspace $targetWorkspaceObject.id
    if ($placed) {
      Write-LauncherLog "Created native ChatGPT window '$($newWindow.id)' in workspace '$targetWorkspace' using shared PID $($primary.ProcessId)."
    } else {
      throw "Native ChatGPT window '$($newWindow.id)' appeared, but placement in workspace '$targetWorkspace' was not confirmed."
    }
  } else {
    Return-ToTargetWorkspace $targetWorkspace $targetContainerId
    throw 'The native New Window command did not create a window. Restart the main ChatGPT app after saving work to reload its keybindings.'
  }
} catch {
  Write-LauncherLog "Launcher error: $($_.Exception.Message)"
  if ($targetWorkspace) { Return-ToTargetWorkspace $targetWorkspace $targetContainerId }
  Write-Error $_ -ErrorAction Continue
  exit 1
} finally {
  if ($lockTaken) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
