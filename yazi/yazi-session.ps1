$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$env:YAZI_FILE_ONE = 'C:\Program Files\Git\usr\bin\file.exe'
$yaziResult = Resolve-DesktopProfileApp -Name 'Yazi'
$yazi = if ($yaziResult -and $yaziResult.Kind -eq 'Path') { $yaziResult.Value } else { '' }

chcp.com 65001 | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$env:LANG = 'en_US.UTF-8'

if (-not (Test-Path -LiteralPath $yazi)) {
  Write-Host "Yazi executable not found." -ForegroundColor Red
  Write-Host "Try opening a new terminal, or reinstall with: winget install --id sxyazi.yazi --exact"
  return
}

& $yazi
