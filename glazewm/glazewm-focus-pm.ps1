$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$cliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
if (-not $cliResult) {
  Show-DesktopProfileError -Message 'GlazeWM CLI was not found.'
  return
}

$cli = $cliResult.Value
$workspaceName = '1'
$url = Get-DesktopProfileSetting -Section 'Urls' -Name 'ProjectManagement' -Default ''
$logPath = Join-Path $env:LOCALAPPDATA 'glzr-startup\pm-workspace.log'

function Write-PmLog {
  param([string]$Message)

  try {
    $logDirectory = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $logDirectory)) {
      New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    Add-Content -LiteralPath $logPath -Value ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message)
  } catch {
    # Logging must never prevent workspace switching.
  }
}

function Invoke-GlazeQuery {
  param([string[]]$Arguments)

  $json = & $cli @Arguments 2>$null
  if (-not $json) {
    return $null
  }
  return $json | ConvertFrom-Json
}

function Get-PmWorkspace {
  $workspacesResult = Invoke-GlazeQuery @('query', 'workspaces')
  $workspacesResult.data.workspaces |
    Where-Object { $_.name -eq $workspaceName } |
    Select-Object -First 1
}

function Get-OpenProjectWindows {
  $windowsResult = Invoke-GlazeQuery @('query', 'windows')
  @(
    $windowsResult.data.windows |
      Where-Object {
        $_.processName -eq 'brave' -and
        ($_.title -match 'OpenProject|Project management')
      }
  )
}

function Focus-PmWorkspace {
  $workspace = Get-PmWorkspace
  if (-not $workspace) {
    & $cli command focus --workspace $workspaceName | Out-Null
  } elseif (-not $workspace.hasFocus) {
    & $cli command focus --workspace $workspaceName | Out-Null
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(4)
  do {
    Start-Sleep -Milliseconds 100
    $workspace = Get-PmWorkspace
    if ($workspace -and $workspace.hasFocus) {
      return $workspace
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  return $null
}

function Move-OpenProjectToPm {
  param(
    $Window,
    [string]$PmWorkspaceId
  )

  for ($i = 0; $i -lt 6; $i++) {
    $current = Get-OpenProjectWindows |
      Where-Object { $_.id -eq $Window.id } |
      Select-Object -First 1
    if ($current -and $current.parentId -eq $PmWorkspaceId) {
      & $cli command --id $Window.id set-tiling | Out-Null
      return $true
    }

    & $cli command --id $Window.id move --workspace $workspaceName | Out-Null
    Start-Sleep -Milliseconds 250
  }

  return $false
}

function Close-OpenProjectDuplicates {
  param([string]$KeepWindowId)

  $duplicates = Get-OpenProjectWindows |
    Where-Object { $_.id -ne $KeepWindowId }
  foreach ($duplicate in $duplicates) {
    Write-PmLog "Closing duplicate OpenProject window '$($duplicate.id)' from workspace parent '$($duplicate.parentId)'."
    & $cli command --id $duplicate.id close | Out-Null
    Start-Sleep -Milliseconds 150
  }
}

function Show-OpenProjectWindow {
  param(
    $Window,
    $PmWorkspace
  )

  $placed = Move-OpenProjectToPm $Window $PmWorkspace.id
  Close-OpenProjectDuplicates $Window.id
  Focus-PmWorkspace | Out-Null
  & $cli command focus --container-id $Window.id | Out-Null

  if ($placed) {
    Write-PmLog "Focused OpenProject window '$($Window.id)' in PM workspace."
  } else {
    Write-PmLog "OpenProject window '$($Window.id)' was found, but placement in PM was not confirmed."
  }
}

$mutex = [System.Threading.Mutex]::new($false, 'Local\GlazeWM-Pm-Workspace')
$lockTaken = $false

try {
  try {
    $lockTaken = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $lockTaken = $true
  }

  if (-not $lockTaken) {
    Write-PmLog 'Ignored overlapping Alt+1 invocation.'
    return
  }

  $pmWorkspace = Focus-PmWorkspace
  if (-not $pmWorkspace) {
    throw 'GlazeWM did not confirm focus on the PM workspace.'
  }

  $existingWindows = @(Get-OpenProjectWindows)
  if ($existingWindows.Count -gt 0) {
    $existing = $existingWindows |
      Sort-Object @{
        Expression = {
          if ($_.parentId -eq $pmWorkspace.id) { 0 }
          elseif ($_.displayState -eq 'shown') { 1 }
          else { 2 }
        }
      } |
      Select-Object -First 1
    Show-OpenProjectWindow $existing $pmWorkspace
    return
  }

  if (-not $url) {
    Write-PmLog 'PM workspace focused without launching OpenProject because no URL is configured.'
    return
  }

  $beforeBraveIds = @(
    (Invoke-GlazeQuery @('query', 'windows')).data.windows |
      Where-Object { $_.processName -eq 'brave' } |
      ForEach-Object { $_.id }
  )

  Write-PmLog 'No OpenProject window exists; launching one in PM.'
  Start-DesktopProfileBrowser -Url $url -NewWindow

  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 200

    $windowsResult = Invoke-GlazeQuery @('query', 'windows')
    $newBraveWindow = $windowsResult.data.windows |
      Where-Object { $_.processName -eq 'brave' -and $_.id -notin $beforeBraveIds } |
      Select-Object -First 1
    if ($newBraveWindow -and $newBraveWindow.parentId -ne $pmWorkspace.id) {
      & $cli command --id $newBraveWindow.id move --workspace $workspaceName | Out-Null
    }

    $opened = Get-OpenProjectWindows |
      Where-Object { $_.id -notin $beforeBraveIds } |
      Select-Object -First 1
    if (-not $opened) {
      $opened = Get-OpenProjectWindows | Select-Object -First 1
    }

    if ($opened) {
      Show-OpenProjectWindow $opened $pmWorkspace
      return
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  Focus-PmWorkspace | Out-Null
  Write-PmLog 'OpenProject launch timed out before a matching Brave window appeared.'
} catch {
  Write-PmLog "PM launcher error: $($_.Exception.Message)"
} finally {
  if ($lockTaken) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
