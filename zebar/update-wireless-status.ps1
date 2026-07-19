param(
  [switch] $Once
)

$ErrorActionPreference = 'SilentlyContinue'
$profileRoot = Split-Path -Parent $PSScriptRoot
$profileLib = Join-Path $profileRoot 'lib\profile-lib.ps1'
if (Test-Path -LiteralPath $profileLib) {
  . $profileLib
}

$statusPath = Join-Path $env:USERPROFILE '.glzr\zebar\minimal-local\wireless-status.json'
$preferredWifiFallbacks = @()
if (Get-Command Get-DesktopProfileSetting -ErrorAction SilentlyContinue) {
  $preferredWifiFallbacks = @(Get-DesktopProfileSetting -Section 'Wifi' -Name 'PreferredSsidFallbacks' -Default @())
}
$mutex = [System.Threading.Mutex]::new($false, 'Local\Zebar-Wireless-Status')
$hasLock = $false

function Get-SavedWifiFallback {
  param($adapter)

  $profileRoot = 'C:\ProgramData\Microsoft\Wlansvc\Profiles\Interfaces'
  if (-not $adapter.InterfaceGuid) {
    return ''
  }

  $profileDir = Join-Path $profileRoot $adapter.InterfaceGuid.ToString()
  if (-not (Test-Path -LiteralPath $profileDir)) {
    return ''
  }

  $savedProfiles = @(
    Get-ChildItem -LiteralPath $profileDir -Filter '*.xml' |
      ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        if ($text -match '<name>([^<]+)</name>') {
          [pscustomobject]@{
            Name = $Matches[1]
            LastWriteTime = $_.LastWriteTime
          }
        }
      }
  )

  foreach ($preferredName in $preferredWifiFallbacks) {
    $match = $savedProfiles | Where-Object { $_.Name -eq $preferredName } | Select-Object -First 1
    if ($match) {
      return $match.Name
    }
  }

  return ''
}

function Get-WifiStatus {
  $adapter = Get-NetAdapter |
    Where-Object {
      $_.Name -like '*Wi-Fi*' -or
      $_.InterfaceDescription -match 'Wireless|Wi-Fi|WiFi|802\.11'
    } |
    Select-Object -First 1

  if (-not $adapter) {
    return [ordered]@{
      state = 'off'
      label = 'wifi off'
      ssid = ''
      strength = $null
      detail = 'No Wi-Fi adapter found'
    }
  }

  if ($adapter.Status -eq 'Disabled' -or $adapter.Status -eq 'Not Present') {
    return [ordered]@{
      state = 'off'
      label = 'wifi off'
      ssid = ''
      strength = $null
      detail = $adapter.Status.ToString()
    }
  }

  $netsh = netsh wlan show interfaces 2>&1 | Out-String
  $ssid = ''
  $strength = $null

  if ($LASTEXITCODE -eq 0 -and $netsh) {
    $ssidLine = ($netsh -split "`r?`n") |
      Where-Object { $_ -match '^\s*SSID\s+:\s*(.+)$' -and $_ -notmatch 'BSSID' } |
      Select-Object -First 1
    $signalLine = ($netsh -split "`r?`n") |
      Where-Object { $_ -match '^\s*(Signal|Segnale)\s+:\s*(\d+)%' } |
      Select-Object -First 1

    if ($ssidLine -match ':\s*(.+)$') {
      $ssid = $Matches[1].Trim()
    }
    if ($signalLine -match '(\d+)%') {
      $strength = [int]$Matches[1]
    }
  }

  $profile = Get-NetConnectionProfile -InterfaceAlias $adapter.Name |
    Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' } |
    Select-Object -First 1

  if ($adapter.MediaConnectionState -eq 'Connected' -or $adapter.Status -eq 'Up') {
    $profileName = ''
    if ($profile -and $profile.Name) {
      $profileName = $profile.Name
    }
    $savedFallback = Get-SavedWifiFallback $adapter
    $label = if ($ssid) { $ssid } elseif ($profileName -and $profileName -notmatch 'Rete non identificata|Unidentified network') { $profileName } elseif ($savedFallback) { $savedFallback } else { 'wifi on' }
    $detail = if ($ssid) { 'SSID from WLAN' } elseif ($savedFallback) { 'SSID blocked by Windows; using saved profile fallback' } else { 'SSID blocked by Windows location/elevation policy' }

    return [ordered]@{
      state = 'connected'
      label = $label
      ssid = if ($ssid) { $ssid } else { $savedFallback }
      strength = $strength
      detail = $detail
    }
  }

  [ordered]@{
    state = 'disconnected'
    label = 'wifi --'
    ssid = ''
    strength = $null
    detail = $adapter.Status.ToString()
  }
}

function Get-BluetoothStatus {
  $adapter = Get-PnpDevice -Class Bluetooth |
    Where-Object { $_.FriendlyName -match 'Adapter|Radio|Bluetooth' -and $_.InstanceId -notmatch 'BTHENUM|BTHLEDEVICE' } |
    Select-Object -First 1
  $service = Get-Service bthserv

  if (-not $adapter -or $adapter.Status -ne 'OK' -or $service.Status -ne 'Running') {
    return [ordered]@{
      state = 'off'
      label = 'bt off'
      device = ''
      detail = 'Bluetooth adapter or service unavailable'
    }
  }

  $devices = @(
    Get-PnpDevice -Class Bluetooth |
      Where-Object {
        $_.Present -and
        $_.Status -eq 'OK' -and
        ($_.InstanceId -like 'BTHENUM\DEV_*' -or $_.InstanceId -like 'BTHLE\DEV_*') -and
        $_.FriendlyName -notmatch 'Transport|Trasporto|Service|Servizio|Profile|Profilo|Generic|Microsoft|Enumerator|Enumeratore'
      } |
      Select-Object -ExpandProperty FriendlyName -Unique
  )

  if ($devices.Count -gt 0) {
    return [ordered]@{
      state = 'connected'
      label = ($devices[0].ToString())
      device = ($devices[0].ToString())
      detail = 'Detected paired/present Bluetooth device'
    }
  }

  [ordered]@{
    state = 'on'
    label = 'bt --'
    device = ''
    detail = 'Bluetooth on, no connected device detected'
  }
}

function Write-WirelessStatus {
  $statusDirectory = Split-Path -Parent $statusPath
  New-Item -ItemType Directory -Path $statusDirectory -Force | Out-Null

  $status = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    wifi = Get-WifiStatus
    bluetooth = Get-BluetoothStatus
  }

  $json = $status | ConvertTo-Json -Depth 6
  $tempPath = "$statusPath.tmp"
  $backupPath = "$statusPath.bak"
  [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))

  if (Test-Path -LiteralPath $statusPath) {
    [System.IO.File]::Replace($tempPath, $statusPath, $backupPath, $true)
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
  } else {
    Move-Item -LiteralPath $tempPath -Destination $statusPath
  }
}

try {
  try {
    $hasLock = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $hasLock = $true
  }

  if (-not $hasLock) {
    exit 0
  }

  do {
    Write-WirelessStatus
    if ($Once) {
      break
    }
    Start-Sleep -Seconds 15
  } while ($true)
} finally {
  if ($hasLock) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
