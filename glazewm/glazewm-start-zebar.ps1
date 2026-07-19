$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$zebarResult = Resolve-DesktopProfileApp -Name 'Zebar'
$zebar = if ($zebarResult) { $zebarResult.Value } else { '' }
$wirelessUpdater = Join-Path $profileRoot 'zebar\update-wireless-status.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'glzr-startup'
$logPath = Join-Path $logDir 'zebar-startup.log'
$mutex = [System.Threading.Mutex]::new($false, 'Local\GlazeWM-Zebar-Startup')
$hasLock = $false

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-StartupLog {
  param([string] $Message)
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -LiteralPath $logPath -Value "$stamp $Message"
}

try {
  try {
    $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
  } catch [System.Threading.AbandonedMutexException] {
    $hasLock = $true
  }

  if (-not $hasLock) {
    Write-StartupLog 'Another Zebar startup request is still running.'
    exit 0
  }

  # GlazeWM is already running when this script is called; only give its
  # providers a short moment to become available.
  Start-Sleep -Milliseconds 750

  if (-not $zebar -or -not (Test-Path -LiteralPath $zebar)) {
    Write-StartupLog 'Missing Zebar executable.'
    exit 1
  }

  if (Test-Path -LiteralPath $wirelessUpdater) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      $wirelessUpdater
    ) -WindowStyle Hidden
  }

  if (Get-Process -Name 'zebar' -ErrorAction SilentlyContinue) {
    Write-StartupLog 'Zebar already running.'
    exit 0
  }

  Write-StartupLog 'Starting Zebar startup config.'
  $process = Start-Process -FilePath $zebar -ArgumentList 'startup' -WindowStyle Hidden -PassThru
  Write-StartupLog "Zebar process started with PID $($process.Id)."
} catch {
  Write-StartupLog "Startup failed: $($_.Exception.Message)"
  exit 1
} finally {
  if ($hasLock) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
