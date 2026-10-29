<#
  OpenCode Portable - Updater
  Downloads the latest stable NSIS installer from opencode.ai, extracts it,
  and replaces apps/opencode/ while preserving all user data in data/.

  Usage:
    PowerShell -ExecutionPolicy Bypass -File bin\Update-OpenCode.ps1
    PowerShell -ExecutionPolicy Bypass -File bin\Update-OpenCode.ps1 -UpdateTools
    # -UpdateTools also refreshes every installed toolchain (Launch.cmd option 5)

  Housekeeping: after any update the downloaded installers, the staging folders
  and all but the newest data\backups\opencode-* snapshot are deleted.
#>

param(
  [string]$PortableRoot = (Split-Path $PSScriptRoot),
  [string]$DownloadUrl = "https://opencode.ai/download/stable/windows-x64-nsis",
  [switch]$Force,
  [switch]$NoBackup,
  [switch]$UpdateTools
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
$backupsDir  = Join-Path $PortableRoot 'data\backups'
$dlDir       = Join-Path $PortableRoot 'downloads'

$backupHelper = Join-Path $PSScriptRoot 'backup-utils.ps1'
if (Test-Path $backupHelper) { . $backupHelper }

# An app backup is a full copy of the install (~600 MB), so keeping a long
# history fills the stick. Keep the newest one; the live install plus data\ are
# the real state, the backup is just a one-step rollback.
function Remove-OldAppBackups {
    if (-not (Get-Command Remove-OldBackups -ErrorAction SilentlyContinue)) { return }
    $old = Remove-OldBackups -BackupDir $backupsDir -Prefix 'opencode-' -Keep 1
    foreach ($d in $old) { Write-Host "  removed older backup $(Split-Path -Leaf $d)" -ForegroundColor DarkGray }
}

# Downloading an installer just to unpack it leaves hundreds of MB behind.
# After a successful update there is nothing left to reuse - the tool installer
# always re-downloads - so delete the archives and the staging folders.
function Clear-UpdateDownloads {
    Remove-Item $stageDir, $newAppDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dlDir '_unpack') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    $archives = @(Get-ChildItem -LiteralPath $dlDir -File -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -in @('.exe', '.msi', '.zip', '.7z') })
    $freed = 0
    foreach ($f in $archives) {
        $freed += $f.Length
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
    if ($freed -gt 0) {
        Write-Host ("  deleted downloaded installers ({0} MB)" -f [math]::Round($freed / 1MB, 1)) -ForegroundColor DarkGray
    }
}

# Refresh every installed toolchain through the tool manager. OpenCode itself
# is excluded there (Test-ToolInstalled / Update-Tools), because this script
# just replaced it.
function Invoke-ToolUpdate {
    $manager = Join-Path $PortableRoot 'bin\Manage-Tools.ps1'
    if (-not (Test-Path $manager)) {
        Write-Warning "tool manager not found: $manager"
        return $false
    }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Write-Host ""
    Write-Host "========================================================"
    Write-Host "  Updating installed toolchains"
    Write-Host "========================================================"
    & $ps -NoProfile -ExecutionPolicy Bypass -File $manager -Update -Force -Root $PortableRoot
    return ($LASTEXITCODE -eq 0)
}

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

# ---------------------------------------------------------------------------
# Progress reporting
# Write-Progress draws the bar in a console; when the output is redirected the
# same numbers are printed as milestone lines instead.
# ---------------------------------------------------------------------------
$script:TextMode = $false
try { $script:TextMode = [Console]::IsOutputRedirected } catch { $script:TextMode = $true }

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Show-PhaseProgress {
    param([string]$Activity, [string]$Status, [int]$Percent, [int]$Id = 1)
    if ($Percent -lt 0) {
        Write-Progress -Id $Id -Activity $Activity -Status $Status
    } else {
        Write-Progress -Id $Id -Activity $Activity -Status $Status -PercentComplete ([Math]::Min(100, $Percent))
    }
}

