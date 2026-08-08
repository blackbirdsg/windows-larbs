[CmdletBinding()]
param(
  [switch] $InstallPackages,
  [switch] $InstallOptionalApps,
  [switch] $SkipReload,
  [switch] $ConfigureWindowsTerminal,
  [switch] $SkipWindowsTerminal,
  [switch] $RuntimeOnly,
  [string] $SettingsPath = '',
  [string] $InstallRoot = ''
)

$ErrorActionPreference = 'Stop'

if (-not $InstallRoot) {
  $InstallRoot = Join-Path $env:LOCALAPPDATA 'larbs-windows'
}
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)

if (-not $SettingsPath) {
  $SettingsPath = Join-Path $PSScriptRoot 'settings.local.psd1'
  if (-not (Test-Path -LiteralPath $SettingsPath)) {
    $SettingsPath = Join-Path $PSScriptRoot 'settings.example.psd1'
  }
}
$SettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)

$backupRoot = Join-Path $env:LOCALAPPDATA 'larbs-windows-backups'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $backupRoot $stamp
$runtimeFolders = @('glazewm', 'zebar', 'yazi', 'powershell', 'lib')

function Write-Step {
  param([string] $Message)
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Set-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string] $Path,
    [Parameter(Mandatory = $true)][string] $Content
  )

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Backup-IfExists {
  param([string] $Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  $name = $Path -replace '^[A-Za-z]:\\', ''
  $name = $name -replace '[\\/:*?"<>|]', '_'
  $destination = Join-Path $backupDir $name
  $item = Get-Item -LiteralPath $Path
  if ($item.PSIsContainer) {
    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedInstallRoot = $InstallRoot.TrimEnd('\')
    if ($resolvedPath -eq $resolvedInstallRoot) {
      New-Item -ItemType Directory -Force -Path $destination | Out-Null
      Get-ChildItem -LiteralPath $Path -Force |
        Where-Object { $_.Name -ne 'codex-instances' } |
        ForEach-Object {
          Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $_.Name) -Recurse -Force
        }
    } else {
      Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
    }
  } else {
    Copy-Item -LiteralPath $Path -Destination $destination -Force
  }
}

function Copy-DirectoryContent {
  param(
    [Parameter(Mandatory = $true)][string] $Source,
    [Parameter(Mandatory = $true)][string] $Destination
  )

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
    $target = Join-Path $Destination $_.Name
    if ($_.PSIsContainer) {
      Copy-DirectoryContent -Source $_.FullName -Destination $target
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

function Assert-HexColor {
  param([string] $Name, [string] $Value)
  if ($Value -notmatch '^#[0-9a-fA-F]{6}$') {
    throw "$Name must be a six-digit hex color such as #4b0706."
  }
}

function Assert-WorkspaceLabel {
  param([string] $Name, [string] $Value)
  if ($Value -notmatch '^[A-Za-z0-9 _-]{1,20}$') {
    throw "$Name must contain 1-20 letters, numbers, spaces, underscores, or hyphens."
  }
}

function Convert-HexToRgbText {
  param([string] $Value)
  $hex = $Value.TrimStart('#')
  $red = [Convert]::ToInt32($hex.Substring(0, 2), 16)
  $green = [Convert]::ToInt32($hex.Substring(2, 2), 16)
  $blue = [Convert]::ToInt32($hex.Substring(4, 2), 16)
  return "$red, $green, $blue"
}

function Render-RuntimeTemplates {
  param(
    [Parameter(Mandatory = $true)][hashtable] $Settings
  )

  $replacements = [ordered]@{
    '{{PROFILE_ROOT}}' = $InstallRoot
    '{{ACCENT_BASE}}' = $Settings.Accent.Base
    '{{ACCENT_BRIGHT}}' = $Settings.Accent.Bright
    '{{ACCENT_TEXT}}' = $Settings.Accent.Text
    '{{ACCENT_BASE_RGB}}' = Convert-HexToRgbText $Settings.Accent.Base
    '{{ACCENT_BRIGHT_RGB}}' = Convert-HexToRgbText $Settings.Accent.Bright
    '{{WORKSPACE_1_NAME}}' = $Settings.Workspaces.One
    '{{WORKSPACE_2_NAME}}' = $Settings.Workspaces.Two
  }

  $textExtensions = @('.ps1', '.psd1', '.cmd', '.yaml', '.yml', '.json', '.toml', '.html', '.css')
  $textFiles = Get-ChildItem -LiteralPath $InstallRoot -Recurse -File |
    Where-Object { $_.Extension -in $textExtensions }

  foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($replacement in $replacements.GetEnumerator()) {
      $content = $content.Replace($replacement.Key, [string] $replacement.Value)
    }
    Set-Utf8NoBom -Path $file.FullName -Content $content
  }

  $unresolved = @($textFiles | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw) -match '\{\{[A-Z0-9_]+\}\}'
  })
  if ($unresolved.Count -gt 0) {
    throw "Unresolved template token in $($unresolved[0].FullName)."
  }
}

