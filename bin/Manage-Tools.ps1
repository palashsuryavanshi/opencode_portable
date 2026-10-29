#Requires -Version 5.1
<#
.SYNOPSIS
    Add or remove the toolchains that live under apps\.

.DESCRIPTION
    Shows every tool in the catalogue, whether it is installed, and how much
    space it uses. Missing tools are installed by delegating to
    build\install-selected-tools.ps1; installed tools are removed by deleting
    their folder under apps\.

    The same menu also launches the tool-facing apps (VS Code, Developer Shell,
    Git Bash, Android SDK Manager), so Launch.cmd only needs the OpenCode and
    housekeeping entries.

    Sessions and everything else that matters is never touched: this script
    only deletes the explicit tool folders listed in Get-ToolDirs. Removing a
    tool never touches data\ or projects\.

    Rust is the one exception that spans two folders: its toolchain lives in
    data\rustup and its shims in data\cargo\bin, so both are removed. The
    cargo registry cache in data\cargo is left alone.

.PARAMETER List
    Show the catalogue and exit.

.PARAMETER Add
    Comma-separated tool names to install, e.g. -Add "python,go".

.PARAMETER Remove
    Comma-separated tool names to remove, e.g. -Remove "vscode,dotnet".

.PARAMETER Launch
    Start a tool-facing app instead of changing anything: vscode, shell, bash
    or android.

.PARAMETER Force
    With -Remove: stop running processes instead of refusing. With -Add:
    reinstall tools that are already present.

.PARAMETER ClearDownloads
    Delete the cached installers in downloads\.

.EXAMPLE
    .\Manage-Tools.ps1
    Interactive add/remove/launch menu.

.EXAMPLE
    .\Manage-Tools.ps1 -List

.EXAMPLE
    .\Manage-Tools.ps1 -Remove "vscode,dotnet"

.EXAMPLE
    .\Manage-Tools.ps1 -Add "python" -Force

.EXAMPLE
    .\Manage-Tools.ps1 -Launch vscode
#>
[CmdletBinding()]
param(
    [string] $Root = '',
    [switch] $List,
    [string] $Add,
    [string] $Remove,
    [string] $Launch,
    [switch] $Force,
    [switch] $ClearDownloads
)

# Resolve the portable root after parameter binding: %PSScriptRoot% is not
# always populated while default parameter values are evaluated.
if (-not $Root) {
    if ($PSScriptRoot) {
        $Root = Split-Path -Parent $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    } else {
        $Root = (Get-Location).Path
    }
}

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$AppsDir   = Join-Path $Root 'apps'
$DlDir     = Join-Path $Root 'downloads'
$Installer = Join-Path $Root 'build\install-selected-tools.ps1'
$PsExe     = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:ForceAll = [bool]$Force

