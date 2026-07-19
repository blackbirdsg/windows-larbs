$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

try {
  $profileId = Get-DesktopProfileSetting -Section 'Vpn' -Name 'ProfileId' -Default ''
  $openVpn = Resolve-DesktopProfileApp -Name 'OpenVpnConnect'

  if ($openVpn -and $openVpn.Kind -eq 'Path') {
    $arguments = if ($profileId) { @("--connect-shortcut=$profileId") } else { @() }
    Start-Process -FilePath $openVpn.Value -ArgumentList $arguments
    return
  }

  if ($openVpn) {
    Start-DesktopProfileApp -Name 'OpenVpnConnect'
    return
  }

  Start-Process -FilePath 'ms-settings:network-vpn'
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}
