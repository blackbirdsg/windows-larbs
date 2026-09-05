$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'zebar\codex-usage.ps1')
function Assert-True($Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
  Write-Output "PASS $Message"
}
$fixture = @{
  rateLimits = @{ primary = @{ usedPercent = 90 } }
  rateLimitsByLimitId = @{ codex = @{
    primary = @{ usedPercent = 57; windowDurationMins = 10080; resetsAt = 1900000000 }
    secondary = @{ usedPercent = 20; windowDurationMins = 300 }
  } }
  rateLimitResetCredits = @{ availableCount = 3; credits = @() }
  accountId = 'private-account-id'
}
$status = ConvertTo-CodexBarStatus $fixture
Assert-True ($status.windows.Count -eq 2 -and $status.windows[0].remainingPercent -eq 43) 'Prefer the Codex bucket and calculate remaining usage.'
Assert-True ($status.windows[1].remainingPercent -eq 80) 'Preserve both quota windows.'
Assert-True ($status.availableResets -eq 3) 'Use the authoritative reset count, not the detail-array length.'
Assert-True (($status | ConvertTo-Json -Depth 6) -notmatch 'private-account-id|credits|accountId') 'Publish only bar data, without account IDs or credit details.'
$missing = ConvertTo-CodexBarStatus ([pscustomobject]@{})
Assert-True ($missing.windows.Count -eq 0 -and $null -eq $missing.availableResets) 'Missing values remain unknown, not zero.'
$zero = ConvertTo-CodexBarStatus (@{ rateLimits = @{ primary = @{ usedPercent = 0 } }; rateLimitResetCredits = @{ availableCount = 0 } })
Assert-True ($zero.windows[0].remainingPercent -eq 100 -and $zero.availableResets -eq 0) 'Zero usage means 100 percent remaining; zero resets is valid.'
$other = ConvertTo-CodexBarStatus (@{ rateLimits = @{ limitId = 'codex_spark'; primary = @{ usedPercent = 10 } } })
Assert-True ($other.windows.Count -eq 0) 'Never substitute a different model bucket for Codex.'
$clamped = ConvertTo-CodexBarStatus (@{ rateLimits = @{ primary = @{ usedPercent = 150 }; secondary = @{ usedPercent = -10 } } })
Assert-True ($clamped.windows[0].remainingPercent -eq 0 -and $clamped.windows[1].remainingPercent -eq 100) 'Clamp remaining percentages to 0 through 100.'

$directory = Join-Path ([IO.Path]::GetTempPath()) ('larbs-usage-test-' + [guid]::NewGuid())
$path = Join-Path $directory 'codex-usage.json'
try {
  function Get-CodexUsageSnapshot { return $fixture }
  Update-CodexBarStatus -Path $path
  $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Assert-True ($saved.state -eq 'ok' -and $saved.availableResets -eq 3) 'Write a readable status file.'
  function Get-CodexUsageSnapshot { throw 'test service failure' }
  Update-CodexBarStatus -Path $path
  $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Assert-True ($saved.state -eq 'unavailable' -and $null -eq $saved.availableResets -and $saved.windows.Count -eq 0) 'Replace stale values with unavailable state after a failed read.'
  Assert-True (-not (Test-Path -LiteralPath "$path.tmp")) 'Atomic replacement leaves no temporary cache.'
} finally {
  $resolved = [IO.Path]::GetFullPath($directory)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
