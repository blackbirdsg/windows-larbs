[CmdletBinding()]
param([string] $KeymapPath = '')

$ErrorActionPreference = 'Stop'
$Accelerator = 'Ctrl+Shift+F12'
if (-not $KeymapPath) {
  $codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
  $KeymapPath = Join-Path $codexDirectory 'keybindings.json'
}

$bindings = @()
if (Test-Path -LiteralPath $KeymapPath) {
  $raw = Get-Content -LiteralPath $KeymapPath -Raw
  if (-not $raw.TrimStart().StartsWith('[')) {
    throw "Expected a JSON array in $KeymapPath; existing keybindings were not changed."
  }
  $parsed = $raw | ConvertFrom-Json
  $bindings = @($parsed | Where-Object { $null -ne $_ })
  foreach ($binding in $bindings) {
    if (-not ($binding.command -is [string]) -or
        ($null -ne $binding.key -and $binding.key -isnot [string])) {
      throw "Invalid keybinding in $KeymapPath; existing keybindings were not changed."
    }
  }
}
function Get-NormalizedAccelerator([string]$Value) {
  (($Value.ToLowerInvariant() -replace 'cmdorctrl|commandorcontrol|control', 'ctrl') -split '\+' |
    ForEach-Object { $_.Trim() } | Sort-Object) -join '+'
}
$normalizedKey = Get-NormalizedAccelerator $Accelerator
if ($bindings | Where-Object {
  $_.command -ne 'newWindow' -and $_.key -and (Get-NormalizedAccelerator $_.key) -eq $normalizedKey
}) {
  throw "The native-window shortcut $Accelerator is already assigned to another command in $KeymapPath."
}
if ($bindings | Where-Object {
  $_.command -eq 'newWindow' -and $_.key -and (Get-NormalizedAccelerator $_.key) -eq $normalizedKey
}) {
  return
}

New-Item -ItemType Directory -Path (Split-Path -Parent $KeymapPath) -Force | Out-Null
if (Test-Path -LiteralPath $KeymapPath) {
  $backup = "$KeymapPath.before-native-windows-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').bak"
  Copy-Item -LiteralPath $KeymapPath -Destination $backup
}
# Preserve other shortcuts and any existing native-window accelerators.
$bindings = @($bindings | Where-Object { $_.command -ne 'newWindow' -or $_.key })
$bindings += [pscustomobject]@{ command = 'newWindow'; key = $Accelerator }
$json = ConvertTo-Json -InputObject $bindings -Depth 20
[IO.File]::WriteAllText($KeymapPath, $json, [Text.UTF8Encoding]::new($false))
