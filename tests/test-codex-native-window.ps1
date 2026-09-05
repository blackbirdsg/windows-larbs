$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$configure = Join-Path $root 'glazewm\configure-codex-native-window.ps1'
$launcher = Join-Path $root 'glazewm\glazewm-launch-codex.ps1'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('codex-window-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$keymap = Join-Path $testDirectory 'keybindings.json'
function Assert-True($Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
  Write-Output "PASS $Message"
}
function Write-Fixture([object[]]$Bindings) {
  [IO.File]::WriteAllText($keymap, (ConvertTo-Json -InputObject $Bindings), [Text.UTF8Encoding]::new($false))
}
try {
  Write-Fixture @(
    @{command='newWindow';key=$null},
    @{command='openThreadInNewWindow';key='Ctrl+Shift+N'},
    @{command='quickChat';key=$null}
  )
  $original = [IO.File]::ReadAllText($keymap)
  & $configure -KeymapPath $keymap
  $parsed = Get-Content -LiteralPath $keymap -Raw | ConvertFrom-Json
  Assert-True (@($parsed).Count -eq 3) 'Preserve unrelated shortcuts without nesting the JSON array (PowerShell 5.1).'
  Assert-True (@($parsed | Where-Object { $_.command -eq 'newWindow' -and $_.key -eq 'Ctrl+Shift+F12' }).Count -eq 1) 'Enable exactly one native New Window binding.'
  $backup = Get-ChildItem -LiteralPath $testDirectory -Filter '*.bak' | Select-Object -First 1
  Assert-True ([IO.File]::ReadAllText($backup.FullName) -ceq $original) 'Back up the original keymap verbatim.'
  $hash = (Get-FileHash -LiteralPath $keymap).Hash
  & $configure -KeymapPath $keymap
  Assert-True ((Get-FileHash -LiteralPath $keymap).Hash -eq $hash) 'Repeated launch leaves the keymap unchanged.'

  Write-Fixture @(@{command='otherCommand';key='Shift+Control+F12'})
  $hash = (Get-FileHash -LiteralPath $keymap).Hash
  $caught = $false
  try { & $configure -KeymapPath $keymap } catch { $caught = $true }
  Assert-True ($caught -and (Get-FileHash -LiteralPath $keymap).Hash -eq $hash) 'Reject equivalent conflicting shortcuts without overwriting them.'

  Write-Fixture @(@{command='newWindow';key='Ctrl+Alt+N'})
  & $configure -KeymapPath $keymap
  $parsed = Get-Content -LiteralPath $keymap -Raw | ConvertFrom-Json
  Assert-True (@($parsed).Count -eq 2) 'Keep an existing New Window accelerator when adding the launcher binding.'

  [IO.File]::WriteAllText($keymap, '{invalid json')
  $caught = $false
  try { & $configure -KeymapPath $keymap } catch { $caught = $true }
  Assert-True ($caught -and [IO.File]::ReadAllText($keymap) -eq '{invalid json') 'Reject invalid keymaps without replacing them.'

  # Load only pure function definitions; never execute the interactive launcher in unit tests.
  $ast = [Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$null, [ref]$null)
  $fn = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-CodexContainerContains'}, $true)
  . ([scriptblock]::Create($fn.Extent.Text))
  $workspace = @{ id='workspace';children=@(@{id='split';children=@(@{id='window';children=@()})}) }
  Assert-True (Test-CodexContainerContains $workspace 'window') 'Find a window inside a nested tiling split.'
  Assert-True (-not (Test-CodexContainerContains $workspace 'elsewhere')) 'Do not reuse a window from another workspace.'
} finally {
  $resolved = [IO.Path]::GetFullPath($testDirectory)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolved) -like 'codex-window-test-*') {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
