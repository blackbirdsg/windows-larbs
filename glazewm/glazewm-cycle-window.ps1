param(
  [ValidateSet('next', 'prev')]
  [string]$Direction = 'next'
)

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$cliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
if (-not $cliResult) {
  exit 1
}
$cli = $cliResult.Value

$windowsResult = & $cli query windows | ConvertFrom-Json
if (-not $windowsResult.success) {
  exit 1
}

$windows = @(
  $windowsResult.data.windows |
    Where-Object { $_.type -eq 'window' -and $_.displayState -eq 'shown' }
)

if ($windows.Count -lt 2) {
  exit 0
}

$focusedIndex = -1
for ($i = 0; $i -lt $windows.Count; $i++) {
  if ($windows[$i].hasFocus) {
    $focusedIndex = $i
    break
  }
}

if ($focusedIndex -lt 0) {
  exit 0
}

if ($Direction -eq 'next') {
  $targetIndex = ($focusedIndex + 1) % $windows.Count
} else {
  $targetIndex = ($focusedIndex - 1 + $windows.Count) % $windows.Count
}

& $cli command focus --container-id $windows[$targetIndex].id | Out-Null
