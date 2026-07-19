param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Paths
)

$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$directory = $Paths | Where-Object { $_ } | Select-Object -First 1
if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
  $directory = (Get-Location).Path
}

try {
  $quotedDirectory = '"{0}"' -f $directory.Replace('"', '\"')
  Start-DesktopProfileApp -Name 'WindowsTerminal' -ArgumentList @('-d', $quotedDirectory, 'powershell.exe')
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}
