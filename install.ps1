[CmdletBinding()]
param(
  [switch] $InstallPackages,
  [switch] $InstallOptionalApps,
  [switch] $SkipReload,
  [switch] $ConfigureWindowsTerminal,
  [switch] $SkipWindowsTerminal,
  [switch] $RuntimeOnly,
  [string] $SettingsPath = '',
  [string] $InstallRoot = ''
)

$installer = Join-Path $PSScriptRoot 'install-desktop-profile.ps1'
& $installer @PSBoundParameters
exit $LASTEXITCODE