# ---------------------------------------------------------------------------
# Catalogue - names match install-selected-tools.ps1
# ---------------------------------------------------------------------------
$Tools = @(
    [pscustomobject]@{ Name = 'opencode'; Label = 'OpenCode GUI + CLI';   SizeMB = 740;  Desc = 'the app itself';                Required = $true  }
    [pscustomobject]@{ Name = 'vscode';   Label = 'VS Code (portable)';   SizeMB = 1030; Desc = 'settings stay in data\vscode-*'; Required = $false }
    [pscustomobject]@{ Name = 'jdk';      Label = 'Temurin JDK 21 LTS';  SizeMB = 330;  Desc = 'needed by Android and Gradle'; Required = $false }
    [pscustomobject]@{ Name = 'android';  Label = 'Android SDK';         SizeMB = 655;  Desc = 'cmdline-tools, build-tools';   Required = $false }
    [pscustomobject]@{ Name = 'node';     Label = 'Node.js (LTS)';       SizeMB = 105;  Desc = 'JavaScript and TypeScript';    Required = $false }
    [pscustomobject]@{ Name = 'go';       Label = 'Go';                  SizeMB = 240;  Desc = 'Go toolchain';                 Required = $false }
    [pscustomobject]@{ Name = 'python';   Label = 'Python';              SizeMB = 250;  Desc = 'full stdlib with pip';         Required = $false }
    [pscustomobject]@{ Name = 'dotnet';   Label = '.NET SDK';            SizeMB = 770;  Desc = 'C# and F#';                    Required = $false }
    [pscustomobject]@{ Name = 'rust';     Label = 'Rust (rustup)';       SizeMB = 760;  Desc = 'cargo / rustc';                Required = $false }
    [pscustomobject]@{ Name = 'git';      Label = 'Git for Windows';     SizeMB = 390;  Desc = 'PortableGit + Git Bash';       Required = $false }
    [pscustomobject]@{ Name = 'maven';    Label = 'Maven';               SizeMB = 12;   Desc = 'Java build tool';              Required = $false }
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

function Get-ToolDirs {
    param([string]$Name)
    switch ($Name) {
        'opencode' { return @((Join-Path $AppsDir 'opencode')) }
        'vscode'   { return @((Join-Path $AppsDir 'vscode')) }
        'jdk'      { return @((Join-Path $AppsDir 'jdk')) }
        'android'  { return @((Join-Path $AppsDir 'android-sdk')) }
        'node'     { return @((Join-Path $AppsDir 'node')) }
        'go'       { return @((Join-Path $AppsDir 'go')) }
        'python'   { return @((Join-Path $AppsDir 'python')) }
        'dotnet'   { return @((Join-Path $AppsDir 'dotnet')) }
        'rust'     { return @((Join-Path $AppsDir 'rust'),
                              (Join-Path $Root 'data\rustup'),
                              (Join-Path $Root 'data\cargo\bin')) }
        'git'      { return @((Join-Path $AppsDir 'git')) }
        'maven'    { return @((Join-Path $AppsDir 'maven')) }
    }
    return @()
}

function Test-ToolInstalled {
    param([string]$Name)
    switch ($Name) {
        'opencode' { return (Test-Path (Join-Path $AppsDir 'opencode\OpenCode.exe')) }
        'vscode'   { return (Test-Path (Join-Path $AppsDir 'vscode\Code.exe')) }
        'jdk'      { return (Test-Path (Join-Path $AppsDir 'jdk\bin\java.exe')) }
        'android'  { return (Test-Path (Join-Path $AppsDir 'android-sdk\cmdline-tools\latest\bin\sdkmanager.bat')) }
        'node'     { return (Test-Path (Join-Path $AppsDir 'node\node.exe')) }
        'go'       { return (Test-Path (Join-Path $AppsDir 'go\bin\go.exe')) }
        'python'   { return (Test-Path (Join-Path $AppsDir 'python\python.exe')) }
        'dotnet'   { return (Test-Path (Join-Path $AppsDir 'dotnet\dotnet.exe')) }
        'rust'     { return (Test-Path (Join-Path $Root 'data\cargo\bin\cargo.exe')) }
        'git'      { return (Test-Path (Join-Path $AppsDir 'git\cmd\git.exe')) }
        'maven'    { return (Test-Path (Join-Path $AppsDir 'maven\bin\mvn.cmd')) }
    }
    return $false
}

$script:SizeCache = @{}
function Get-ToolSizeMB {
    param([string]$Name)
    if ($script:SizeCache.ContainsKey($Name)) { return $script:SizeCache[$Name] }
    $sum = 0
    foreach ($d in (Get-ToolDirs $Name)) {
        if (Test-Path -LiteralPath $d) {
            $bytes = (Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
                      Measure-Object -Property Length -Sum).Sum
            if ($bytes) { $sum += $bytes }
        }
    }
    $mb = [int]($sum / 1MB)
    $script:SizeCache[$Name] = $mb
    return $mb
}

function Get-ToolProcesses {
    param([string[]]$Dirs)
    @(Get-Process | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { $p = $null }
        if (-not $p) { return $false }
        foreach ($d in $Dirs) {
            if ($p.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    })
}

function Find-Tool {
    param([string]$Text)
    $t = $Text.Trim()
    if ($t -match '^\d+$') {
        $i = [int]$t - 1
        if ($i -ge 0 -and $i -lt $Tools.Count) { return $Tools[$i] }
        return $null
    }
    # Numbers stop at 9; the 10th, 11th, ... entries are a, b, c, ...
    if ($t -match '^[a-z]$') {
        $i = 10 + ([int][char]$t - [int][char]'a') - 1
        if ($i -ge 0 -and $i -lt $Tools.Count) { return $Tools[$i] }
        return $null
    }
    return ($Tools | Where-Object { $_.Name -eq $t.ToLower() } | Select-Object -First 1)
}

# The tool-facing apps now live in this menu instead of Launch.cmd. Each entry
# points at the launcher in bin\, which already loads env.cmd, so PATH and the
# portable data redirection are exactly the same as when they were top-level
# menu items. Keys avoid a/b, which address the 10th/11th catalogue entry.
function Get-LaunchTargets {
    @(
        [pscustomobject]@{ Key = 'v'; Label = 'VS Code';             Name = 'vscode';  Launcher = 'VSCode.cmd' }
        [pscustomobject]@{ Key = 's'; Label = 'Developer Shell';     Name = $null;     Launcher = 'Shell.cmd' }
        [pscustomobject]@{ Key = 'g'; Label = 'Git Bash';            Name = 'git';     Launcher = 'Bash.cmd' }
        [pscustomobject]@{ Key = 'd'; Label = 'Android SDK Manager'; Name = 'android'; Launcher = 'Android.cmd' }
    )
}

function Start-ToolLauncher {
    param([pscustomobject]$Target)
    if ($Target.Name -and -not (Test-ToolInstalled $Target.Name)) {
        Write-Warn2 "$($Target.Label) is not installed."
        Write-Host "       Add '$($Target.Name)' from this menu first." -ForegroundColor DarkGray
        return
    }
    $launcher = Join-Path $Root ('bin\' + $Target.Launcher)
    if (-not (Test-Path $launcher)) {
        Write-Err2 "launcher not found: $launcher"
        return
    }
    Write-Host "  starting $($Target.Label) ..." -ForegroundColor Cyan
    # Interactive launchers (shell, bash, Android) return here when they exit.
    & $env:ComSpec /c "`"$launcher`""
}

function Read-Yes {
    param([string]$Prompt, [bool]$Default = $false)
    $ans = Read-Host $Prompt
    if ($null -eq $ans) { return $false }
    $ans = $ans.Trim().ToLower()
    if ($ans -eq '') { return $Default }
    return ($ans -eq 'y' -or $ans -eq 'yes')
}

function Show-FreeSpace {
    $drive = $Root.Substring(0, 2)
    try {
        $psd = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop
        Write-Host ("  Free on {0}\ : {1} GB" -f $drive, [math]::Round($psd.Free / 1GB, 1)) -ForegroundColor DarkGray
    } catch {
        Write-Host "  Free space: unavailable" -ForegroundColor DarkGray
    }
}

function Show-Tools {
    Write-Host ""
    Write-Host "  OpenCode Portable - tool manager" -ForegroundColor White
    Write-Host "  root: $Root"
    Write-Host ""
    Write-Host ("  {0,-3} {1,-26} {2,-14} {3,9}  {4}" -f '#', 'Tool', 'Status', 'On disk', 'Notes') -ForegroundColor White
    Write-Host ("  " + ('-' * 80)) -ForegroundColor DarkGray
    $i = 0
    foreach ($t in $Tools) {
        $i++
        # Numbers only go up to 9; from the 10th entry on, use letters.
        $key = if ($i -le 9) { [string]$i } else { [string][char]([int][char]'a' + ($i - 10)) }
        $installed = Test-ToolInstalled $t.Name
        $status = 'not installed'
        $size   = ''
        $color  = 'Gray'
        if ($installed) {
            $status = 'installed'
            $size   = "$(Get-ToolSizeMB $t.Name) MB"
            $color  = 'Green'
        }
        Write-Host ("  {0,-3} {1,-26} {2,-14} {3,9}  {4}" -f $key, $t.Label, $status, $size, $t.Desc) -ForegroundColor $color
    }
    Write-Host ("  {0,-3} {1,-26} {2,-14} {3,9}  {4}" -f '-', '7-Zip (bundled)', 'built-in', "$(Get-ToolSizeMB '7zip') MB", 'required by installers') -ForegroundColor DarkGray
    Write-Host ("  " + ('-' * 80)) -ForegroundColor DarkGray
    $installedMB = 0
    foreach ($t in $Tools) { if (Test-ToolInstalled $t.Name) { $installedMB += (Get-ToolSizeMB $t.Name) } }
    $installedMB += (Get-ToolSizeMB '7zip')
    Write-Host ("  tools on disk: {0} MB" -f $installedMB) -ForegroundColor Cyan
    Show-FreeSpace
    Write-Host ""
    Write-Host "  Launch a tool" -ForegroundColor White
    foreach ($t in (Get-LaunchTargets)) {
        $state = 'ready'
        $color = 'Green'
        if ($t.Name -and -not (Test-ToolInstalled $t.Name)) {
            $state = 'not installed - add it here first'
            $color = 'DarkGray'
        }
        Write-Host ("    {0}  {1,-22} {2}" -f $t.Key, $t.Label, $state) -ForegroundColor $color
    }
    Write-Host ""
}

# 7-Zip lives in the catalogue listing but is not a managed tool.
$script:SizeCache['7zip'] = 0
if (Test-Path (Join-Path $AppsDir '7zip')) {
    $b = (Get-ChildItem (Join-Path $AppsDir '7zip') -Recurse -File -Force -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
    if ($b) { $script:SizeCache['7zip'] = [int]($b / 1MB) }
}

# ---------------------------------------------------------------------------
# Add / remove
# ---------------------------------------------------------------------------
function Remove-Tool {
    param([pscustomobject]$Tool)

    if ($Tool.Required) {
        Write-Warn2 "$($Tool.Label) is the application itself - it cannot be removed."
        Write-Host "       Use bin\Update-OpenCode.cmd to reinstall or update it."
        return $false
    }

    if ($Tool.Name -eq 'jdk' -and (Test-ToolInstalled 'android')) {
        Write-Warn2 "the Android SDK manager needs the JDK - sdkmanager will stop working"
    }

    $dirs = Get-ToolDirs $Tool.Name
    $procs = Get-ToolProcesses $dirs
    if ($procs.Count -gt 0) {
        if (-not $script:ForceAll) {
            Write-Err2 "$($Tool.Label) is running:"
            foreach ($p in $procs) { Write-Host "         $($p.ProcessName) ($($p.Id))" }
            Write-Host "       Close it and try again (or use -Force to stop it)."
            return $false
        }
        Write-Warn2 "stopping $($procs.Count) running process(es)"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 20 -and (Get-ToolProcesses $dirs).Count -gt 0; $i++) {
            Start-Sleep -Milliseconds 250
        }
    }

    $failed = $false
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Write-Host "    removing $d"
        # Antivirus scanners can hold a handle for a moment after a process exits.
        for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $d); $i++) {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $d) { Start-Sleep -Milliseconds 800 }
        }
        if (Test-Path -LiteralPath $d) {
            Write-Err2 "could not remove $d - a file is still in use"
            $failed = $true
        }
    }

    $script:SizeCache.Remove($Tool.Name)
    if (-not $failed) {
        if (-not (Test-ToolInstalled $Tool.Name)) {
            Write-Ok "$($Tool.Label) removed"
            Write-Host "       sessions and data\ were not touched." -ForegroundColor DarkGray
            return $true
        }
        Write-Err2 "$($Tool.Label) still reports as installed after removal"
    }
    return $false
}

function Add-Tool {
    param([pscustomobject]$Tool)

    if ($Tool.Required -and (Test-ToolInstalled $Tool.Name) -and -not $script:ForceAll) {
        Write-Ok "$($Tool.Label) is already installed"
        return $true
    }
    if (-not (Test-Path $Installer)) {
        Write-Err2 "installer not found: $Installer"
        return $false
    }

    Write-Step "Installing $($Tool.Label)"
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Installer, '-Only', $Tool.Name)
    if ($script:ForceAll) { $psArgs += '-Force' }
    & $PsExe @psArgs
    $rc = $LASTEXITCODE

    $script:SizeCache.Remove($Tool.Name)
    # The installer exits non-zero if *anything* in its run failed. It always
    # includes OpenCode itself, which is expected to fail on a fresh checkout
    # where the app is not installed yet - so trust the verification of the
    # tool that was actually asked for.
    if (Test-ToolInstalled $Tool.Name) {
        Write-Ok "$($Tool.Label) is installed ($(Get-ToolSizeMB $Tool.Name) MB on disk)"
        if ($rc -ne 0) {
            Write-Warn2 "the installer reported failures for other items (exit code $rc) - see the output above"
        }
        return $true
    }
    Write-Err2 "$($Tool.Label) did not install correctly (exit code $rc)"
    return $false
}

function Clear-Downloads {
    # Never delete the tracked placeholders - only real downloaded installers.
    $files = @(Get-ChildItem -LiteralPath $DlDir -File -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notin @('.gitkeep', '.gitignore') })
    if ($files.Count -eq 0) {
        Write-Host "  downloads\ is already empty." -ForegroundColor DarkGray
        return
    }
    $sum = ($files | Measure-Object -Property Length -Sum).Sum
    $mb = 0
    if ($sum) { $mb = [int]($sum / 1MB) }
    Write-Host "  $($files.Count) cached installer(s), $mb MB in downloads\"
    if (-not $script:ForceAll) {
        if (-not (Read-Yes "  Delete them? [y/N]" $false)) { return }
    }
    foreach ($f in $files) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $DlDir '_unpack') -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "cleared downloads\ - about $mb MB freed"
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------
function Invoke-Menu {
    while ($true) {
        Show-Tools
        Write-Host "  Enter 1-9, a letter (a, b, ...) or a tool name to add or remove that toolchain." -ForegroundColor DarkGray
        Write-Host "  v/s/g/d launch a tool   c = clear downloaded installers   q = quit" -ForegroundColor DarkGray
        Write-Host ""
        $line = Read-Host '  Tool'
        if ($null -eq $line) { break }
        $line = $line.Trim()
        if ($line -eq '') { continue }
        $low = $line.ToLower()
        if ($low -eq 'q' -or $low -eq 'quit') { break }
        if ($low -eq 'c' -or $low -eq 'clear') { Clear-Downloads; continue }

        # Single-letter keys start a tool-facing app; longer input is a tool name.
        if ($low.Length -eq 1) {
            $target = Get-LaunchTargets | Where-Object { $_.Key -eq $low } | Select-Object -First 1
            if ($target) { Start-ToolLauncher $target; continue }
        }

        $tool = Find-Tool $line
        if (-not $tool) {
            Write-Host "  no tool called '$line'" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 900
            continue
        }

        if (Test-ToolInstalled $tool.Name) {
            if ($tool.Required) {
                Write-Host "  $($tool.Label) is required and cannot be removed." -ForegroundColor Yellow
                Start-Sleep -Milliseconds 900
                continue
            }
            if (-not (Read-Yes "  Remove $($tool.Label)? [y/N]" $false)) { continue }
            [void](Remove-Tool $tool)
        } else {
            if (-not (Read-Yes "  Install $($tool.Label) (about $($tool.SizeMB) MB download)? [Y/n]" $true)) { continue }
            [void](Add-Tool $tool)
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ($List) {
    Show-Tools
    exit 0
}

if ($ClearDownloads) {
    Clear-Downloads
    exit 0
}

if ($Launch) {
    # Accept the menu key (v/s/g/d) or the app name. a and b are tools, not
    # launchers, so they are deliberately not aliases here.
    $aliases = @{
        'v' = 'v'; 'vscode' = 'v'; 'code' = 'v'
        's' = 's'; 'shell' = 's'; 'devshell' = 's'
        'g' = 'g'; 'bash' = 'g'; 'gitbash' = 'g'
        'd' = 'd'; 'android' = 'd'; 'sdk' = 'd'
    }
    $key = $Launch.Trim().ToLower()
    if (-not $aliases.ContainsKey($key)) {
        Write-Err2 "unknown launcher '$Launch'"
        Write-Host "       valid names: vscode, shell, bash, android"
        exit 1
    }
    $wanted = $aliases[$key]
    $target = Get-LaunchTargets | Where-Object { $_.Key -eq $wanted } | Select-Object -First 1
    Start-ToolLauncher $target
    exit 0
}

function Resolve-ToolList {
    param([string]$Value)
    $names = @($Value -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    $bad = @($names | Where-Object { $_ -notin $Tools.Name })
    if ($bad.Count -gt 0) {
        Write-Err2 "unknown tool(s): $($bad -join ', ')"
        Write-Host "       valid names: $(($Tools | ForEach-Object { $_.Name }) -join ', ')"
        return $null
    }
    return $names
}

$exitCode = 0

if ($Add) {
    $names = Resolve-ToolList $Add
    if ($null -eq $names) { exit 1 }
    $failed = @()
    foreach ($n in $names) {
        $tool = $Tools | Where-Object { $_.Name -eq $n } | Select-Object -First 1
        if (Test-ToolInstalled $n -and -not $script:ForceAll) {
            Write-Ok "$($tool.Label) already installed - skipping"
            continue
        }
        if (-not (Add-Tool $tool)) { $failed += $n }
    }
    if ($failed.Count -gt 0) { Write-Err2 "failed: $($failed -join ', ')"; $exitCode = 1 }
    exit $exitCode
}

if ($Remove) {
    $names = Resolve-ToolList $Remove
    if ($null -eq $names) { exit 1 }
    $failed = @()
    foreach ($n in $names) {
        $tool = $Tools | Where-Object { $_.Name -eq $n } | Select-Object -First 1
        if (-not (Test-ToolInstalled $n)) {
            Write-Ok "$($tool.Label) is not installed - nothing to do"
            continue
        }
        if (-not (Remove-Tool $tool)) { $failed += $n }
    }
    if ($failed.Count -gt 0) { Write-Err2 "failed: $($failed -join ', ')"; $exitCode = 1 }
    exit $exitCode
}

Invoke-Menu
exit 0
