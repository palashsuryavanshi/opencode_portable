<#
  OpenCode Portable - session backup / restore
  The chat history lives in a SQLite database that uses WAL mode, so the
  .db, .db-wal and .db-shm files MUST be copied together or the copy is
  corrupt. Always run this with OpenCode closed.
#>
param(
  [ValidateSet('backup', 'restore', 'import-host', 'list')]
  [string]$Action = 'list',
  [string]$Root = "D:\VIBECODINGPROJECTS\OpenCode Portable"
)
$ErrorActionPreference = 'Continue'

$data = Join-Path $Root 'data\opencode-data\opencode'
$baks = Join-Path $Root 'data\backups'

function Test-OpenCodeRunning {
  if (Get-Process -Name 'OpenCode', 'opencode-cli' -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "  [!] OpenCode is still running." -ForegroundColor Yellow
    Write-Host "      Close it first, otherwise the database copy can be torn." -ForegroundColor Yellow
    return $true
  }
  return $false
}

function Copy-SessionDir($src, $dst) {
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  # WAL-mode SQLite: these three belong together
  foreach ($f in @('opencode.db', 'opencode.db-wal', 'opencode.db-shm', 'auth.json')) {
    $p = Join-Path $src $f
    if (Test-Path $p) { Copy-Item $p $dst -Force }
  }
}

switch ($Action) {

  'backup' {
    if (Test-OpenCodeRunning) { exit 1 }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest  = Join-Path $baks "sessions-$stamp"
    Copy-SessionDir $data $dest
    $size = [math]::Round(((Get-ChildItem $dest -File | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Host "  backed up sessions to $dest ($size MB)" -ForegroundColor Green
  }

  'restore' {
    if (Test-OpenCodeRunning) { exit 1 }
    if (-not (Test-Path $baks)) { Write-Host "  no backups yet"; exit 1 }
    $latest = Get-ChildItem $baks -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Host "  no backups yet"; exit 1 }
    Write-Host "  restoring from $($latest.FullName)"
    Copy-SessionDir $latest.FullName $data
    Write-Host "  done" -ForegroundColor Green
  }

  'import-host' {
    if (Test-OpenCodeRunning) { exit 1 }
    $src = Join-Path $env:USERPROFILE '.local\share\opencode'
    if (-not (Test-Path $src)) { Write-Host "  no host sessions at $src"; exit 1 }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest  = Join-Path $baks "host-$stamp"
    Copy-SessionDir $src $dest
    Write-Host "  imported host sessions to $dest" -ForegroundColor Green
    Write-Host "  now run:  Sync.cmd restore-host"
  }

  'list' {
    if (Test-Path $baks) {
      Get-ChildItem $baks -Directory | Sort-Object Name -Descending |
        ForEach-Object {
          $s = [math]::Round(((Get-ChildItem $_.FullName -File | Measure-Object Length -Sum).Sum / 1MB), 1)
          "  {0}  ({1} MB)" -f $_.Name, $s
        }
    } else { Write-Host "  no backups yet" }
  }
}
