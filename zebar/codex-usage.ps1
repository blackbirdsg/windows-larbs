function Find-CodexUsageExecutable {
  # The desktop app rotates this directory on updates. Resolve it on each poll.
  $bundled = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\*\codex.exe') -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($bundled) { return $bundled.FullName }
  $command = Get-Command 'codex.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }
  throw 'Codex CLI is unavailable.'
}

function Read-CodexUsageReply {
  param($Process, [int] $Id, [datetime] $Deadline)
  while ([datetime]::UtcNow -lt $Deadline) {
    $line = $Process.StandardOutput.ReadLineAsync()
    $remaining = [int][Math]::Max(1, ($Deadline - [datetime]::UtcNow).TotalMilliseconds)
    if (-not $line.Wait($remaining)) { throw 'Codex usage request timed out.' }
    if ($null -eq $line.Result) { throw 'Codex usage connection closed.' }
    $reply = $line.Result | ConvertFrom-Json
    if ($reply.id -eq $Id) {
      if ($reply.error) { throw 'Codex could not read account usage. Check sign-in and connectivity.' }
      return $reply.result
    }
  }
  throw 'Codex usage request timed out.'
}

function Get-CodexUsageSnapshot {
  $ErrorActionPreference = 'Stop'
  $start = New-Object System.Diagnostics.ProcessStartInfo
  $start.FileName = Find-CodexUsageExecutable
  $start.Arguments = 'app-server --stdio'
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardInput = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.EnvironmentVariables.Remove('CODEX_ELECTRON_USER_DATA_PATH')
  $process = [System.Diagnostics.Process]::Start($start)
  try {
    # Drain diagnostics without logging credentials or raw service responses.
    $stderr = $process.StandardError.ReadToEndAsync()
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    $process.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"larbs_usage_bar","version":"1.0.0"},"capabilities":{"experimentalApi":true}}}')
    $null = Read-CodexUsageReply $process 1 $deadline
    $process.StandardInput.WriteLine('{"method":"initialized"}')
    $process.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read"}')
    return Read-CodexUsageReply $process 2 $deadline
  } finally {
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(1500)) {
      $process.Kill()
      $process.WaitForExit()
    }
    $process.Dispose()
  }
}

function ConvertTo-CodexBarStatus {
  param($Snapshot)
  $limits = $Snapshot.rateLimitsByLimitId.codex
  if (-not $limits -and (-not $Snapshot.rateLimits.limitId -or $Snapshot.rateLimits.limitId -eq 'codex')) {
    $limits = $Snapshot.rateLimits
  }
  $windows = @(
    foreach ($name in @('primary', 'secondary')) {
      $window = $limits.$name
      if ($null -ne $window -and $null -ne $window.usedPercent) {
        [ordered]@{
          name = $name
          remainingPercent = 100 - [Math]::Min(100, [Math]::Max(0, [double]$window.usedPercent))
          windowDurationMins = $window.windowDurationMins
          resetsAt = $window.resetsAt
        }
      }
    }
  )
  $resets = $Snapshot.rateLimitResetCredits.availableCount
  [ordered]@{
    timestamp = [datetime]::UtcNow.ToString('o')
    state = 'ok'
    windows = @($windows)
    availableResets = $(if ($null -ne $resets -and $resets -ge 0) { [int]$resets } else { $null })
  }
}

function Update-CodexBarStatus {
  param([string] $Path)
  $ErrorActionPreference = 'Stop'
  try {
    $status = ConvertTo-CodexBarStatus (Get-CodexUsageSnapshot)
  } catch {
    $status = [ordered]@{
      timestamp = [datetime]::UtcNow.ToString('o')
      state = 'unavailable'
      windows = @()
      availableResets = $null
    }
  }
  $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
  $tempPath = "$Path.tmp"
  [IO.File]::WriteAllText($tempPath, ($status | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
  if (Test-Path -LiteralPath $Path) {
    $backupPath = "$Path.bak"
    [IO.File]::Replace($tempPath, $Path, $backupPath, $true)
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
  } else {
    [IO.File]::Move($tempPath, $Path)
  }
}