function Get-WingetCommand {
  $command = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) {
    return $command.Source
  }

  $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  if (Test-Path -LiteralPath $alias) {
    return $alias
  }

  return $null
}

function Install-WingetPackageSet {
  param([string[]] $Ids)

  $winget = Get-WingetCommand
  if (-not $winget) {
    throw 'WinGet was not found. Install App Installer from Microsoft, then rerun this script.'
  }

  foreach ($id in $Ids) {
    Write-Step "Install or update $id"
    & $winget install --id $id --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "WinGet could not install $id. The rest of the profile will continue."
    }
  }
}

function Add-ProfileBlock {
  param(
    [string] $ProfilePath,
    [string] $Name,
    [string] $Content
  )

  $start = "# BEGIN LARBS Windows $Name"
  $end = "# END LARBS Windows $Name"
  $legacyStart = "# BEGIN Codex $Name"
  $legacyEnd = "# END Codex $Name"
  $block = "$start`r`n$Content`r`n$end"

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProfilePath) | Out-Null
  $current = if (Test-Path -LiteralPath $ProfilePath) {
    Get-Content -LiteralPath $ProfilePath -Raw
  } else {
    ''
  }

  foreach ($markerPair in @(@($start, $end), @($legacyStart, $legacyEnd))) {
    if ($current -match [regex]::Escape($markerPair[0])) {
      $pattern = '(?s)' + [regex]::Escape($markerPair[0]) + '.*?' + [regex]::Escape($markerPair[1])
      $current = [regex]::Replace(
        $current,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $block }
      )
      Set-Utf8NoBom -Path $ProfilePath -Content $current
      return
    }
  }

  if ($current -and -not $current.EndsWith("`r`n")) {
    $current += "`r`n"
  }
  $current += "$block`r`n"
  Set-Utf8NoBom -Path $ProfilePath -Content $current
}

function Install-GlazeStartupTask {
  $glazeExe = 'C:\Program Files\glzr.io\GlazeWM\glazewm.exe'
  if (-not (Test-Path -LiteralPath $glazeExe)) {
    Write-Warning 'GlazeWM is not installed, so the logon task was not created.'
    return
  }

  $taskName = 'GlazeWM Desktop'
  $userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $startupScript = Join-Path $InstallRoot 'glazewm\glazewm-start-desktop.ps1'
  $action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startupScript`"" `
    -WorkingDirectory (Split-Path -Parent $startupScript)
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
  $trigger.Delay = 'PT8S'
  $principal = New-ScheduledTaskPrincipal `
    -UserId $userId `
    -LogonType Interactive `
    -RunLevel Limited
  $taskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)
  $task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $taskSettings `
    -Description 'Start GlazeWM through the interactive Windows shell, verify workspace IPC, and recover from transient startup failures.'

  Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

  $startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  @('GlazeWM.lnk', 'Zebar Minimal Bar.lnk') | ForEach-Object {
    $shortcut = Join-Path $startupDir $_
    if (Test-Path -LiteralPath $shortcut) {
      Remove-Item -LiteralPath $shortcut -Force
    }
  }
}

