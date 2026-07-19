param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Paths
)

$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$nvimResult = Resolve-DesktopProfileApp -Name 'Neovim'
$nvim = if ($nvimResult -and $nvimResult.Kind -eq 'Path') { $nvimResult.Value } else { '' }
$terminalResult = Resolve-DesktopProfileApp -Name 'WindowsTerminal'
$terminal = if ($terminalResult -and $terminalResult.Kind -eq 'Path') { $terminalResult.Value } else { '' }

if (-not (Test-Path -LiteralPath $nvim)) {
  Start-Process -FilePath 'wt.exe' -ArgumentList @(
    'powershell.exe',
    '-NoExit',
    '-Command',
    "Write-Host 'Neovim was not found.' -ForegroundColor Yellow"
  )
  return
}

if (-not (Test-Path -LiteralPath $terminal)) {
  Show-DesktopProfileError -Message 'Windows Terminal was not found.'
  return
}

$files = @($Paths | Where-Object { $_ } | ForEach-Object {
  (Resolve-Path -LiteralPath $_).Path
})

if ($files.Count -eq 0) {
  return
}

$workingDir = Split-Path -LiteralPath $files[0] -Parent
$quotedFiles = $files | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }
$script = @"
Set-Location -LiteralPath '$($workingDir -replace "'", "''")'
& '$($nvim -replace "'", "''")' @(
$($quotedFiles -join ",`n")
)
"@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))

Start-Process -FilePath $terminal -ArgumentList @(
  '-d',
  ('"{0}"' -f $workingDir.Replace('"', '\"')),
  'powershell.exe',
  '-NoExit',
  '-EncodedCommand',
  $encoded
)
