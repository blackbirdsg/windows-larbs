$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$url = Get-DesktopProfileSetting -Section 'Urls' -Name 'SourceControl' -Default ''
if (-not $url) {
  Show-DesktopProfileError -Message 'Set Urls.SourceControl in settings.local.psd1, then rerun the installer.'
  return
}

Start-DesktopProfileBrowser -Url $url -NewWindow
