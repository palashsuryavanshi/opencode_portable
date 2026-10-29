#Requires -Version 5.1
<#
.SYNOPSIS
    First-time setup for OpenCode Portable (Windows only).

.DESCRIPTION
    Builds a personalised first install: choose the OpenCode variant
    (CLI only, about 78 MB, or CLI + GUI, about 740 MB) and the optional
    toolchains you want. The total size is shown before anything is
    downloaded, and you can change the selection until you are happy with it.
    Every step runs through the same portable installer used later by
    Launch.cmd, so nothing is written outside this folder.
#>
[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# OS guard
# ---------------------------------------------------------------------------
if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
    Write-Host "This setup is for Windows only." -ForegroundColor Red
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = $ScriptDir
foreach ($d in @('apps','data','downloads','projects')) {
    if (-not (Test-Path (Join-Path $Root $d))) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null
    }
}

$Tools = @(
    [pscustomobject]@{ Name = 'vscode';   Label = 'VS Code (portable)';       SizeMB = 1030; Desc = 'portable ZIP edition, data on the stick' }
    [pscustomobject]@{ Name = 'jdk';      Label = 'Temurin JDK 21 LTS';       SizeMB = 330;  Desc = 'Java, needed for Android and Gradle' }
    [pscustomobject]@{ Name = 'android';  Label = 'Android SDK';              SizeMB = 655;  Desc = 'cmdline-tools, platform-tools, build-tools 34/35' }
    [pscustomobject]@{ Name = 'node';     Label = 'Node.js (latest LTS)';     SizeMB = 105;  Desc = 'JavaScript and TypeScript' }
    [pscustomobject]@{ Name = 'go';       Label = 'Go (latest)';              SizeMB = 240;  Desc = 'Go toolchain' }
    [pscustomobject]@{ Name = 'python';   Label = 'Python (full stdlib)';     SizeMB = 250;  Desc = 'includes pip' }
    [pscustomobject]@{ Name = 'dotnet';   Label = '.NET SDK';                 SizeMB = 770;  Desc = 'C# and F#' }
    [pscustomobject]@{ Name = 'rust';     Label = 'Rust (rustup)';            SizeMB = 760;  Desc = 'cargo / rustc, stable toolchain' }
    [pscustomobject]@{ Name = 'git';      Label = 'Git for Windows';          SizeMB = 390;  Desc = 'PortableGit, includes Git Bash' }
    [pscustomobject]@{ Name = 'maven';    Label = 'Maven';                    SizeMB = 12;   Desc = 'Java build tool' }
)

$OpenCodeCliUrl  = 'https://github.com/anomalyco/opencode/releases/latest/download/opencode-windows-x64.zip'
$OpenCodeCliSize = 78
$OpenCodeGuiSize = 740

