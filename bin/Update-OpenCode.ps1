<#
  OpenCode Portable - Updater
  Downloads the latest stable NSIS installer from opencode.ai, extracts it,
  and replaces apps/opencode/ while preserving all user data in data/.

  Usage:
    PowerShell -ExecutionPolicy Bypass -File bin\Update-OpenCode.ps1
    # or from Launch.cmd menu (to be added)
#>

param(
  [string]$PortableRoot = (Split-Path $PSScriptRoot),
  [string]$DownloadUrl = "https://opencode.ai/download/stable/windows-x64-nsis",
  [switch]$Force,
  [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================================"
Write-Host "  OpenCode Portable Updater"
Write-Host "  Root: $PortableRoot"
Write-Host "========================================================"
Write-Host ""

$appsDir     = Join-Path $PortableRoot 'apps'
$opencodeDir = Join-Path $appsDir 'opencode'
$stageDir    = Join-Path $PortableRoot 'downloads\_update_stage'
# Deliberately a sibling of $stageDir, not a child: enumerating $stageDir while
# $newAppDir sits inside it would pick up app-new and try to move it into itself.
$newAppDir   = Join-Path $PortableRoot 'downloads\_app_new'
$installerPath = Join-Path $PortableRoot 'downloads\opencode-update.exe'

# Prefer the 7-Zip bundled inside the portable (apps\7zip\7za.exe). It is a
# standalone build, so the updater works on a machine that has never had
# 7-Zip installed and nothing is added to the host.
function Resolve-7z {
    $bundled = Join-Path $PortableRoot 'apps\7zip\7za.exe'
    if (Test-Path $bundled) { return $bundled }
    $c = Get-Command 7z, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($q in @("$env:ProgramFiles\7-Zip\7z.exe",
                     "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path $q) { return $q }
    }
    return $null
}

$sevenZip = Resolve-7z
if (-not $sevenZip) {
    Write-Error "No 7-Zip found. Expected the bundled copy at apps\7zip\7za.exe."
    exit 1
}

# --- 1. Check current version ---
$currentVer = "unknown"
if (Test-Path (Join-Path $opencodeDir 'OpenCode.exe')) {
  $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $opencodeDir 'OpenCode.exe'))
  $currentVer = "$($vi.FileMajorPart).$($vi.FileMinorPart).$($vi.FileBuildPart)"
}
Write-Host "  Current version: $currentVer"

# --- 2. Download latest installer ---
Write-Host ""
Write-Host "  Downloading latest installer..."
Write-Host "  URL: $DownloadUrl"

New-Item -ItemType Directory -Force -Path (Split-Path $installerPath) | Out-Null
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

try {
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 600
  $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
  Write-Host "  Downloaded: $sizeMB MB"
} catch {
  Write-Error "Download failed: $($_.Exception.Message)"
  exit 1
}

# --- 3. Extract NSIS installer (7z can read NSIS) ---
Write-Host ""
Write-Host "  Extracting..."

# Wipe the whole staging area. Removing only the NSIS folders left stale
# app-new\ contents behind after a failed run, and the next run then failed
# trying to move a directory onto a directory that already existed.
if (Test-Path $stageDir)    { Remove-Item $stageDir    -Recurse -Force }
if (Test-Path $newAppDir)   { Remove-Item $newAppDir   -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# The payload layout depends on which 7-Zip build is used:
#   * full 7z.exe -> $PLUGINSDIR\app-64.7z, a second archive to unpack
#   * bundled 7za -> the app files appear directly at the top level
# Handle both, otherwise the update appears to succeed but installs nothing.
& $sevenZip x $installerPath -o"$stageDir" -y | Out-Null

# Deliberately a sibling of $stageDir, not a child: enumerating $stageDir while
# $newAppDir sits inside it would pick up app-new and try to move it into itself.

$app7z = Join-Path $stageDir '$PLUGINSDIR\app-64.7z'

if (Test-Path $app7z) {
    Write-Host "  Extracting app archive..."
    & $sevenZip x $app7z -o"$newAppDir" -y | Out-Null
} elseif (Test-Path (Join-Path $stageDir 'OpenCode.exe')) {
    Write-Host "  App payload found directly in the installer."
    if (Test-Path $newAppDir) { Remove-Item $newAppDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $newAppDir | Out-Null
    Get-ChildItem $stageDir -Force |
        ForEach-Object { Move-Item $_.FullName -Destination $newAppDir -Force }
} else {
    Write-Error "Could not locate the OpenCode payload. The installer format may have changed."
    exit 1
}

# --- 5. Verify extracted app ---
$newExe = Join-Path $newAppDir 'OpenCode.exe'
if (-not (Test-Path $newExe)) {
  Write-Error "OpenCode.exe not found in extracted app."
  exit 1
}

$newVi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($newExe)
$newVer = "$($newVi.FileMajorPart).$($newVi.FileMinorPart).$($newVi.FileBuildPart)"
Write-Host "  New version: $newVer"

if ($currentVer -eq $newVer -and -not $Force) {
  Write-Host ""
  Write-Warning "Already on latest version ($currentVer). Use -Force to reinstall."
  exit 0
}

# --- 6. Backup current opencode (optional) ---
# Only back up if there is something installed to back up. On a fresh install
# apps\opencode does not exist yet, and copying it would abort the update.
if (-not $NoBackup -and (Test-Path $opencodeDir)) {
  $backupDir = Join-Path $PortableRoot "data\backups\opencode-$currentVer-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Write-Host ""
  Write-Host "  Backing up current opencode to: $backupDir"
  Copy-Item $opencodeDir $backupDir -Recurse -Force
}

# --- 7. Replace apps/opencode ---
Write-Host ""
Write-Host "  Installing new version..."

# Remove old (keep data/ separate so sessions survive)
Remove-Item $opencodeDir -Recurse -Force -ErrorAction SilentlyContinue
Move-Item $newAppDir $opencodeDir -Force

# --- 8. Verify ---
$checkVi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $opencodeDir 'OpenCode.exe'))
$checkVer = "$($checkVi.FileMajorPart).$($checkVi.FileMinorPart).$($checkVi.FileBuildPart)"

Write-Host ""
Write-Host "========================================================"
Write-Host "  Update complete!"
Write-Host "  Old version: $currentVer"
Write-Host "  New version: $checkVer"
Write-Host "  User data preserved in: $PortableRoot\data\"
Write-Host "========================================================"

# --- 9. Cleanup ---
Remove-Item $stageDir, $newAppDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Run Verify.cmd (option 8 in Launch.cmd) to confirm."