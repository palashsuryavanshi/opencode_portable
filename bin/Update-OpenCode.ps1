<#
  OpenCode Portable - Updater
  Downloads the latest stable NSIS installer from opencode.ai, extracts it,
  and replaces apps/opencode/ while preserving all user data in data/.

  Usage:
    PowerShell -ExecutionPolicy Bypass -File bin\Update-OpenCode.ps1
    # or from Launch.cmd menu (to be added)
#>

param(
  [string]$PortableRoot = (Split-Path (Split-Path $PSScriptRoot)),
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
$installerPath = Join-Path $PortableRoot 'downloads\opencode-update.exe'

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

if (Test-Path (Join-Path $stageDir '$PLUGINSDIR')) {
  Remove-Item (Join-Path $stageDir '$PLUGINSDIR') -Recurse -Force
}
if (Test-Path (Join-Path $stageDir '$R0')) {
  Remove-Item (Join-Path $stageDir '$R0') -Recurse -Force
}

& 7z x $installerPath -o"$stageDir" -y | Out-Null

$app7z = Join-Path $stageDir '$PLUGINSDIR\app-64.7z'
if (-not (Test-Path $app7z)) {
  Write-Error "Could not find app-64.7z in extracted installer. Installer format may have changed."
  exit 1
}

# --- 4. Extract app-64.7z to staging ---
Write-Host "  Extracting app archive..."
$newAppDir = Join-Path $stageDir 'app-new'
& 7z x $app7z -o"$newAppDir" -y | Out-Null

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
if (-not $NoBackup) {
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
Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Run Verify.cmd (option 8 in Launch.cmd) to confirm."