function Write-Info   { param([string]$m) Write-Host "    $m" -ForegroundColor White }
function Write-Ok2    { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn3  { param([string]$m) Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Write-Err3   { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

function Read-Line {
    param([string]$Prompt, [string]$Default = '')
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $v = Read-Host -Prompt "$Prompt$suffix"
    if (-not $v) { return $Default }
    return $v.Trim()
}

function Save-WithProgress {
    param([string]$Url, [string]$Path, [string]$Label = 'download')
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 300000
    $req.AllowAutoRedirect = $true
    $req.UserAgent = 'OpenCode-Portable-Setup'
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in   = $resp.GetResponseStream()
    $out  = [System.IO.File]::Create($Path)
    $done = 0
    try {
        $buf = New-Object byte[] 131072
        $lastPct = -1
        while (($read = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $read)
            $done += $read
            if ($total -gt 0) {
                $pct = [int]([Math]::Min(100, ($done * 100 / $total)))
                if ($pct -ne $lastPct) {
                    Write-Progress -Activity $Label -Status ("{0} of {1} ({2}%)" -f (Format-Bytes $done), (Format-Bytes $total), $pct) -PercentComplete $pct
                    $lastPct = $pct
                }
            }
        }
    } finally {
        $out.Close(); $in.Close(); $resp.Close()
    }
    Write-Progress -Activity $Label -Completed
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

# ---------------------------------------------------------------------------
# Selection loop
# ---------------------------------------------------------------------------
$setup = $null
$selectedTools = @()
$confirmed = $false
while (-not $confirmed) {
    Clear-Host
    Write-Host "  OpenCode Portable - first-time setup (Windows only)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  App variant:"
    Write-Host "    1. OpenCode CLI only              (about $OpenCodeCliSize MB)"
    Write-Host "    2. OpenCode CLI + GUI             (about $OpenCodeGuiSize MB)"
    $variant = Read-Line -Prompt "  Choose 1 or 2" -Default '2'
    if ($variant -notin @('1','2')) { Write-Warn3 "invalid choice"; Start-Sleep 1; continue }

    Write-Host ""
    Write-Host "  Optional toolchains (enter names, 'a' for all, 'n' for none):"
    foreach ($t in $Tools) {
        $size = "{0,5} MB" -f $t.SizeMB
        Write-Host ("    {0,-9} {1}  -  {2}" -f $t.Name, $size, $t.Desc)
    }
    $raw = Read-Line -Prompt "  Tools" -Default 'n'
    $userTools = @()
    if ($raw -eq 'a') { $userTools = @($Tools.Name) }
    elseif ($raw -eq 'n' -or $raw -eq '') { $userTools = @() }
    else {
        $userTools = @($raw -split '[,\s]+' | Where-Object { $_ } | Sort-Object -Unique)
        foreach ($u in $userTools) {
            if ($u -notin $Tools.Name) { Write-Warn3 "unknown tool: $u" }
        }
        $userTools = @($userTools | Where-Object { $_ -in $Tools.Name })
    }

    $appSize = if ($variant -eq '1') { $OpenCodeCliSize } else { $OpenCodeGuiSize }
    $appLabel = if ($variant -eq '1') { 'OpenCode CLI only' } else { 'OpenCode CLI + GUI' }
    $toolSize = ($Tools | Where-Object { $_.Name -in $userTools } | Measure-Object SizeMB -Sum).Sum
    if ($null -eq $toolSize) { $toolSize = 0 }
    $total = $appSize + $toolSize

    Write-Host ""
    Write-Host "  Planned install:" -ForegroundColor Cyan
    Write-Host "    $appLabel : $appSize MB"
    foreach ($u in $userTools) {
        $t = $Tools | Where-Object Name -eq $u
        Write-Host ("    {0,-9} : {1} MB" -f $t.Name, $t.SizeMB)
    }
    Write-Host ("    {0}" -f ('-' * 30))
    Write-Host ("    TOTAL     : {0} MB  ({1:N2} GB)" -f $total, ($total / 1024)) -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Line -Prompt "  Proceed? (y)es / (m)odify selection / (q)uit" -Default 'y'
    switch ($ans.ToLower()) {
        'y'        { $confirmed = $true }
        'yes'      { $confirmed = $true }
        ''         { $confirmed = $true }
        'm'        { continue }
        'modify'   { continue }
        'q'        { Write-Host "  Aborted."; exit 0 }
        'quit'     { Write-Host "  Aborted."; exit 0 }
        default    { Write-Warn3 "unknown answer"; Start-Sleep 1; continue }
    }

    $setup = [pscustomobject]@{
        Variant = $variant
        Tools   = $userTools
        Total   = $total
    }
    $selectedTools = $userTools
}

$variant = $setup.Variant
$tools   = $setup.Tools
$appSize = if ($variant -eq '1') { $OpenCodeCliSize } else { $OpenCodeGuiSize }

Write-Host ""
Write-Host "  Starting install..." -ForegroundColor Green

if ($DryRun) {
    Write-Host "  [dry run] nothing downloaded."
    exit 0
}

# ---------------------------------------------------------------------------
# 1. OpenCode itself
# ---------------------------------------------------------------------------
if ($variant -eq '1') {
    Write-Host ""
    Write-Host "==> OpenCode CLI (78 MB)" -ForegroundColor Cyan
    $appDir = Join-Path $Root 'apps\opencode'
    $zip    = Join-Path $Root 'downloads\opencode-cli.zip'
    New-Item -ItemType Directory -Force -Path $appDir, (Join-Path $appDir 'resources') | Out-Null
    try {
        Save-WithProgress -Url $OpenCodeCliUrl -Path $zip -Label 'OpenCode CLI'
        $stage = Join-Path $Root 'downloads\_opencode_cli'
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Expand-Archive -Path $zip -DestinationPath $stage -Force
        $exe = Get-ChildItem $stage -Filter 'opencode.exe' -Recurse | Select-Object -First 1
        if (-not $exe) { throw "opencode.exe missing from the CLI archive" }
        Copy-Item $exe.FullName (Join-Path $appDir 'opencode.exe') -Force
        Copy-Item $exe.FullName (Join-Path $appDir 'resources\opencode-cli.exe') -Force
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Write-Ok2 "OpenCode CLI installed"
    } catch {
        Write-Err3 "CLI install failed: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "==> OpenCode CLI + GUI (740 MB)" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $Root 'bin\Update-OpenCode.ps1'))) {
        Write-Err3 "bin\Update-OpenCode.ps1 not found"; exit 1
    }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'bin\Update-OpenCode.ps1') -PortableRoot $Root -Force
    if ($LASTEXITCODE -ne 0) { Write-Err3 "OpenCode GUI install failed"; exit 1 }
}

# ---------------------------------------------------------------------------
# 2. Toolchains
# ---------------------------------------------------------------------------
if ($tools.Count -gt 0) {
    if (-not (Test-Path (Join-Path $Root 'build\install-selected-tools.ps1'))) {
        Write-Err3 "build\install-selected-tools.ps1 not found"; exit 1
    }
    $args = @('-Only', ($tools -join ','), '-Force', '-NoOpenCode')
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'build\install-selected-tools.ps1') @args
    if ($LASTEXITCODE -ne 0) { Write-Warn3 "some toolchains reported failures (see output above)" }
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  First-time setup complete" -ForegroundColor Green
Write-Host "========================================================"
Write-Host ""
if (Test-Path (Join-Path $Root 'bin\Verify.cmd')) {
    & (Join-Path $Root 'bin\Verify.cmd')
}
Write-Host ""
Write-Host "  Launch with Launch.cmd  (option 1 for the GUI, option 2 for the CLI)."