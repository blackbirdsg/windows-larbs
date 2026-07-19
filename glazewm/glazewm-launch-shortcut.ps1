param(
  [Parameter(Mandatory = $true)]
  [string] $Shortcut
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Shortcut)) {
  Start-Process -FilePath 'wt.exe' -ArgumentList @(
    'powershell.exe',
    '-NoExit',
    '-Command',
    "Write-Host 'Shortcut not found: $Shortcut' -ForegroundColor Yellow"
  )
  return
}

Start-Process -FilePath $Shortcut