if (-not (Test-Path -LiteralPath $SettingsPath)) {
  throw "Settings file not found: $SettingsPath"
}

$settings = Import-PowerShellDataFile -LiteralPath $SettingsPath
foreach ($requiredSection in @('Accent', 'Workspaces', 'Browser', 'Urls', 'Vpn', 'Wifi', 'Codex', 'Apps')) {
  if (-not $settings.ContainsKey($requiredSection)) {
    throw "Settings file is missing the '$requiredSection' section."
  }
}
Assert-HexColor -Name 'Accent.Base' -Value $settings.Accent.Base
Assert-HexColor -Name 'Accent.Bright' -Value $settings.Accent.Bright
Assert-HexColor -Name 'Accent.Text' -Value $settings.Accent.Text
Assert-WorkspaceLabel -Name 'Workspaces.One' -Value $settings.Workspaces.One
Assert-WorkspaceLabel -Name 'Workspaces.Two' -Value $settings.Workspaces.Two

if ($InstallPackages) {
  Install-WingetPackageSet -Ids @(
    'glzr-io.glazewm',
    'glzr-io.zebar',
    'Microsoft.WindowsTerminal',
    'Microsoft.PowerToys',
    'Git.Git',
    'sxyazi.yazi',
    'Gyan.FFmpeg',
    '7zip.7zip',
    'jqlang.jq',
    'oschwartz10612.Poppler',
    'sharkdp.fd',
    'BurntSushi.ripgrep.MSVC',
    'junegunn.fzf',
    'ajeetdsouza.zoxide',
    'ImageMagick.ImageMagick',
    'DEVCOM.JetBrainsMonoNerdFont',
    'Brave.Brave',
    'OpenAI.Codex'
  )
}

if ($InstallOptionalApps) {
  Install-WingetPackageSet -Ids @(
    'TeXstudio.TeXstudio',
    'WiresharkFoundation.Wireshark',
    'OBSProject.OBSStudio',
    'Neovim.Neovim',
    'KiCad.KiCad',
    'Bambulab.Bambustudio',
    'OSGeo.QGIS',
    'Google.EarthPro',
    'OpenVPNTechnologies.OpenVPNConnect',
    'MarkText.MarkText',
    'OpenJS.NodeJS.LTS'
  )
}

Write-Step 'Back up the current desktop profile'
$pathsToBackup = @($InstallRoot)
if (-not $RuntimeOnly) {
  $pathsToBackup += @(
    (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'),
    (Join-Path $env:USERPROFILE '.glzr\zebar\settings.json'),
    (Join-Path $env:USERPROFILE '.glzr\zebar\minimal-local'),
    (Join-Path $env:APPDATA 'yazi\config\yazi.toml'),
    (Join-Path $env:APPDATA 'yazi\config\keymap.toml'),
    $PROFILE.CurrentUserCurrentHost
  )
}
$pathsToBackup | ForEach-Object { Backup-IfExists $_ }

Write-Step "Deploy stable runtime to $InstallRoot"
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
foreach ($folder in $runtimeFolders) {
  $source = Join-Path $PSScriptRoot $folder
  if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing source folder: $source"
  }
  Copy-DirectoryContent -Source $source -Destination (Join-Path $InstallRoot $folder)
}
Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $InstallRoot 'settings.psd1') -Force
Render-RuntimeTemplates -Settings $settings

if ($RuntimeOnly) {
  Write-Host ''
  Write-Host 'Rendered runtime successfully.' -ForegroundColor Green
  Write-Host "Runtime: $InstallRoot"
  return
}

Write-Step 'Install GlazeWM configuration'
$glazeConfig = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $glazeConfig) | Out-Null
Copy-Item -LiteralPath (Join-Path $InstallRoot 'glazewm\glazewm-larbs-config.yaml') -Destination $glazeConfig -Force

Write-Step 'Register resilient GlazeWM logon startup'
Install-GlazeStartupTask

