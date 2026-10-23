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
# resources\opencode-cli.exe is the binary the desktop app spawns for every
# request. A payload without it installs "successfully" and then fails with
# "spawn ...\resources\opencode-cli.exe ENOENT", so check it up front.
$newExe = Join-Path $newAppDir 'OpenCode.exe'
$newCli = Join-Path $newAppDir 'resources\opencode-cli.exe'
if (-not (Test-Path $newExe) -or -not (Test-Path $newCli)) {
  Write-Error "The extracted app is incomplete (OpenCode.exe or resources\opencode-cli.exe missing)."
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

# --- 6. Stop the app before touching the install ---
# Windows refuses to delete files that are in use. If OpenCode is running,
# Remove-Item deletes what it can and fails on the rest, and the following
# Move-Item then nests the new app inside the half-empty folder
# (apps\opencode\_app_new). That is exactly how a 2.1.3 -> 2.1.4 update broke
# a portable install: resources\opencode-cli.exe was gone afterwards and the
# desktop failed with "spawn ...\resources\opencode-cli.exe ENOENT".
function Get-PortableProcesses {
    param([string]$Dir)
    @(Get-Process | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { $p = $null }
        $p -and $p.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase)
    })
}

$running = Get-PortableProcesses $opencodeDir
if ($running.Count -gt 0) {
    Write-Host ""
    Write-Host "  Stopping OpenCode processes from the stick..."
    foreach ($p in $running) { Write-Host "    $($p.ProcessName) ($($p.Id))" }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (Get-PortableProcesses $opencodeDir).Count -gt 0; $i++) {
        Start-Sleep -Milliseconds 250
    }
    if ((Get-PortableProcesses $opencodeDir).Count -gt 0) {
        Write-Error "OpenCode is still running from $opencodeDir. Close it and run the updater again."
        exit 1
    }
}

# Anything named _app_new inside the install is left over from an earlier
# failed swap - the payload we are about to install lives in downloads\.
$staleDir = Join-Path $opencodeDir '_app_new'
if (Test-Path $staleDir) {
    Write-Host "  Removing stale $staleDir"
    Remove-Item $staleDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 7. Backup current opencode (optional) ---
# Only back up if there is something installed to back up. On a fresh install
# apps\opencode does not exist yet, and copying it would abort the update.
$backupDir = $null
if (-not $NoBackup -and (Test-Path $opencodeDir)) {
  $backupDir = Join-Path $PortableRoot "data\backups\opencode-$currentVer-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Write-Host ""
  Write-Host "  Backing up current opencode to: $backupDir"
  Copy-Item $opencodeDir $backupDir -Recurse -Force
}

# --- 8. Replace apps/opencode ---
Write-Host ""
Write-Host "  Installing new version..."

# Remove old (keep data/ separate so sessions survive). Retry a few times:
# antivirus scanners can hold a handle for a second or two after the app exits.
for ($i = 0; $i -lt 5 -and (Test-Path $opencodeDir); $i++) {
    Remove-Item $opencodeDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $opencodeDir) { Start-Sleep -Seconds 1 }
}
if (Test-Path $opencodeDir) {
    Write-Error "Could not remove $opencodeDir - a file is still in use. Nothing was replaced; the old install is intact."
    exit 1
}

# Move-Item nests the source when the destination exists, so the check above
# guarantees this is a clean rename and not apps\opencode\_app_new.
Move-Item $newAppDir $opencodeDir -Force

# --- 9. Verify ---
$checkExe = Join-Path $opencodeDir 'OpenCode.exe'
$checkCli = Join-Path $opencodeDir 'resources\opencode-cli.exe'
if (-not (Test-Path $checkExe) -or -not (Test-Path $checkCli)) {
    Write-Error "Install verification failed: OpenCode.exe or resources\opencode-cli.exe is missing."
    if ($backupDir -and (Test-Path $backupDir)) {
        Write-Host "  Rolling back to $currentVer ..."
        Remove-Item $opencodeDir -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $backupDir $opencodeDir -Recurse -Force
        Write-Host "  Rollback complete - $currentVer is installed again."
    }
    exit 1
}

$checkVi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($checkExe)
$checkVer = "$($checkVi.FileMajorPart).$($checkVi.FileMinorPart).$($checkVi.FileBuildPart)"

Write-Host ""
Write-Host "========================================================"
Write-Host "  Update complete!"
Write-Host "  Old version: $currentVer"
Write-Host "  New version: $checkVer"
Write-Host "  User data preserved in: $PortableRoot\data\"
Write-Host "========================================================"

# --- 10. Cleanup ---
Remove-Item $stageDir, $newAppDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Run Verify.cmd (option 8 in Launch.cmd) to confirm."