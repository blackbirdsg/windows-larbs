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

function Invoke-GlazeQuery {
  param([string[]]$Arguments)
  $json = & $cli @Arguments
  if (-not $json) {
    return $null
  }
  return $json | ConvertFrom-Json
}

function Get-ContainerWindows {
  param($Container)

  if (-not $Container) {
    return @()
  }

  if ($Container.type -eq 'window') {
    return @($Container)
  }

  @($Container.children | ForEach-Object { Get-ContainerWindows $_ })
}

function Get-Workspace {
  $workspacesResult = Invoke-GlazeQuery @('query', 'workspaces')
  $workspacesResult.data.workspaces |
    Where-Object { $_.name -eq $workspaceName } |
    Select-Object -First 1
}

function Get-OpenProjectWindow {
  $workspace = Get-Workspace
  Get-ContainerWindows $workspace |
    Where-Object {
      $_.processName -eq 'brave' -and
      ($_.title -match 'OpenProject|Project management')
    } |
    Select-Object -First 1
}

function Get-BraveWindowIds {
  $windowsResult = Invoke-GlazeQuery @('query', 'windows')
  @(
    $windowsResult.data.windows |
      Where-Object { $_.processName -eq 'brave' } |
      ForEach-Object { $_.id }
  )
}

& $cli command focus --workspace $workspaceName | Out-Null

$existing = Get-OpenProjectWindow
if ($existing) {
  & $cli command focus --container-id $existing.id | Out-Null
  return
}

$beforeIds = @(Get-BraveWindowIds)

if (-not $url) {
  return
}

Start-DesktopProfileBrowser -Url $url -NewWindow

for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 200
  $windowsResult = Invoke-GlazeQuery @('query', 'windows')
  $newWindow = $windowsResult.data.windows |
    Where-Object { $_.processName -eq 'brave' -and $_.id -notin $beforeIds } |
    Select-Object -First 1

  if ($newWindow) {
    & $cli command --id $newWindow.id move --workspace $workspaceName | Out-Null
    & $cli command --id $newWindow.id set-tiling | Out-Null
    & $cli command focus --workspace $workspaceName | Out-Null
    & $cli command focus --container-id $newWindow.id | Out-Null
    return
  }
}

& $cli command focus --workspace $workspaceName | Out-Null
