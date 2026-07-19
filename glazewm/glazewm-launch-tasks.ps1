$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$tasksUrl = Get-DesktopProfileSetting -Section 'Urls' -Name 'Tasks' -Default 'https://tasks.google.com/tasks/'
Start-DesktopProfileBrowser -Url $tasksUrl -NewWindow
