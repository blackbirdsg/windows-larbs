function y {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
  )

  $profileRoot = Split-Path -Parent $PSScriptRoot
  . (Join-Path $profileRoot 'lib\profile-lib.ps1')
  $yaziResult = Resolve-DesktopProfileApp -Name 'Yazi'
  $yazi = if ($yaziResult -and $yaziResult.Kind -eq 'Path') { $yaziResult.Value } else { '' }

  if (-not (Test-Path -LiteralPath $yazi)) {
    Write-Host 'Yazi executable not found.' -ForegroundColor Yellow
    return
  }

  $env:YAZI_FILE_ONE = 'C:\Program Files\Git\usr\bin\file.exe'
  $cwdFile = [System.IO.Path]::GetTempFileName()

  try {
    & $yazi @Args --cwd-file="$cwdFile"
    $nextDir = Get-Content -LiteralPath $cwdFile -Raw -ErrorAction SilentlyContinue
    $nextDir = $nextDir.Trim()
    if ($nextDir -and (Test-Path -LiteralPath $nextDir)) {
      Set-Location -LiteralPath $nextDir
    }
  } finally {
    Remove-Item -LiteralPath $cwdFile -Force -ErrorAction SilentlyContinue
  }
}

Set-Alias yy y
