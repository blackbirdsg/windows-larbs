param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $Paths
)

$ErrorActionPreference = 'Stop'
$profileRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $profileRoot 'lib\profile-lib.ps1')

$markTextResult = Resolve-DesktopProfileApp -Name 'MarkText'
$markText = if ($markTextResult -and $markTextResult.Kind -eq 'Path') { $markTextResult.Value } else { '' }

if (-not (Test-Path -LiteralPath $markText)) {
  Start-Process -FilePath 'wt.exe' -ArgumentList @(
    'powershell.exe',
    '-NoExit',
    '-Command',
    "Write-Host 'MarkText was not found. Set Apps.MarkText in settings.local.psd1.' -ForegroundColor Yellow"
  )
  return
}

$files = @($Paths | Where-Object { $_ } | ForEach-Object {
  (Resolve-Path -LiteralPath $_).Path
})

if ($files.Count -eq 0) {
  return
}

$arguments = $files | ForEach-Object { '"{0}"' -f $_.Replace('"', '\"') }
Start-Process -FilePath $markText -ArgumentList $arguments
