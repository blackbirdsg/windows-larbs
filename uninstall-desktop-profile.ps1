[CmdletBinding()]
param(
  [switch] $KeepRuntime,
  [switch] $KeepLiveConfigs,
  [switch] $KeepTerminalProfile,
  [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA 'larbs-windows')
)

$ErrorActionPreference = 'Stop'

function Remove-ProfileBlock {
  param([string] $ProfilePath, [string] $Name)

  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    return
  }

  $content = Get-Content -LiteralPath $ProfilePath -Raw
  foreach ($prefix in @('LARBS Windows', 'Codex')) {
    $start = "# BEGIN $prefix $Name"
    $end = "# END $prefix $Name"
    $pattern = '(?s)\s*' + [regex]::Escape($start) + '.*?' + [regex]::Escape($end) + '\s*'
    $content = [regex]::Replace($content, $pattern, "`r`n")
  }
  [System.IO.File]::WriteAllText($ProfilePath, $content.Trim() + "`r`n", [System.Text.UTF8Encoding]::new($false))
}

function Remove-YaziTerminalProfile {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
  )
  $settingsPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $settingsPath) {
    return
  }

  Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak" -Force
  $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
  if ($settings.profiles.list) {
    $settings.profiles.list = @($settings.profiles.list | Where-Object {
      $_.guid -ne '{8f5dbac4-6f5a-4a27-a75f-7dce7f3310a1}' -and $_.name -ne 'Yazi'
    })
    $json = $settings | ConvertTo-Json -Depth 64
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
  }
}

Get-Process -Name 'glazewm', 'zebar' -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue

try {
  Unregister-ScheduledTask -TaskName 'GlazeWM Desktop' -Confirm:$false -ErrorAction Stop
} catch {
  & "$env:WINDIR\System32\schtasks.exe" /Delete /TN 'GlazeWM Desktop' /F 2>$null | Out-Null
}

Remove-ProfileBlock -ProfilePath $PROFILE.CurrentUserCurrentHost -Name 'Desktop Profile'
Remove-ProfileBlock -ProfilePath $PROFILE.CurrentUserCurrentHost -Name 'Yazi helpers'

if (-not $KeepTerminalProfile) {
  Remove-YaziTerminalProfile
}

if (-not $KeepLiveConfigs) {
  @(
    (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'),
    (Join-Path $env:USERPROFILE '.glzr\zebar\minimal-local'),
    (Join-Path $env:USERPROFILE '.glzr\zebar\settings.json'),
    (Join-Path $env:APPDATA 'yazi\config\yazi.toml'),
    (Join-Path $env:APPDATA 'yazi\config\keymap.toml')
  ) | ForEach-Object {
    if (Test-Path -LiteralPath $_) {
      Remove-Item -LiteralPath $_ -Recurse -Force
    }
  }
}

if (-not $KeepRuntime -and (Test-Path -LiteralPath $InstallRoot)) {
  $resolvedInstallRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
  $resolvedLocalAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\') + '\'
  if (-not $resolvedInstallRoot.StartsWith($resolvedLocalAppData, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a runtime outside LOCALAPPDATA: $resolvedInstallRoot"
  }
  Remove-Item -LiteralPath $resolvedInstallRoot -Recurse -Force
}

Write-Host 'Windows desktop profile removed. Existing backups were kept.' -ForegroundColor Green

