param(
  [string] $FontPackageId = 'DEVCOM.JetBrainsMonoNerdFont'
)

$ErrorActionPreference = 'Stop'
$fontFace = 'JetBrainsMono NFM'
$fontsKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$fontRegistry = Get-ItemProperty -Path $fontsKey -ErrorAction SilentlyContinue | Out-String
$fontInstalled = $fontRegistry -match 'JetBrainsMono'

if (-not $fontInstalled) {
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $winget) {
    throw 'WinGet was not found. Install a JetBrainsMono Nerd Font manually, then rerun the installer.'
  }

  & $winget.Source install --id $FontPackageId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
  if ($LASTEXITCODE -ne 0) {
    throw "WinGet could not install $FontPackageId. Install a JetBrainsMono Nerd Font manually."
  }
}

[pscustomobject]@{
  Font = $fontFace
  Installed = $true
}

