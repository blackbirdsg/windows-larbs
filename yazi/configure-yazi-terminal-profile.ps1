param(
  [string] $SessionPath = '',
  [string] $FontFace = 'JetBrainsMono NFM'
)

$ErrorActionPreference = 'Stop'

function Get-WindowsTerminalSettingsPath {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
  )

  return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Set-Utf8NoBom {
  param([string] $Path, [string] $Content)
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$terminalSettings = Get-WindowsTerminalSettingsPath
if (-not $terminalSettings) {
  throw 'Windows Terminal settings.json was not found. Start Windows Terminal once, then rerun the installer.'
}

if (-not $SessionPath) {
  $SessionPath = Join-Path $PSScriptRoot 'yazi-session.ps1'
}
if (-not (Test-Path -LiteralPath $SessionPath)) {
  throw "Missing Yazi session script: $SessionPath"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$terminalSettings.$timestamp.bak"
$profileGuid = '{8f5dbac4-6f5a-4a27-a75f-7dce7f3310a1}'
$commandLine = 'powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File "{0}"' -f $SessionPath

Copy-Item -LiteralPath $terminalSettings -Destination $backup -Force
$settings = Get-Content -LiteralPath $terminalSettings -Raw | ConvertFrom-Json

if (-not $settings.profiles) {
  $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{}) -Force
}
if (-not $settings.profiles.defaults) {
  $settings.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value ([pscustomobject]@{}) -Force
}
if (-not $settings.profiles.defaults.font) {
  $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value ([pscustomobject]@{}) -Force
}
if (-not $settings.profiles.list) {
  $settings.profiles | Add-Member -MemberType NoteProperty -Name list -Value @() -Force
}

$settings.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name face -Value $FontFace -Force

$profiles = @($settings.profiles.list)
$existing = $profiles | Where-Object { $_.guid -eq $profileGuid -or $_.name -eq 'Yazi' } | Select-Object -First 1

if (-not $existing) {
  $existing = [pscustomobject]@{
    guid = $profileGuid
    name = 'Yazi'
    commandline = $commandLine
    startingDirectory = '%USERPROFILE%'
    hidden = $false
    font = [pscustomobject]@{
      face = $FontFace
    }
  }
  $settings.profiles.list = @($settings.profiles.list) + $existing
} else {
  $existing.commandline = $commandLine
  $existing.startingDirectory = '%USERPROFILE%'
  $existing.hidden = $false
  if (-not $existing.font) {
    $existing | Add-Member -MemberType NoteProperty -Name font -Value ([pscustomobject]@{}) -Force
  }
  $existing.font | Add-Member -MemberType NoteProperty -Name face -Value $FontFace -Force
}

$json = $settings | ConvertTo-Json -Depth 64
Set-Utf8NoBom -Path $terminalSettings -Content $json

[pscustomobject]@{
  Profile = 'Yazi'
  Font = $FontFace
  Session = $SessionPath
  Backup = $backup
}
