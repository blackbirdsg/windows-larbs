$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$session = Join-Path $PSScriptRoot 'glazewm-claude-terminal.ps1'
$wtArgs = "powershell.exe -NoExit -ExecutionPolicy Bypass -File `"$session`""

try {
  Start-DesktopProfileApp -Name 'WindowsTerminal' -ArgumentList $wtArgs
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}
