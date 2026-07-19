$guide = Join-Path $PSScriptRoot 'glazewm-shortcuts.html'
$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$uri = [System.Uri]::new($guide).AbsoluteUri
Start-DesktopProfileBrowser -Url $uri -NewWindow