Write-Step 'Install Zebar pack'
$zebarPack = Join-Path $env:USERPROFILE '.glzr\zebar\minimal-local'
New-Item -ItemType Directory -Force -Path $zebarPack | Out-Null
Copy-Item -LiteralPath (Join-Path $InstallRoot 'zebar\zebar-minimal-bar.html') -Destination (Join-Path $zebarPack 'bar.html') -Force
Copy-Item -LiteralPath (Join-Path $InstallRoot 'zebar\zebar-minimal-styles.css') -Destination (Join-Path $zebarPack 'styles.css') -Force
Copy-Item -LiteralPath (Join-Path $InstallRoot 'zebar\zebar-minimal-zpack.json') -Destination (Join-Path $zebarPack 'zpack.json') -Force
$zebarSettings = Join-Path $env:USERPROFILE '.glzr\zebar\settings.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zebarSettings) | Out-Null
Copy-Item -LiteralPath (Join-Path $InstallRoot 'zebar\zebar-settings.json') -Destination $zebarSettings -Force

Write-Step 'Install Yazi configuration'
$yaziConfigDir = Join-Path $env:APPDATA 'yazi\config'
New-Item -ItemType Directory -Force -Path $yaziConfigDir | Out-Null
Copy-Item -LiteralPath (Join-Path $InstallRoot 'yazi\config\yazi.toml') -Destination (Join-Path $yaziConfigDir 'yazi.toml') -Force
Copy-Item -LiteralPath (Join-Path $InstallRoot 'yazi\config\keymap.toml') -Destination (Join-Path $yaziConfigDir 'keymap.toml') -Force

Write-Step 'Install PowerShell profile helpers'
$profileScript = (Join-Path $InstallRoot 'powershell\powershell-larbs-profile.ps1').Replace("'", "''")
$yaziHelpers = (Join-Path $InstallRoot 'yazi\powershell-yazi-functions.ps1').Replace("'", "''")
Add-ProfileBlock -ProfilePath $PROFILE.CurrentUserCurrentHost -Name 'Desktop Profile' -Content ". '$profileScript'"
Add-ProfileBlock -ProfilePath $PROFILE.CurrentUserCurrentHost -Name 'Yazi helpers' -Content ". '$yaziHelpers'"

$configureTerminal = $ConfigureWindowsTerminal -or -not $SkipWindowsTerminal
if ($configureTerminal) {
  Write-Step 'Configure Windows Terminal Yazi profile'
  try {
    $terminalConfigurator = Join-Path $InstallRoot 'yazi\configure-yazi-terminal-profile.ps1'
    $yaziSession = Join-Path $InstallRoot 'yazi\yazi-session.ps1'
    & $terminalConfigurator -SessionPath $yaziSession | Out-Host
  } catch {
    Write-Warning $_.Exception.Message
  }
}

if (-not $SkipReload) {
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*update-wireless-status.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Get-Process -Name 'zebar' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500

  $profileLib = Join-Path $InstallRoot 'lib\profile-lib.ps1'
  . $profileLib
  $glazeCliResult = Resolve-DesktopProfileApp -Name 'GlazeCli'
  $glazeRunning = Get-Process -Name 'glazewm' -ErrorAction SilentlyContinue
  if ($glazeRunning -and $glazeCliResult) {
    Write-Step 'Reload GlazeWM'
    & $glazeCliResult.Value command wm-reload-config | Out-Null
  } elseif (-not $glazeRunning) {
    Write-Step 'Start GlazeWM'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallRoot 'glazewm\glazewm-start-desktop.ps1')
  }

  Write-Step 'Start or refresh Zebar'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallRoot 'glazewm\glazewm-start-zebar.ps1')
}

Write-Host ''
Write-Host 'Windows desktop profile installed.' -ForegroundColor Green
Write-Host "Runtime:  $InstallRoot"
Write-Host "Settings: $SettingsPath"
if (Test-Path -LiteralPath $backupDir) {
  Write-Host "Backup:   $backupDir"
}
Write-Host ''
Write-Host 'Run .\test-desktop-profile.ps1 to verify the source and live installation.'
