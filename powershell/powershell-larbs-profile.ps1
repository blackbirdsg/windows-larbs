# Minimal LARBS-like PowerShell profile.
# Per-user, dependency-light, and safe to remove.

Set-PSReadLineOption -EditMode Vi -ErrorAction SilentlyContinue
Set-PSReadLineOption -BellStyle None -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Ctrl+f -Function ForwardWord -ErrorAction SilentlyContinue
Set-PSReadLineKeyHandler -Key Ctrl+b -Function BackwardWord -ErrorAction SilentlyContinue

$env:EDITOR = if (Get-Command nvim -ErrorAction SilentlyContinue) { 'nvim' } else { 'notepad' }
$env:VISUAL = $env:EDITOR

Set-Alias grep Select-String
Set-Alias open Invoke-Item
Set-Alias which Get-Command

function ll { Get-ChildItem -Force @args }
function la { Get-ChildItem -Force @args }
function l  { Get-ChildItem @args }
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

function touch {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    (Get-Item -LiteralPath $Path).LastWriteTime = Get-Date
  } else {
    New-Item -ItemType File -Path $Path | Out-Null
  }
}

function mkcd {
  param([Parameter(Mandatory = $true)][string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
  Set-Location -LiteralPath $Path
}

function c {
  Clear-Host
}

function home {
  Set-Location $HOME
}

function Get-GitBranch {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return $null
  }

  $branch = git branch --show-current 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    return $null
  }

  $dirty = git status --porcelain 2>$null
  if ($dirty) {
    return "$branch*"
  }

  return $branch
}

function Get-ShortPath {
  $path = (Get-Location).Path
  if ($path.StartsWith($HOME)) {
    return "~" + $path.Substring($HOME.Length)
  }
  return $path
}

function prompt {
  $lastExit = $LASTEXITCODE
  $path = Get-ShortPath
  $branch = Get-GitBranch
  $statusColor = if ($lastExit -and $lastExit -ne 0) { 'Red' } else { 'Green' }

  Write-Host "[" -NoNewline -ForegroundColor DarkGray
  Write-Host $env:USERNAME -NoNewline -ForegroundColor Yellow
  Write-Host "@" -NoNewline -ForegroundColor DarkGray
  Write-Host $env:COMPUTERNAME.ToLower() -NoNewline -ForegroundColor Cyan
  Write-Host " " -NoNewline
  Write-Host $path -NoNewline -ForegroundColor Blue

  if ($branch) {
    Write-Host " git:" -NoNewline -ForegroundColor DarkGray
    Write-Host $branch -NoNewline -ForegroundColor Magenta
  }

  Write-Host "]" -NoNewline -ForegroundColor DarkGray
  Write-Host "`n$" -NoNewline -ForegroundColor $statusColor
  return " "
}
