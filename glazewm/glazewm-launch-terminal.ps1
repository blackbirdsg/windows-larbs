$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

try {
  Start-DesktopProfileApp -Name 'WindowsTerminal' -ArgumentList @('powershell.exe')
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}