function Write-TextProgress {
    param([string]$Text)
    if ($script:TextMode) { Write-Host "    $Text" -ForegroundColor DarkGray }
}

function Get-LastPercent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return -1 }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $len = $fs.Length
            if ($len -le 0) { return -1 }
            $take = [Math]::Min(4096, $len)
            [void]$fs.Seek(-$take, 'End')
            $bytes = New-Object byte[] $take
            [void]$fs.Read($bytes, 0, $take)
            $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        } finally { $fs.Dispose() }
    } catch { return -1 }
    $m = [regex]::Matches($text, '(\d{1,3})\s*%')
    if ($m.Count -eq 0) { return -1 }
    $pct = [int]$m[$m.Count - 1].Groups[1].Value
    if ($pct -lt 0)   { return 0 }
    if ($pct -gt 100) { return 100 }
    return $pct
}

# Download to a file while reporting percentage. Invoke-WebRequest cannot show
# progress when it writes straight to disk, so stream it by hand and fall back
# to Invoke-WebRequest if the request object is unsuitable (proxies, etc.).
function Save-FileWithProgress {
    param([string]$Url, [string]$Path, [string]$Label = 'installer')

    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 300000
    $req.AllowAutoRedirect = $true
    $req.UserAgent = 'OpenCode-Portable'

    $resp  = $req.GetResponse()
    $total = $resp.ContentLength
    $in    = $resp.GetResponseStream()
    $out   = [System.IO.File]::Create($Path)
    $done  = 0
    try {
        $buf = New-Object byte[] 131072
        $lastPct  = -1
        $lastText = -10
        while (($read = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $read)
            $done += $read
            if ($total -gt 0) {
                $pct = [int]($done * 100 / $total)
                if ($pct -ne $lastPct) {
                    Show-PhaseProgress -Activity 'Downloading OpenCode' `
                        -Status ("{0}  {1} of {2} ({3}%)" -f $Label, (Format-Bytes $done), (Format-Bytes $total), $pct) `
                        -Percent $pct -Id 1
                    if (($pct - $lastText) -ge 10) {
                        Write-TextProgress ("downloading {0}  {1}%" -f $Label, $pct)
                        $lastText = $pct
                    }
                    $lastPct = $pct
                }
            } else {
                Show-PhaseProgress -Activity 'Downloading OpenCode' `
                    -Status ("{0}  {1} downloaded" -f $Label, (Format-Bytes $done)) -Percent -1 -Id 1
                if (($done / 1MB) - $lastText -ge 25) {
                    Write-TextProgress ("downloading {0}  {1}" -f $Label, (Format-Bytes $done))
                    $lastText = $done / 1MB
                }
            }
        }
    } finally {
        $out.Close()
        $in.Close()
        $resp.Close()
    }
    return $done
}

# Unpack with 7-Zip while polling its percentage output.
function Expand-WithProgress {
    param([string]$Archive, [string]$Dest, [string]$Label)

    # 7-Zip omits the progress line entirely when a job is very short, so ask
    # it for the unpacked size up front and fall back to measuring the folder
    # while it works. Without this a small archive shows nothing at all.
    $totalBytes = 0
    try {
        & $sevenZip l -slt $Archive 2>$null | ForEach-Object {
            if ($_ -match '^Size = (\d+)$') { $totalBytes += [int64]$Matches[1] }
        }
    } catch { $totalBytes = 0 }

    $log = Join-Path $dlDir ('_7z-' + [guid]::NewGuid().ToString('N') + '.log')
    $err = "$log.err"
    $argString = 'x "' + $Archive + '" -o"' + $Dest + '" -y -bsp2'

    # Start-Process -PassThru cannot report ExitCode on Windows PowerShell 5.1,
    # so start the process directly and pump both streams into log files.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $sevenZip
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $outFs = New-Object System.IO.FileStream($log, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $errFs = New-Object System.IO.FileStream($err, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outFs)
    $errTask = $proc.StandardError.BaseStream.CopyToAsync($errFs)

    $last = -1
    $reported = -10
    $lastByteCheck = Get-Date
    $tick = 0
    Show-PhaseProgress -Activity 'Extracting' -Status ("{0}  0%" -f $Label) -Percent 0 -Id 2
    Write-TextProgress ("extracting {0}  0%" -f $Label)
    while (-not $proc.HasExited) {
        # Fast first samples: a 20 MB archive is unpacked before a 250 ms
        # timer would fire a second time.
        $tick++
        if ($tick -le 8) { Start-Sleep -Milliseconds 80 } else { Start-Sleep -Milliseconds 250 }
        $pct = Get-LastPercent $err
        if ($pct -lt 0) { $pct = Get-LastPercent $log }
        if ($pct -lt 0 -and $totalBytes -gt 0) {
            if (((Get-Date) - $lastByteCheck).TotalMilliseconds -ge 200) {
                $lastByteCheck = Get-Date
                $bytes = 0
                Get-ChildItem -LiteralPath $Dest -Recurse -File -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { $bytes += $_.Length }
                $pct = [int]([Math]::Min(100, ($bytes * 100 / $totalBytes)))
            }
        }
        if ($pct -ge 0 -and $pct -ne $last) {
            Show-PhaseProgress -Activity 'Extracting' -Status ("{0}  {1}%" -f $Label, $pct) -Percent $pct -Id 2
            if (($pct - $reported) -ge 10) {
                Write-TextProgress ("extracting {0}  {1}%" -f $Label, $pct)
                $reported = $pct
            }
            $last = $pct
        }
    }
    if ($last -lt 100) {
        Show-PhaseProgress -Activity 'Extracting' -Status ("{0}  100%" -f $Label) -Percent 100 -Id 2
        if ($reported -lt 100) { Write-TextProgress ("extracting {0}  100%" -f $Label) }
    }
    $proc.WaitForExit()
    [void]$outTask.Wait(5000)
    [void]$errTask.Wait(5000)
    $outFs.Dispose()
    $errFs.Dispose()
    $code = $proc.ExitCode
    Remove-Item -LiteralPath $log, $err -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) {
        Write-Error "7-Zip could not unpack $Archive (exit code $code)."
        exit 1
    }
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
  try {
    $bytes = Save-FileWithProgress -Url $DownloadUrl -Path $installerPath -Label 'installer'
  } catch {
    # Some proxy setups reject a hand-built request; plain IWR still works,
    # it just cannot report progress.
    Write-Host "  Streaming download unavailable - falling back..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 600
    $bytes = (Get-Item $installerPath).Length
  }
  Write-Progress -Id 1 -Activity 'Downloading OpenCode' -Completed
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
Expand-WithProgress -Archive $installerPath -Dest $stageDir -Label 'installer'

# Deliberately a sibling of $stageDir, not a child: enumerating $stageDir while
# $newAppDir sits inside it would pick up app-new and try to move it into itself.

$app7z = Join-Path $stageDir '$PLUGINSDIR\app-64.7z'

if (Test-Path $app7z) {
    Write-Host "  Extracting app archive..."
    Expand-WithProgress -Archive $app7z -Dest $newAppDir -Label 'application'
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

Write-Progress -Id 2 -Activity 'Extracting' -Completed

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
  # Nothing to install, but the download and staging area are still full.
  Clear-UpdateDownloads
  if ($UpdateTools) {
    Remove-OldAppBackups
    if (Invoke-ToolUpdate) { exit 0 } else { exit 1 }
  }
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
Clear-UpdateDownloads
Remove-OldAppBackups

if ($UpdateTools) {
    if (-not (Invoke-ToolUpdate)) {
        Write-Error "OpenCode is updated, but refreshing the toolchains failed. Run bin\Manage-Tools.cmd -Update to retry."
        exit 1
    }
    Remove-OldAppBackups
    Clear-UpdateDownloads
}

Write-Host ""
Write-Host "  Run Verify.cmd (option 4 in Launch.cmd) to confirm."
