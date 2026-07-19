$env:YAZI_FILE_ONE = 'C:\Program Files\Git\usr\bin\file.exe'

$profileRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$fallbackDir = (Get-DesktopProfileSettings).DefaultProjectDirectory
if (-not $fallbackDir) {
  $fallbackDir = $env:USERPROFILE
}
$startDir = $fallbackDir
$codexState = Join-Path $env:USERPROFILE '.codex\.codex-global-state.json'

if (Test-Path -LiteralPath $codexState) {
  try {
    $state = Get-Content -LiteralPath $codexState -Raw | ConvertFrom-Json
    $activeRoots = @($state.'active-workspace-roots' | Where-Object { $_ })
    if ($activeRoots.Count -gt 0) {
      $startDir = $activeRoots[0]
    }
  } catch {
    $startDir = $fallbackDir
  }
}

if (-not (Test-Path -LiteralPath $startDir)) {
  $startDir = $fallbackDir
}

if (-not (Test-Path -LiteralPath $startDir)) {
  $startDir = $env:USERPROFILE
}

try {
  $quotedStartDir = '"{0}"' -f $startDir.Replace('"', '\"')
  Start-DesktopProfileApp -Name 'WindowsTerminal' -ArgumentList @('-p', 'Yazi', '-d', $quotedStartDir)
} catch {
  Show-DesktopProfileError -Message $_.Exception.Message
}
