$ErrorActionPreference = 'Stop'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$workspace = (Get-DesktopProfileSettings).DefaultProjectDirectory
if (-not $workspace -or -not (Test-Path -LiteralPath $workspace)) {
  $workspace = $env:USERPROFILE
}
Set-Location -LiteralPath $workspace

$claudeCommand = Get-Command claude -ErrorAction SilentlyContinue
$claudePath = if ($claudeCommand) { $claudeCommand.Source } else { '' }
if (-not $claudePath) {
  $npmClaude = Join-Path $env:APPDATA 'npm\claude.cmd'
  if (Test-Path -LiteralPath $npmClaude) {
    $claudePath = $npmClaude
  }
}
if ($claudePath) {
  & $claudePath
  return
}

Write-Host 'Claude Code was not found on PATH.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Install Claude Code, or open a fresh terminal if it was just installed, then try Alt+v again.'
Write-Host ''
Write-Host 'Expected command: claude'
