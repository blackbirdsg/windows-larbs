$script:DesktopProfileRoot = Split-Path -Parent $PSScriptRoot
$script:DesktopProfileSettings = $null

$script:DesktopAppDefinitions = @{
  Brave = @{
    Commands = @('brave.exe')
    Paths = @(
      '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe',
      '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
    )
    StartMenuPatterns = @('Brave*')
  }
  KiCad = @{
    Commands = @('kicad.exe')
    Paths = @('%ProgramFiles%\KiCad\*\bin\kicad.exe')
    StartMenuPatterns = @('KiCad*')
  }
  BambuStudio = @{
    Commands = @('bambu-studio.exe')
    Paths = @('%ProgramFiles%\Bambu Studio\bambu-studio.exe')
    StartMenuPatterns = @('Bambu Studio*')
  }
  Wireshark = @{
    Commands = @('Wireshark.exe')
    Paths = @('%ProgramFiles%\Wireshark\Wireshark.exe')
    StartMenuPatterns = @('Wireshark*')
  }
  GoogleEarth = @{
    Commands = @('googleearth.exe', 'googleearthpro.exe')
    Paths = @(
      '%ProgramFiles%\Google\Google Earth Pro\client\googleearth.exe',
      '%ProgramFiles%\Google\Google Earth Pro\client\googleearthpro.exe'
    )
    StartMenuPatterns = @('Google Earth Pro*')
  }
  QGIS = @{
    Commands = @('qgis.exe', 'qgis-bin.exe')
    Paths = @(
      '%ProgramFiles%\QGIS *\bin\qgis.exe',
      '%ProgramFiles%\QGIS *\bin\qgis-bin.exe'
    )
    StartMenuPatterns = @('QGIS Desktop*', 'QGIS*')
  }
  OBS = @{
    Commands = @('obs64.exe')
    Paths = @('%ProgramFiles%\obs-studio\bin\64bit\obs64.exe')
    StartMenuPatterns = @('OBS Studio*')
  }
  TeXstudio = @{
    Commands = @('texstudio.exe')
    Paths = @('%ProgramFiles%\texstudio\texstudio.exe')
    StartMenuPatterns = @('TeXstudio*')
  }
  MarkText = @{
    Commands = @('MarkText.exe')
    Paths = @(
      '%LOCALAPPDATA%\Programs\MarkText\MarkText.exe',
      '%ProgramFiles%\MarkText\MarkText.exe'
    )
    StartMenuPatterns = @('MarkText*')
  }
  Neovim = @{
    Commands = @('nvim.exe')
    Paths = @(
      '%USERPROFILE%\scoop\shims\nvim.exe',
      '%LOCALAPPDATA%\Programs\Neovim\bin\nvim.exe',
      '%ProgramFiles%\Neovim\bin\nvim.exe'
    )
    StartMenuPatterns = @('Neovim*')
  }
  OpenVpnConnect = @{
    Commands = @('OpenVPNConnect.exe')
    Paths = @('%ProgramFiles%\OpenVPN Connect\OpenVPNConnect.exe')
    StartMenuPatterns = @('OpenVPN Connect*')
  }
  PowerToysRun = @{
    Commands = @('PowerToys.PowerLauncher.exe')
    Paths = @('%ProgramFiles%\PowerToys\PowerToys.PowerLauncher.exe')
    StartMenuPatterns = @()
  }
  WindowsTerminal = @{
    Commands = @('wt.exe')
    Paths = @(
      '%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe',
      '%LOCALAPPDATA%\Microsoft\WindowsApps\Microsoft.WindowsTerminal_8wekyb3d8bbwe\wt.exe'
    )
    StartMenuPatterns = @('Terminal*', 'Windows Terminal*')
  }
  Yazi = @{
    Commands = @('yazi.exe')
    Paths = @(
      '%USERPROFILE%\scoop\shims\yazi.exe',
      '%LOCALAPPDATA%\Microsoft\WinGet\Packages\sxyazi.yazi_Microsoft.Winget.Source_8wekyb3d8bbwe\yazi-x86_64-pc-windows-msvc\yazi.exe',
      '%LOCALAPPDATA%\Microsoft\WinGet\Packages\sxyazi.yazi_*\yazi-*\yazi.exe'
    )
    StartMenuPatterns = @()
  }
  GlazeWM = @{
    Commands = @()
    Paths = @('%ProgramFiles%\glzr.io\GlazeWM\glazewm.exe')
    StartMenuPatterns = @('GlazeWM*')
  }
  GlazeCli = @{
    Commands = @()
    Paths = @('%ProgramFiles%\glzr.io\GlazeWM\cli\glazewm.exe')
    StartMenuPatterns = @()
  }
  Zebar = @{
    Commands = @('zebar.exe')
    Paths = @('%ProgramFiles%\glzr.io\Zebar\zebar.exe')
    StartMenuPatterns = @('Zebar*')
  }
}

