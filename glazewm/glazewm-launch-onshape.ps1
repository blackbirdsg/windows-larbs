$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$url = Get-DesktopProfileSetting -Section 'Urls' -Name 'Onshape' -Default 'https://cad.onshape.com/documents'
Start-DesktopProfileBrowser -Url $url -NewWindow
