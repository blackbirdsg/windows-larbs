[CmdletBinding()]
param(
  [switch] $SourceOnly,
  [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA 'larbs-windows')
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$passed = [System.Collections.Generic.List[string]]::new()

function Add-Pass {
  param([string] $Message)
  $passed.Add($Message)
}

function Add-Failure {
  param([string] $Message)
  $failures.Add($Message)
}

function Add-WarningResult {
  param([string] $Message)
  $warnings.Add($Message)
}

function Test-PowerShellFiles {
  $parseFailures = @()
  Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      $_.FullName,
      [ref] $tokens,
      [ref] $errors
    ) | Out-Null
    foreach ($parseError in $errors) {
      $parseFailures += "$($_.FullName):$($parseError.Extent.StartLineNumber) $($parseError.Message)"
    }
  }

  if ($parseFailures.Count -gt 0) {
    $parseFailures | ForEach-Object { Add-Failure $_ }
  } else {
    Add-Pass 'All PowerShell files parse successfully.'
  }
}

function Test-JsonFiles {
  foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.json') {
    try {
      Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
    } catch {
      Add-Failure "Invalid JSON: $($file.FullName)"
    }
  }

  if (-not ($failures | Where-Object { $_ -like 'Invalid JSON:*' })) {
    Add-Pass 'All JSON files parse successfully.'
  }
}

function Test-PublicFiles {
  # Read ignore rules as lines so CRLF checkouts on Windows behave like LF checkouts.
  $ignoredSettings = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '.gitignore')) |
    ForEach-Object { $_.Trim() }
  if ('settings.local.psd1' -notin $ignoredSettings) {
    Add-Failure 'settings.local.psd1 is not ignored by Git.'
  } else {
    Add-Pass 'Per-machine settings are ignored by Git.'
  }

  $publicFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File |
    Where-Object {
      $_.Name -ne 'settings.local.psd1' -and
      $_.Extension -in @('.ps1', '.psd1', '.cmd', '.yaml', '.yml', '.json', '.toml', '.html', '.css', '.md')
    }

  $privatePatterns = @(
    'C:\\Users\\[A-Za-z0-9._-]+',
    'https?://[^\s''"]+\.internal(?:/[^\s''"]*)?'
  )
  foreach ($file in $publicFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $privatePatterns) {
      if ($content -match $pattern) {
        Add-Failure "Possible machine-private value in $($file.FullName): $($Matches[0])"
      }
    }
  }

  if (-not ($failures | Where-Object { $_ -like 'Possible machine-private value*' })) {
    Add-Pass 'Public files contain no user paths or internal URLs.'
  }
}

function Test-SourceTemplates {
  $allowedTokens = @(
    '{{PROFILE_ROOT}}',
    '{{ACCENT_BASE}}',
    '{{ACCENT_BRIGHT}}',
    '{{ACCENT_TEXT}}',
    '{{ACCENT_BASE_RGB}}',
    '{{ACCENT_BRIGHT_RGB}}',
    '{{WORKSPACE_1_NAME}}',
    '{{WORKSPACE_2_NAME}}'
  )

  $templateFiles = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File |
    Where-Object { $_.Name -ne 'install-desktop-profile.ps1' }
  foreach ($file in $templateFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
      continue
    }
    $matches = [regex]::Matches($content, '\{\{[A-Z0-9_]+\}\}')
    foreach ($match in $matches) {
      if ($match.Value -notin $allowedTokens) {
        Add-Failure "Unknown template token $($match.Value) in $($file.FullName)."
      }
    }
  }

  if (-not ($failures | Where-Object { $_ -like 'Unknown template token*' })) {
    Add-Pass 'All source template tokens are recognized.'
  }
}