function Get-DesktopProfileRoot {
  return $script:DesktopProfileRoot
}

function Get-DesktopProfileSettings {
  if ($script:DesktopProfileSettings) {
    return $script:DesktopProfileSettings
  }

  $candidates = @(
    (Join-Path $script:DesktopProfileRoot 'settings.psd1'),
    (Join-Path $script:DesktopProfileRoot 'settings.local.psd1'),
    (Join-Path $script:DesktopProfileRoot 'settings.example.psd1')
  )
  $settingsPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $settingsPath) {
    throw "Desktop profile settings were not found under $script:DesktopProfileRoot."
  }

  $script:DesktopProfileSettings = Import-PowerShellDataFile -LiteralPath $settingsPath
  return $script:DesktopProfileSettings
}

function Get-DesktopProfileSetting {
  param(
    [Parameter(Mandatory = $true)][string] $Section,
    [Parameter(Mandatory = $true)][string] $Name,
    $Default = $null
  )

  $settings = Get-DesktopProfileSettings
  if (-not $settings.ContainsKey($Section)) {
    return $Default
  }

  $sectionValue = $settings[$Section]
  if ($sectionValue -is [System.Collections.IDictionary] -and $sectionValue.Contains($Name)) {
    return $sectionValue[$Name]
  }

  return $Default
}

function Expand-DesktopProfilePath {
  param([Parameter(Mandatory = $true)][string] $Path)
  return [Environment]::ExpandEnvironmentVariables($Path)
}

function New-DesktopAppResult {
  param(
    [Parameter(Mandatory = $true)][string] $Kind,
    [Parameter(Mandatory = $true)][string] $Value
  )

  return [pscustomobject]@{
    Kind = $Kind
    Value = $Value
  }
}

function Resolve-DesktopProfilePathCandidate {
  param([string] $Candidate)

  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return $null
  }

  $expanded = Expand-DesktopProfilePath $Candidate
  $matches = @(Get-Item -Path $expanded -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Sort-Object @{
      Expression = {
        $versions = [regex]::Matches($_.FullName, '(?<!\d)\d+(?:\.\d+)+(?!\d)')
        if ($versions.Count -gt 0) {
          try { return [version] $versions[$versions.Count - 1].Value } catch { }
        }
        return [version] '0.0'
      }
      Descending = $true
    }, @{
      Expression = { $_.FullName }
      Descending = $true
    })
  if ($matches.Count -gt 0) {
    return $matches[0].FullName
  }

  $command = Get-Command $expanded -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) {
    return $command.Source
  }

  return $null
}

