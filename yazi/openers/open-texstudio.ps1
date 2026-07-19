param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Paths
)

$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$texstudioResult = Resolve-DesktopProfileApp -Name 'TeXstudio'
$glazewmResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
$texstudio = if ($texstudioResult -and $texstudioResult.Kind -eq 'Path') { $texstudioResult.Value } else { '' }
$glazewm = if ($glazewmResult) { $glazewmResult.Value } else { '' }

function Invoke-GlazeQuery {
  param([string[]]$Arguments)

  if (-not (Test-Path -LiteralPath $glazewm)) {
    return $null
  }

  $json = & $glazewm @Arguments
  if (-not $json) {
    return $null
  }

  return $json | ConvertFrom-Json
}

function Get-CurrentWorkspaceName {
  $workspacesResult = Invoke-GlazeQuery @('query', 'workspaces')
  $focusedWorkspace = $workspacesResult.data.workspaces |
    Where-Object { $_.hasFocus } |
    Select-Object -First 1

  return $focusedWorkspace.name
}

function Get-TexstudioWindowIds {
  $windowsResult = Invoke-GlazeQuery @('query', 'windows')
  @(
    $windowsResult.data.windows |
      Where-Object { $_.processName -eq 'texstudio' } |
      ForEach-Object { $_.id }
  )
}

if (-not (Test-Path -LiteralPath $texstudio)) {
  Start-Process -FilePath 'wt.exe' -ArgumentList @(
    'powershell.exe',
    '-NoExit',
    '-Command',
    "Write-Host 'TeXstudio was not found. Set Apps.TeXstudio in settings.local.psd1.' -ForegroundColor Yellow"
  )
  return
}

$files = @($Paths | Where-Object { $_ } | ForEach-Object {
  (Resolve-Path -LiteralPath $_).Path
})

if ($files.Count -eq 0) {
  return
}

$targetWorkspace = Get-CurrentWorkspaceName
$beforeWindowIds = @(Get-TexstudioWindowIds)

# Keep each Yazi-opened document in its own TeXstudio instance/window.
$arguments = @('--start-always') + @($files | ForEach-Object { '"{0}"' -f $_.Replace('"', '\"') })
Start-Process -FilePath $texstudio -ArgumentList $arguments

if (-not $targetWorkspace) {
  return
}

for ($i = 0; $i -lt 50; $i++) {
  Start-Sleep -Milliseconds 200
  $newWindowId = Get-TexstudioWindowIds |
    Where-Object { $_ -notin $beforeWindowIds } |
    Select-Object -First 1

  if ($newWindowId) {
    & $glazewm command --id $newWindowId move --workspace $targetWorkspace | Out-Null
    & $glazewm command --id $newWindowId set-tiling | Out-Null
    & $glazewm command focus --workspace $targetWorkspace | Out-Null
    & $glazewm command focus --container-id $newWindowId | Out-Null
    break
  }
}
