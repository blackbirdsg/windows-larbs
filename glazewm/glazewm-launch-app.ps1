param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('KiCad', 'BambuStudio', 'Wireshark', 'GoogleEarth', 'QGIS', 'OBS', 'PowerToysRun')]
  [string] $Name
)

$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

try {
  Start-DesktopProfileApp -Name $Name
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}

