$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$url = Get-DesktopProfileSetting -Section 'Urls' -Name 'ProjectManagement' -Default ''
if (-not $url) {
  Show-DesktopProfileError -Message 'Set Urls.ProjectManagement in settings.local.psd1, then rerun the installer.'
  return
}

Start-DesktopProfileBrowser -Url $url -NewWindow
