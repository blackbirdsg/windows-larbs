$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$glazeResult = Resolve-DesktopProfileApp -Name 'GlazeWM'
$glazeCliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
$glaze = if ($glazeResult) { $glazeResult.Value } else { '' }
$glazeCli = if ($glazeCliResult) { $glazeCliResult.Value } else { '' }
$explorer = Join-Path $env:WINDIR 'explorer.exe'
$zebarLauncher = Join-Path $PSScriptRoot 'glazewm-start-zebar.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'glzr-startup'
$logPath = Join-Path $logDir 'desktop-startup.log'
$mutex = [System.Threading.Mutex]::new($false, 'Local\GlazeWM-Desktop-Startup')
$hasLock = $false

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-StartupLog {
  param([string] $Message)

  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -LiteralPath $logPath -Value "$stamp $Message"
}

function Get-GlazeProcess {
  Get-Process -Name 'glazewm' -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

function Test-GlazeHealthy {
  $process = Get-GlazeProcess
  if (-not $process) {
    return $false
  }

  try {
    $response = & $glazeCli query workspaces 2>$null
    return $LASTEXITCODE -eq 0 -and [bool]$response
  } catch {
    return $false
  }
}

function Wait-GlazeHealthy {
  param([int] $TimeoutSeconds = 20)

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $consecutiveHealthyChecks = 0

  do {
    if (Test-GlazeHealthy) {
      $consecutiveHealthyChecks++
      if ($consecutiveHealthyChecks -ge 3) {
        return Get-GlazeProcess
      }
    } else {
      $consecutiveHealthyChecks = 0
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return $null
}

function Test-GlazeStability {
  param([int] $Seconds = 12)

  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (-not (Test-GlazeHealthy)) {
      return $false
    }
    Start-Sleep -Seconds 1
  }

  return $true
}

function Remove-UnhealthyGlazeProcess {
  $process = Get-GlazeProcess
  if (-not $process) {
    return
  }

  Write-StartupLog "Stopping unhealthy GlazeWM process PID $($process.Id) before retry."
  Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
}

function Start-ZebarIfNeeded {
  if (Get-Process -Name 'zebar' -ErrorAction SilentlyContinue) {
    return
  }

  if (-not (Test-Path -LiteralPath $zebarLauncher)) {
    Write-StartupLog "Missing Zebar launcher: $zebarLauncher"
    return
  }

  Write-StartupLog 'Zebar did not follow GlazeWM; starting the fallback launcher.'
  Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    $zebarLauncher
  ) -WindowStyle Hidden
}

try {
  try {
    $hasLock = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
  } catch [System.Threading.AbandonedMutexException] {
    $hasLock = $true
  }

  if (-not $hasLock) {
    Write-StartupLog 'Another desktop startup request is still running.'
    exit 0
  }

  Write-StartupLog 'Desktop startup health check began.'

  if (-not $glaze -or -not (Test-Path -LiteralPath $glaze)) {
    Write-StartupLog 'Missing GlazeWM executable.'
    exit 1
  }

  if (-not $glazeCli -or -not (Test-Path -LiteralPath $glazeCli)) {
    Write-StartupLog 'Missing GlazeWM CLI.'
    exit 1
  }

  $shellDeadline = (Get-Date).AddSeconds(30)
  while (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -ge $shellDeadline) {
      Write-StartupLog 'Windows Explorer was not ready within 30 seconds.'
      exit 1
    }
    Start-Sleep -Milliseconds 500
  }

  $stable = $false
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $runningGlaze = Get-GlazeProcess
    if ($runningGlaze) {
      Write-StartupLog "Attempt ${attempt}: checking GlazeWM PID $($runningGlaze.Id)."
    } else {
      Write-StartupLog "Attempt ${attempt}: handing GlazeWM launch to Windows Explorer."
      Start-Process -FilePath $explorer -ArgumentList @($glaze)
    }

    $healthyGlaze = Wait-GlazeHealthy 20
    if ($healthyGlaze) {
      Write-StartupLog "GlazeWM IPC became ready with PID $($healthyGlaze.Id); checking stability."
      if (Test-GlazeStability 12) {
        $stable = $true
        Write-StartupLog "GlazeWM remained healthy with PID $($healthyGlaze.Id)."
        break
      }

      Write-StartupLog "Attempt ${attempt}: GlazeWM lost IPC or exited during the stability check."
    } else {
      Write-StartupLog "Attempt ${attempt}: GlazeWM did not establish healthy IPC within 20 seconds."
    }

    Remove-UnhealthyGlazeProcess
    if ($attempt -lt 3) {
      Start-Sleep -Seconds 3
    }
  }

  if (-not $stable) {
    Write-StartupLog 'GlazeWM failed all three startup attempts.'
    exit 1
  }

  $zebarDeadline = (Get-Date).AddSeconds(10)
  while (-not (Get-Process -Name 'zebar' -ErrorAction SilentlyContinue)) {
    if (-not (Test-GlazeHealthy)) {
      Write-StartupLog 'GlazeWM stopped while waiting for Zebar.'
      exit 1
    }
    if ((Get-Date) -ge $zebarDeadline) {
      Start-ZebarIfNeeded
      break
    }
    Start-Sleep -Milliseconds 500
  }

  if (-not (Test-GlazeHealthy)) {
    Write-StartupLog 'GlazeWM was no longer healthy at the end of desktop startup.'
    exit 1
  }

  Write-StartupLog 'Desktop startup completed successfully.'
  exit 0
} catch {
  Write-StartupLog "Desktop startup failed: $($_.Exception.Message)"
  exit 1
} finally {
  if ($hasLock) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