function Resolve-DesktopProfileApp {
  param([Parameter(Mandatory = $true)][string] $Name)

  if (-not $script:DesktopAppDefinitions.ContainsKey($Name)) {
    throw "Unknown desktop app '$Name'."
  }

  $configured = Get-DesktopProfileSetting -Section 'Apps' -Name $Name -Default ''
  $configuredPath = Resolve-DesktopProfilePathCandidate $configured
  if ($configuredPath) {
    return New-DesktopAppResult -Kind 'Path' -Value $configuredPath
  }

  $definition = $script:DesktopAppDefinitions[$Name]
  foreach ($commandName in @($definition.Commands)) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
      return New-DesktopAppResult -Kind 'Path' -Value $command.Source
    }
  }

  foreach ($path in @($definition.Paths)) {
    $resolvedPath = Resolve-DesktopProfilePathCandidate $path
    if ($resolvedPath) {
      return New-DesktopAppResult -Kind 'Path' -Value $resolvedPath
    }
  }

  if ($Name -eq 'WindowsTerminal') {
    $terminalPackage = Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue |
      Sort-Object Version -Descending |
      Select-Object -First 1
    if ($terminalPackage) {
      $terminalExe = Join-Path $terminalPackage.InstallLocation 'wt.exe'
      if (Test-Path -LiteralPath $terminalExe) {
        return New-DesktopAppResult -Kind 'Path' -Value $terminalExe
      }
    }
  }

  $startMenuRoots = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  foreach ($pattern in @($definition.StartMenuPatterns)) {
    foreach ($root in $startMenuRoots) {
      $shortcut = Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like $pattern } |
        Sort-Object FullName |
        Select-Object -First 1
      if ($shortcut) {
        return New-DesktopAppResult -Kind 'Path' -Value $shortcut.FullName
      }
    }

    $startApp = Get-StartApps -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like $pattern } |
      Sort-Object Name |
      Select-Object -First 1
    if ($startApp) {
      return New-DesktopAppResult -Kind 'AppsFolder' -Value $startApp.AppID
    }
  }

  return $null
}

function Start-DesktopProfileApp {
  param(
    [Parameter(Mandatory = $true)][string] $Name,
    [string[]] $ArgumentList = @(),
    [string] $WorkingDirectory = ''
  )

  $app = Resolve-DesktopProfileApp -Name $Name
  if (-not $app) {
    throw "$Name was not found. Install it or set Apps.$Name in settings.local.psd1."
  }

  if ($app.Kind -eq 'AppsFolder') {
    Start-Process -FilePath 'explorer.exe' -ArgumentList @("shell:AppsFolder\$($app.Value)")
    return
  }

  $parameters = @{
    FilePath = $app.Value
  }
  if ($ArgumentList.Count -gt 0) {
    $parameters.ArgumentList = $ArgumentList
  }
  if ($WorkingDirectory) {
    $parameters.WorkingDirectory = $WorkingDirectory
  } elseif ([System.IO.Path]::GetExtension($app.Value) -ieq '.exe') {
    $parameters.WorkingDirectory = Split-Path -Parent $app.Value
  }
  Start-Process @parameters
}

function Start-DesktopProfileBrowser {
  param(
    [string] $Url = '',
    [switch] $NewWindow
  )

  $browser = Resolve-DesktopProfileApp -Name 'Brave'
  if ($browser -and $browser.Kind -eq 'Path') {
    $arguments = @()
    if ($NewWindow) {
      $arguments += '--new-window'
    }
    if ($Url) {
      $arguments += $Url
    }
    Start-Process -FilePath $browser.Value -ArgumentList $arguments
    return
  }

  if ($Url) {
    Start-Process -FilePath $Url
    return
  }

  $homeUrl = Get-DesktopProfileSetting -Section 'Browser' -Name 'HomeUrl' -Default 'https://start.duckduckgo.com/'
  Start-Process -FilePath $homeUrl
}

function Write-DesktopProfileLog {
  param(
    [Parameter(Mandatory = $true)][string] $Name,
    [Parameter(Mandatory = $true)][string] $Message
  )

  try {
    $logDirectory = Join-Path $env:LOCALAPPDATA 'larbs-windows\logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logPath = Join-Path $logDirectory "$Name.log"
    Add-Content -LiteralPath $logPath -Value ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message)
  } catch {
    # Logging must not break a shortcut.
  }
}

function Show-DesktopProfileError {
  param([Parameter(Mandatory = $true)][string] $Message)

  Write-DesktopProfileLog -Name 'launcher-errors' -Message $Message
  $safeMessage = $Message.Replace("'", "''")
  $command = "Write-Host '$safeMessage' -ForegroundColor Yellow"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-EncodedCommand', $encoded)
}