function Test-SettingsFile {
  $settingsPath = Join-Path $PSScriptRoot 'settings.example.psd1'
  try {
    $settings = Import-PowerShellDataFile -LiteralPath $settingsPath
    foreach ($section in @('Accent', 'Workspaces', 'Browser', 'Urls', 'Vpn', 'Wifi', 'Codex', 'Apps')) {
      if (-not $settings.ContainsKey($section)) {
        Add-Failure "settings.example.psd1 is missing section '$section'."
      }
    }
    if ($settings.Accent.Base -notmatch '^#[0-9a-fA-F]{6}$') {
      Add-Failure 'settings.example.psd1 has an invalid Accent.Base value.'
    }
  } catch {
    Add-Failure "Could not import settings.example.psd1: $($_.Exception.Message)"
  }

  if (-not ($failures | Where-Object { $_ -like '*settings.example.psd1*' })) {
    Add-Pass 'Public settings template is valid.'
  }
}

function Test-LiveProfile {
  if (-not (Test-Path -LiteralPath $InstallRoot)) {
    Add-Failure "Installed runtime not found: $InstallRoot"
    return
  }

  $requiredRuntimeFiles = @(
    'settings.psd1',
    'lib\profile-lib.ps1',
    'glazewm\glazewm-start-desktop.ps1',
    'glazewm\glazewm-larbs-config.yaml',
    'zebar\zebar-minimal-bar.html',
    'yazi\config\yazi.toml'
  )
  foreach ($relativePath in $requiredRuntimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot $relativePath))) {
      Add-Failure "Installed runtime is missing $relativePath."
    }
  }

  $runtimeTokens = Get-ChildItem -LiteralPath $InstallRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psd1', '.cmd', '.yaml', '.json', '.toml', '.html', '.css') } |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '\{\{[A-Z0-9_]+\}\}' }
  if ($runtimeTokens) {
    Add-Failure "Installed runtime contains unresolved tokens: $($runtimeTokens[0].FullName)"
  } else {
    Add-Pass 'Installed runtime is complete and fully rendered.'
  }

  $liveConfig = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
  if (-not (Test-Path -LiteralPath $liveConfig)) {
    Add-Failure 'Live GlazeWM config is missing.'
  } elseif ((Get-Content -LiteralPath $liveConfig -Raw) -notmatch [regex]::Escape($InstallRoot)) {
    Add-Failure 'Live GlazeWM config does not use the stable installed runtime.'
  } else {
    Add-Pass 'Live GlazeWM config uses the stable runtime.'
  }

  $glazeCli = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe'
  if (Test-Path -LiteralPath $glazeCli) {
    try {
      $response = & $glazeCli query workspaces 2>$null | ConvertFrom-Json
      if ($response.success) {
        Add-Pass 'GlazeWM IPC is healthy.'
      } else {
        Add-Failure 'GlazeWM IPC did not report success.'
      }
    } catch {
      Add-Failure 'GlazeWM IPC is unavailable.'
    }
  } else {
    Add-Failure 'GlazeWM CLI is not installed.'
  }

  if (Get-Process -Name 'zebar' -ErrorAction SilentlyContinue) {
    Add-Pass 'Zebar is running.'
  } else {
    Add-Failure 'Zebar is not running.'
  }

  try {
    Get-ScheduledTask -TaskName 'GlazeWM Desktop' -ErrorAction Stop | Out-Null
    Add-Pass 'GlazeWM logon task exists.'
  } catch {
    Add-WarningResult 'Could not verify the GlazeWM logon task from this session.'
  }
}

Test-PowerShellFiles
Test-JsonFiles
Test-PublicFiles
Test-SourceTemplates
Test-SettingsFile
if (-not $SourceOnly) {
  Test-LiveProfile
}

foreach ($message in $passed) {
  Write-Host "PASS  $message" -ForegroundColor Green
}
foreach ($message in $warnings) {
  Write-Host "WARN  $message" -ForegroundColor Yellow
}
foreach ($message in $failures) {
  Write-Host "FAIL  $message" -ForegroundColor Red
}

Write-Host ''
Write-Host "$($passed.Count) passed, $($warnings.Count) warnings, $($failures.Count) failed."
if ($failures.Count -gt 0) {
  exit 1
}
