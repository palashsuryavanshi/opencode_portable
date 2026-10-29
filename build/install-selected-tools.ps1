#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive, selective tool installer for OpenCode Portable (Windows).

.DESCRIPTION
    The full bundle is roughly 7 GB. This script lets the user pick only the
    toolchains they actually want, shows sizes and checks free space before
    downloading anything, and verifies each tool after install.

    Everything lands under <ROOT>\apps. The script never touches
    <ROOT>\data (chat sessions, caches) or <ROOT>\projects.

.PARAMETER All
    Install every tool. Non-interactive.

.PARAMETER Minimal
    Install only OpenCode itself. Non-interactive.

.PARAMETER Only
    Comma-separated tool names to install. Non-interactive.

.PARAMETER Force
    Reinstall tools that are already present.

.PARAMETER List
    Show the tool catalogue and exit.

.PARAMETER NoAndroid
    Skip Android SDK package installation (keep the command-line tools).

.PARAMETER NoOpenCode
    Do not add OpenCode itself to the selection. Used by bin\Manage-Tools.ps1,
    which updates toolchains while the app is handled by its own updater.

.EXAMPLE
    .\install-selected-tools.ps1
    Install interactively, choosing tools.

.EXAMPLE
    .\install-selected-tools.ps1 -Minimal
    Install only OpenCode.

.EXAMPLE
    .\install-selected-tools.ps1 -Only "jdk,node,go"
    Install exactly those toolchains, unattended.
#>
[CmdletBinding()]
param(
    [switch] $All,
    [switch] $Minimal,
    [string] $Only,
    [switch] $Force,
    [switch] $List,
    [switch] $NoAndroid,
    [switch] $NoOpenCode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = Split-Path -Parent $ScriptDir          # portable root
$AppsDir   = Join-Path $Root 'apps'
$DlDir     = Join-Path $Root 'downloads'
$UnpackDir = Join-Path $DlDir   '_unpack'

foreach ($d in @($AppsDir, $DlDir, $UnpackDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# ---------------------------------------------------------------------------
# Tool catalogue
# ---------------------------------------------------------------------------
# SizeMB is the approximate size once installed on disk.
$Tools = @(
    [pscustomobject]@{ Name = 'opencode'; Label = 'OpenCode GUI + CLI';        SizeMB = 740;  Desc = 'The AI coding assistant (required)' }
    [pscustomobject]@{ Name = 'vscode';   Label = 'VS Code (portable)';        SizeMB = 1030; Desc = 'Portable ZIP edition, data on the stick' }
    [pscustomobject]@{ Name = 'jdk';      Label = 'Temurin JDK 21 LTS';       SizeMB = 330;  Desc = 'Java, needed for Android and Gradle' }
    [pscustomobject]@{ Name = 'android';  Label = 'Android SDK';              SizeMB = 655;  Desc = 'cmdline-tools, platform-tools, build-tools 34/35' }
    [pscustomobject]@{ Name = 'node';     Label = 'Node.js (latest LTS)';     SizeMB = 105;  Desc = 'JavaScript and TypeScript' }
    [pscustomobject]@{ Name = 'go';       Label = 'Go (latest)';              SizeMB = 240;  Desc = 'Go toolchain' }
    [pscustomobject]@{ Name = 'python';   Label = 'Python (full stdlib)';     SizeMB = 250;  Desc = 'includes pip; embeddable build will NOT work' }
    [pscustomobject]@{ Name = 'dotnet';   Label = '.NET SDK';                 SizeMB = 770;  Desc = 'C# and F#' }
    [pscustomobject]@{ Name = 'rust';     Label = 'Rust (rustup)';            SizeMB = 760;  Desc = 'cargo / rustc, stable toolchain' }
    [pscustomobject]@{ Name = 'git';      Label = 'Git for Windows';          SizeMB = 390;  Desc = 'PortableGit, includes Git Bash' }
    [pscustomobject]@{ Name = 'maven';    Label = 'Maven';                    SizeMB = 12;   Desc = 'Java build tool' }
)

function Write-Step  { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "    [ok]   $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Progress reporting
#
# Write-Progress draws the bar when the script runs in a console. When the
# output is redirected (logs, automation) it renders nothing, so the same
# numbers are also emitted as milestone lines in that case.
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
    param(
        [string] $Activity,
        [string] $Status,
        [int]    $Percent,
        [int]    $Id = 1
    )
    if ($Percent -lt 0) {
        Write-Progress -Id $Id -Activity $Activity -Status $Status
    } else {
        Write-Progress -Id $Id -Activity $Activity -Status $Status -PercentComplete ([Math]::Min(100, $Percent))
    }
}

function Write-TextProgress {
    # Console-friendly copy of the bar for redirected output.
    param([string]$Text)
    if ($script:TextMode) { Write-Host "    $Text" -ForegroundColor DarkGray }
}

# Read the last "NN%" that a child process wrote. 7-Zip and the Android SDK
# manager both update a single line, so the tail of the log is enough.
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

function Quote-Arg {
    param([string]$Value)
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

# Total unpacked bytes in an archive, read from 7-Zip's listing. Used as the
# denominator when the extractor never prints a percentage (it skips the
# progress line entirely when a job finishes in well under a second).
function Get-ArchiveBytes {
    param([string]$Archive, [string]$SevenZip)
    if (-not $SevenZip) { $SevenZip = Find-7z }
    if (-not $SevenZip -or -not $Archive) { return 0 }
    $sum = 0
    try {
        & $SevenZip l -slt $Archive 2>$null | ForEach-Object {
            if ($_ -match '^Size = (\d+)$') { $sum += [int64]$Matches[1] }
        }
    } catch { return 0 }
    return $sum
}

function Get-DirBytes {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = 0
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length }
    return $sum
}

# Install-phase position, set by the main loop so nested extraction can report
# a slice of the overall percentage instead of restarting at 0 for each tool.
$script:InstallBase = 0
$script:InstallSpan = 100
$script:ProgressLabel = ''

# Run a child process while polling the percentages it prints (7-Zip, Android
# sdkmanager, rustup). Falls back to a plain wait when the child prints none.
function Invoke-ChildWithProgress {
    param(
        [string]   $FilePath,
        [string[]] $Arguments,
        [string]   $RawArguments,
        [string]   $Label,
        [int]      $BasePercent = -1,
        [int]      $SpanPercent = -1,
        [string]   $ByteDir,
        [int64]    $ByteTotal = 0,
        [int]      $Id = 2
    )
    if ($BasePercent -lt 0) { $BasePercent = $script:InstallBase }
    if ($SpanPercent -lt 0) { $SpanPercent = $script:InstallSpan }
    if (-not $Label) { $Label = $script:ProgressLabel }

    $argString = $RawArguments
    if (-not $argString) {
        $argString = (@($Arguments) | ForEach-Object { Quote-Arg $_ }) -join ' '
    }

    $log = Join-Path $UnpackDir ('progress-' + [guid]::NewGuid().ToString('N') + '.log')
    $err = "$log.err"

    # Start-Process -PassThru cannot report ExitCode on Windows PowerShell 5.1,
    # so drive the process directly and pump both streams into files we can
    # poll for percentages.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
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
    $started = Get-Date
    $lastTick = -1
    $lastByteCheck = $started
    $tick = 0
    Show-PhaseProgress -Activity 'Installing tools' -Status ("{0}  0%" -f $Label) -Percent $BasePercent -Id $Id
    Write-TextProgress ("{0}  0%" -f $Label)
    while (-not $proc.HasExited) {
        # Poll quickly at the start: small archives extract in a few hundred
        # milliseconds and a slow first sample would show 0% and then done.
        $tick++
        if ($tick -le 8) { Start-Sleep -Milliseconds 80 } else { Start-Sleep -Milliseconds 250 }
        $pct = Get-LastPercent $err
        if ($pct -lt 0) { $pct = Get-LastPercent $log }
        if ($pct -lt 0 -and $ByteDir -and $ByteTotal -gt 0) {
            # The child prints no percentage, but we know how many bytes the
            # archive should produce, so measure the folder it writes into.
            if (((Get-Date) - $lastByteCheck).TotalMilliseconds -ge 200) {
                $lastByteCheck = Get-Date
                $pct = [int]([Math]::Min(100, ((Get-DirBytes $ByteDir) * 100 / $ByteTotal)))
            }
        }
        if ($pct -ge 0 -and $pct -ne $last) {
            $overall = $BasePercent + [int]($SpanPercent * $pct / 100)
            Show-PhaseProgress -Activity 'Installing tools' -Status ("{0}  {1}%" -f $Label, $pct) -Percent $overall -Id $Id
            if ($pct - $reported -ge 10 -or ($last -lt 0 -and $pct -gt 0)) {
                Write-TextProgress ("{0}  {1}%" -f $Label, $pct)
                $reported = $pct
            }
            $last = $pct
        } elseif ($pct -lt 0) {
            # No percentage from this child (rustup, for example). Show that
            # work is still happening instead of a frozen bar.
            $secs = [int]((Get-Date) - $started).TotalSeconds
            if ($secs -ne $lastTick -and ($secs % 5) -eq 0) {
                Show-PhaseProgress -Activity 'Installing tools' -Status ("{0}  working {1}s" -f $Label, $secs) -Percent $BasePercent -Id $Id
                if ($secs -ge 15 -and ($secs % 15) -eq 0) {
                    Write-TextProgress ("{0}  working {1}s" -f $Label, $secs)
                }
                $lastTick = $secs
            }
        }
    }
    if ($last -lt 100) {
        $overall = $BasePercent + $SpanPercent
        Show-PhaseProgress -Activity 'Installing tools' -Status ("{0}  100%" -f $Label) -Percent $overall -Id $Id
        if ($reported -lt 100) { Write-TextProgress ("{0}  100%" -f $Label) }
    }
    $proc.WaitForExit()
    [void]$outTask.Wait(5000)
    [void]$errTask.Wait(5000)
    $outFs.Dispose()
    $errFs.Dispose()
    $code = $proc.ExitCode

    if ($code -ne 0) {
        Write-Warn2 "$Label exited with code $code"
        if (Test-Path -LiteralPath $log) {
            Get-Content -LiteralPath $log -Tail 5 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        }
    }
    Remove-Item -LiteralPath $log, $err -Force -ErrorAction SilentlyContinue
    return $code
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Find-7z {
    # Prefer the 7-Zip bundled inside the portable (apps\7zip\7za.exe). It is a
    # standalone build, so it works on a machine where 7-Zip was never installed
    # and nothing needs to be added to the host.
    $bundled = Join-Path $AppsDir '7zip\7za.exe'
    if (Test-Path $bundled) { return $bundled }

    # Fall back to whatever the host happens to have.
    $c = Get-Command 7z, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
    )) { if (Test-Path $p) { return $p } }
    return $null
}

# Unpack the OpenCode NSIS installer.
#
# Layout depends on which 7-Zip build is used:
#   * full 7z.exe  ->  $PLUGINSDIR\app-64.7z  (a second archive to unpack)
#   * bundled 7za  ->  the app files appear directly at the top level
# Handle both, otherwise the updater appears to succeed but installs nothing.
function Expand-OpenCodeNsis {
    param([string] $Installer, [string] $Dest)

    $seven = Find-7z
    if (-not $seven) { throw "7-Zip not found. Install it and re-run." }
    $stage = Join-Path $UnpackDir 'opencode-nsis'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

    # The NSIS wrapper is tiny; almost all of the work is the payload inside.
    $wrapperSpan = [int]($script:InstallSpan * 0.25)
    $rc = Invoke-ChildWithProgress -FilePath $seven `
              -Arguments @('x', $Installer, "-o$stage", '-y', '-bsp2') `
              -Label ($script:ProgressLabel + ' installer') `
              -BasePercent $script:InstallBase -SpanPercent $wrapperSpan `
              -ByteDir $stage -ByteTotal (Get-ArchiveBytes -Archive $Installer -SevenZip $seven)
    if ($rc -ne 0) { throw "7-Zip could not unpack the OpenCode installer (exit code $rc)" }

    $inner = Join-Path $stage '$PLUGINSDIR\app-64.7z'
    if (Test-Path $inner) {
        Expand-ArchiveSmart -Archive $inner -Dest $Dest -StripWrapper $false `
            -BasePercent ($script:InstallBase + $wrapperSpan) `
            -SpanPercent ($script:InstallSpan - $wrapperSpan)
    } elseif (Test-Path (Join-Path $stage 'OpenCode.exe')) {
        if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Get-ChildItem $stage -Force | ForEach-Object { Move-Item $_.FullName -Destination $Dest -Force }
    } else {
        throw "could not find OpenCode.exe in the installer payload"
    }

    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

# Expand an archive. $StripWrapper moves the contents of the single wrapper
# directory up into $Dest. Many tool archives nest everything one level deep;
# getting this wrong leaves the tool one folder too deep and breaks PATH.
function Expand-ArchiveSmart {
    param(
        [string] $Archive,
        [string] $Dest,
        [bool]   $StripWrapper,
        [int]    $BasePercent = -1,
        [int]    $SpanPercent = -1
    )
    $seven = Find-7z
    if (-not $seven) { throw "7-Zip not found. Install it and re-run." }
    $archiveBytes = Get-ArchiveBytes -Archive $Archive -SevenZip $seven

    if ($StripWrapper) {
        $stage = Join-Path $UnpackDir ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $rc = Invoke-ChildWithProgress -FilePath $seven `
                  -Arguments @('x', $Archive, "-o$stage", '-y', '-bsp2') `
                  -Label $script:ProgressLabel -BasePercent $BasePercent -SpanPercent $SpanPercent `
                  -ByteDir $stage -ByteTotal $archiveBytes
        if ($rc -ne 0) { throw "7-Zip could not extract $Archive (exit code $rc)" }
        $child = Get-ChildItem $stage -Directory | Select-Object -First 1
        if ($child) {
            if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $Dest | Out-Null
            Get-ChildItem $child.FullName -Force | ForEach-Object {
                Move-Item $_.FullName -Destination $Dest -Force
            }
        } else {
            New-Item -ItemType Directory -Force -Path $Dest | Out-Null
            Get-ChildItem $stage -Force | ForEach-Object {
                Move-Item $_.FullName -Destination $Dest -Force
            }
        }
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        $rc = Invoke-ChildWithProgress -FilePath $seven `
                  -Arguments @('x', $Archive, "-o$Dest", '-y', '-bsp2') `
                  -Label $script:ProgressLabel -BasePercent $BasePercent -SpanPercent $SpanPercent `
                  -ByteDir $Dest -ByteTotal $archiveBytes
        if ($rc -ne 0) { throw "7-Zip could not extract $Archive (exit code $rc)" }
    }
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

# ---------------------------------------------------------------------------
# URL resolution - each tool resolves its own current stable release
# ---------------------------------------------------------------------------
function Resolve-Url {
    param([string]$Name)

    switch ($Name) {

        'opencode' {
            return 'https://opencode.ai/download/stable/windows-x64-nsis'
        }

        'vscode' {
            return 'https://update.code.visualstudio.com/latest/win32-x64-archive/stable'
        }

        'jdk' {
            $a = Invoke-RestMethod 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
            return $a[0].binary.package.link
        }

        'go' {
            $rel = Invoke-RestMethod 'https://go.dev/dl/?mode=json'
            $f = $rel[0].files | Where-Object {
                $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive'
            } | Select-Object -First 1
            return "https://go.dev/dl/$($f.filename)"
        }

        'node' {
            $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
            $n = $idx | Where-Object { $_.lts -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1
            return "https://nodejs.org/dist/$($n.version)/node-$($n.version)-win-x64.zip"
        }

        'maven' {
            $h = Invoke-WebRequest 'https://dlcdn.apache.org/maven/maven-3/' -UseBasicParsing
            $v = ([regex]::Matches($h.Content, '3\.\d+\.\d+') |
                  ForEach-Object { $_.Value } |
                  Sort-Object -Unique -Descending | Select-Object -First 1)
            return "https://dlcdn.apache.org/maven/maven-3/$v/binaries/apache-maven-$v-bin.zip"
        }

        'git' {
            # PortableGit is a self-extracting 7z whose payload is ALREADY FLAT.
            # Do not strip a wrapper directory here - doing so yields only bin\.
            $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
                                    -Headers @{ 'User-Agent' = 'opencode-portable' }
            $a = $rel.assets | Where-Object { $_.name -match 'PortableGit.*64-bit\.7z\.exe$' } | Select-Object -First 1
            return $a.browser_download_url
        }

        'dotnet' {
            # Channel 9.0 LTS. The SDK zip is already flat (no wrapper folder).
            $idx = Invoke-RestMethod 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json'
            $ch  = $idx.'releases-index' |
                   Where-Object { $_.'channel-version' -eq '9.0' -and $_.'support-phase' -eq 'active' } |
                   Select-Object -First 1
            if (-not $ch) { $ch = $idx.'releases-index' | Select-Object -First 1 }
            $sdk = Invoke-RestMethod $ch.'releases-json'
            $rel = $sdk.releases | Where-Object { $_.sdk.version -eq $ch.'latest-sdk' } | Select-Object -First 1
            $f = $rel.sdk.files | Where-Object {
                $_.name -match 'win-x64\.zip$' -and $_.name -notmatch 'aspnetcore|runtime'
            } | Select-Object -First 1
            return $f.url
        }

        'python' {
            # The embeddable zip has no pip and no ensurepip, so `python -m pip`
            # fails afterwards. Use the full stdlib from NuGet instead; the
            # package unpacks into a tools\ directory that we flatten.
            $html = Invoke-WebRequest 'https://www.python.org/downloads/windows/' -UseBasicParsing
            $link = $html.Links | Where-Object { $_.href -match 'python-3\.13\.\d+-amd64\.exe$' } | Select-Object -First 1
            $ver  = if ($link) { ([regex]::Match($link.href, '3\.13\.\d+')).Value } else { '3.13.0' }
            return "https://www.nuget.org/api/v2/package/python/$ver"
        }

        'rust' {
            return 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
        }

        'android' {
            $xml = Invoke-WebRequest 'https://dl.google.com/android/repository/repository2-3.xml' -UseBasicParsing
            $m = [regex]::Match($xml.Content, 'commandlinetools-win-(\d+)_latest\.zip')
            return "https://dl.google.com/android/repository/commandlinetools-win-$($m.Groups[1].Value)_latest.zip"
        }
    }
    return $null
}

function Get-ArchiveName {
    param([string]$Name, [string]$Url)
    switch ($Name) {
        'opencode' { return 'opencode-setup.exe' }
        'vscode'   { return 'vscode.zip' }
        'jdk'      { return 'jdk.zip' }
        'android'  { return 'android-cmdline.zip' }
        'node'     { return 'node.zip' }
        'go'       { return 'go.zip' }
        'python'   { return 'python.nupkg' }
        'dotnet'   { return 'dotnet.zip' }
        'rust'     { return 'rustup-init.exe' }
        'git'      { return 'portablegit.7z.exe' }
        'maven'    { return 'maven.zip' }
    }
    $leaf = [System.IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
    if (-not $leaf) { return "$Name.bin" }
    return $leaf
}

# ---------------------------------------------------------------------------
# Installers
# ---------------------------------------------------------------------------
function Install-OpenCode {
    param([string]$Archive)
    Expand-OpenCodeNsis -Installer $Archive -Dest (Join-Path $AppsDir 'opencode')

    # Verify the bundled CLI too - the GUI depends on it
    $cli = Join-Path $AppsDir 'opencode\resources\opencode-cli.exe'
    if (-not (Test-Path $cli)) { throw "opencode-cli.exe missing from resources" }
    $ver = & $cli --version 2>&1 | Select-Object -First 1
    Write-Ok "OpenCode GUI + CLI  ($ver)"
}

function Install-Vscode {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'vscode') -StripWrapper $false
    # A 'data' folder next to Code.exe is what makes the ZIP edition portable
    New-Item -ItemType Directory -Force -Path (Join-Path $AppsDir 'vscode\data') | Out-Null
    Write-Ok "VS Code  $((Get-Item (Join-Path $AppsDir 'vscode\Code.exe')).VersionInfo.ProductVersion)"
}

function Install-Jdk {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'jdk') -StripWrapper $true
    # Verify against the folder that actually contains bin\java.exe. A plain
    # wildcard would pick ...\jdk\lib, which is not a usable JAVA_HOME.
    $home = Get-ChildItem (Join-Path $AppsDir 'jdk') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } |
            Select-Object -First 1
    if (-not $home) { $home = Get-Item (Join-Path $AppsDir 'jdk') }
    $v = & (Join-Path $home.FullName 'bin\java.exe') -version 2>&1 | Select-Object -First 1
    Write-Ok "JDK  $v"
}

function Install-Go {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'go') -StripWrapper $true
    $v = & (Join-Path $AppsDir 'go\bin\go.exe') version
    Write-Ok "Go  $v"
}

function Install-Node {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'node') -StripWrapper $true
    $v = & (Join-Path $AppsDir 'node\node.exe') -v
    Write-Ok "Node  $v"
}

function Install-Maven {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'maven') -StripWrapper $true
    Write-Ok "Maven  installed"
}

function Install-Git {
    param([string]$Archive)
    # FLAT payload - do not strip a wrapper
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'git') -StripWrapper $false
    if (-not (Test-Path (Join-Path $AppsDir 'git\cmd\git.exe'))) {
        throw "git\cmd\git.exe missing - PortableGit should be extracted flat"
    }
    $v = & (Join-Path $AppsDir 'git\cmd\git.exe') --version
    Write-Ok "Git  $v"
}

function Install-Dotnet {
    param([string]$Archive)
    Expand-ArchiveSmart -Archive $Archive -Dest (Join-Path $AppsDir 'dotnet') -StripWrapper $false
    $env:DOTNET_ROOT = Join-Path $AppsDir 'dotnet'
    $v = & (Join-Path $AppsDir 'dotnet\dotnet.exe') --version
    Write-Ok ".NET  $v"
}

function Install-Python {
    param([string]$Archive)
    $dest = Join-Path $AppsDir 'python'
    $seven = Find-7z
    $stage = Join-Path $UnpackDir 'python'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $extractSpan = [int]($script:InstallSpan * 0.65)
    $rc = Invoke-ChildWithProgress -FilePath $seven `
              -Arguments @('x', $Archive, "-o$stage", '-y', '-bsp2') `
              -Label $script:ProgressLabel -BasePercent $script:InstallBase -SpanPercent $extractSpan `
              -ByteDir $stage -ByteTotal (Get-ArchiveBytes -Archive $Archive -SevenZip $seven)
    if ($rc -ne 0) { throw "7-Zip could not extract $Archive (exit code $rc)" }

    # The NuGet package unpacks to tools\ which holds the real interpreter
    $tools = Join-Path $stage 'tools'
    if (Test-Path $tools) {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem $tools -Force | ForEach-Object { Move-Item $_.FullName -Destination $dest -Force }
    } else {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem $stage -Force | ForEach-Object { Move-Item $_.FullName -Destination $dest -Force }
    }
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

    $py = Join-Path $dest 'python.exe'
    # Bootstrap pip: the NuGet build ships without it
    $pipBase = $script:InstallBase + $extractSpan
    Show-PhaseProgress -Activity 'Installing tools' -Status ("{0}  bootstrapping pip" -f $script:ProgressLabel) -Percent $pipBase -Id 2
    Write-TextProgress ("{0}  bootstrapping pip" -f $script:ProgressLabel)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest 'https://bootstrap.pypa.io/get-pip.py' -OutFile (Join-Path $dest 'get-pip.py') -UseBasicParsing
    & $py (Join-Path $dest 'get-pip.py') --quiet 2>&1 | Out-Null

    # pip entry points are not generated, so provide wrappers
    $scripts = Join-Path $dest 'Scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    foreach ($n in @('pip', 'pip3')) {
        $bat = Join-Path $scripts "$n.bat"
        $body = "@echo off`r`nsetlocal`r`nset `"PYTHONHOME=%~dp0..`"`r`n`"%~dp0..\python.exe`" -m $n %*`r`n"
        [System.IO.File]::WriteAllText($bat, $body)
    }

    $v = & $py -c 'import sys; print(sys.version.split()[0])'
    Write-Ok "Python  $v (pip bootstrapped)"
}

function Install-Rust {
    param([string]$Archive)
    $cargo  = Join-Path $Root 'data\cargo'
    $rustup = Join-Path $Root 'data\rustup'
    New-Item -ItemType Directory -Force -Path $cargo, $rustup | Out-Null
    $env:CARGO_HOME   = $cargo
    $env:RUSTUP_HOME  = $rustup
    # rustup-init prints no percentages, so the helper shows elapsed time and
    # keeps the bar alive while it downloads the toolchain.
    $rc = Invoke-ChildWithProgress -FilePath $Archive `
              -Arguments @('-y', '--no-modify-path', '--default-toolchain', 'stable', '--profile', 'minimal') `
              -Label $script:ProgressLabel -BasePercent $script:InstallBase -SpanPercent $script:InstallSpan
    if ($rc -ne 0) { throw "rustup-init failed (exit code $rc)" }
    $v = & (Join-Path $cargo 'bin\cargo.exe') --version
    Write-Ok "Rust  $v"
}

function Install-Android {
    param([string]$Archive)
    $sdk = Join-Path $AppsDir 'android-sdk'
    $seven = Find-7z
    $stage = Join-Path $UnpackDir 'androidcmd'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $cmdSpan = [int]($script:InstallSpan * 0.25)
    $rc = Invoke-ChildWithProgress -FilePath $seven `
              -Arguments @('x', $Archive, "-o$stage", '-y', '-bsp2') `
              -Label $script:ProgressLabel -BasePercent $script:InstallBase -SpanPercent $cmdSpan `
              -ByteDir $stage -ByteTotal (Get-ArchiveBytes -Archive $Archive -SevenZip $seven)
    if ($rc -ne 0) { throw "7-Zip could not extract $Archive (exit code $rc)" }

    # The SDK manager only runs from a directory literally named 'latest'
    $cl = Join-Path $sdk 'cmdline-tools'
    if (Test-Path $cl) { Remove-Item $cl -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $cl | Out-Null
    Move-Item (Join-Path $stage 'cmdline-tools') (Join-Path $cl 'latest') -Force
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

    # JAVA_HOME must point at the folder that holds bin\java.exe
    $jdkHome = Get-ChildItem (Join-Path $AppsDir 'jdk') -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } |
               Select-Object -First 1
    if (-not $jdkHome -and (Test-Path (Join-Path $AppsDir 'jdk\bin\java.exe'))) {
        $jdkHome = Get-Item (Join-Path $AppsDir 'jdk')
    }
    $env:JAVA_HOME = if ($jdkHome) { $jdkHome.FullName } else { Join-Path $AppsDir 'jdk' }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk

    $sdkm = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    Write-Ok "Android command-line tools installed"

    if ($NoAndroid) { Write-Warn2 "skipping SDK packages (-NoAndroid)"; return }

    # Licences are non-interactive. The tool blocks on stdin when it inherits
    # a console, so pipe a supply of 'y' rather than letting it wait.
    Write-TextProgress ("{0}  accepting SDK licences" -f $script:ProgressLabel)
    1..40 | ForEach-Object { 'y' } | & $sdkm --sdk_root="$sdk" --licenses 2>&1 | Out-Null

    # NOTE: the current cmdline-tools delegate to the new `android` CLI, which
    # takes sdk-style paths with FORWARD SLASHES. The semicolon form fails
    # with "Package not found".
    $pkgs = @('platform-tools', 'build-tools/35.0.0', 'platforms/android-35',
              'build-tools/34.0.0', 'platforms/android-34')
    $pkgBase = $script:InstallBase + $cmdSpan + [int]($script:InstallSpan * 0.05)
    $pkgSpan = $script:InstallSpan - $cmdSpan - [int]($script:InstallSpan * 0.05)
    $k = 0
    foreach ($p in $pkgs) {
        Write-Host "    installing $p ..."
        $b  = $pkgBase + [int]($pkgSpan * $k / $pkgs.Count)
        $sp = [int]($pkgSpan * ($k + 1) / $pkgs.Count) - [int]($pkgSpan * $k / $pkgs.Count)
        $cmdLine = '/c "' + $sdkm + '" --sdk_root="' + $sdk + '" ' + $p
        [void](Invoke-ChildWithProgress -FilePath $env:ComSpec -RawArguments $cmdLine `
                   -Label ("android " + $p) -BasePercent $b -SpanPercent $sp)
        $k++
    }

    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    if (Test-Path $adb) {
        $env:PATH = "$(Join-Path $sdk 'platform-tools');$env:PATH"
        $v = (& $adb version 2>&1 | Select-Object -First 1)
        Write-Ok "Android SDK  ($v)"
    } else {
        throw "adb.exe missing after package install"
    }
}

# ---------------------------------------------------------------------------
# Catalogue display / selection
# ---------------------------------------------------------------------------
function Show-Catalogue {
    Write-Host ""
    Write-Host "  OpenCode Portable - tool installer" -ForegroundColor White
    Write-Host "  root: $Root"
    Write-Host ""
    Write-Host ("  {0,-3} {1,-26} {2,7}  {3}" -f '#', 'Tool', 'Size', 'Notes') -ForegroundColor White
    Write-Host "  " ('-' * 74) -ForegroundColor DarkGray
    $i = 0
    foreach ($t in $Tools) {
        $i++
        $mark = if (Test-ToolInstalled $t.Name) { 'installed' } else { '' }
        Write-Host ("  {0,-3} {1,-26} {2,6} MB  {3} {4}" -f $i, $t.Label, $t.SizeMB, $t.Desc, $mark)
    }
    Write-Host "  " ('-' * 74) -ForegroundColor DarkGray
    $total = ($Tools | Measure-Object SizeMB -Sum).Sum
    Write-Host ("  {0,-30} {1,6} MB  (full bundle)" -f 'TOTAL', $total)
    Write-Host ""
}

function Select-Tools {
    Show-Catalogue
    Write-Host "  Enter numbers to toggle, separated by spaces or commas." -ForegroundColor DarkGray
    Write-Host "  Useful: 'a' = all, 'n' = none, 'q' = quit" -ForegroundColor DarkGray
    Write-Host ""

    $sel = @{}
    for ($i = 0; $i -lt $Tools.Count; $i++) { $sel[$Tools[$i].Name] = $false }

    while ($true) {
        $line = Read-Host '  Your selection'
        # EOF (no more input) returns $null - stop rather than spin forever
        if ($null -eq $line) { break }
        $line = $line.Trim().ToLower()

        if ($line -eq 'q') { exit 0 }
        if ($line -eq 'a') { foreach ($k in $sel.Keys) { $sel[$k] = $true }; break }
        if ($line -eq 'n' -or $line -eq '') { break }

        foreach ($tok in ($line -split '[,\s]+')) {
            if ($tok -match '^\d+$') {
                $idx = [int]$tok - 1
                if ($idx -ge 0 -and $idx -lt $Tools.Count) {
                    $n = $Tools[$idx].Name
                    $sel[$n] = -not $sel[$n]
                } else {
                    Write-Warn2 "no tool numbered $tok"
                }
            }
        }

        Write-Host ""
        foreach ($t in $Tools) {
            $mark = if ($sel[$t.Name]) { 'x' } else { ' ' }
            $inst = if (Test-ToolInstalled $t.Name) { ' (already installed)' } else { '' }
            Write-Host ("   [{0}] {1,-26} {2,6} MB{3}" -f $mark, $t.Label, $t.SizeMB, $inst)
        }
        $cur = 0
        foreach ($k in $sel.Keys) { if ($sel[$k]) { $cur += ($Tools | Where-Object Name -eq $k).SizeMB } }
        Write-Host ("   selected total: {0} MB" -f $cur) -ForegroundColor Cyan
        Write-Host ""
    }
    return ($sel.Keys | Where-Object { $sel[$_] })
}

function Show-SpaceCheck {
    param([string[]] $Names)
    $need = 0
    foreach ($n in $Names) {
        $t = $Tools | Where-Object Name -eq $n
        if ($t) { $need += $t.SizeMB }
    }
    # downloads are staged on the same drive, so allow roughly double
    $needWithStaging = [int]($need * 1.4) + 2048

    $rootPath = if ($Root.Length -ge 2) { $Root.Substring(0, 2) } else { $Root }
    $drive = $rootPath.TrimEnd('\')
    $freeGB = 0
    try {
        $psd = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop
        $freeGB = [int]($psd.Free / 1GB)
    } catch { }

    Write-Host ""
    Write-Host ("  Selected : {0} tool(s), about {1} MB installed" -f $Names.Count, $need)
    Write-Host ("  Needs    : about {0} MB free (includes download staging)" -f $needWithStaging)
    Write-Host ("  Free on {0,-6} : {1} GB" -f $drive, $freeGB)

    if ($freeGB -gt 0 -and ($freeGB * 1024) -lt $needWithStaging) {
        Write-Host ""
        Write-Err2 "Not enough free space on ${drive}:."
        Write-Host "       Need about $([int]($needWithStaging/1024)) GB, have $freeGB GB."
        Write-Host "       Remove some tools from the selection and try again."
        return $false
    }
    Write-Host ""
    return $true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if ($List) { Show-Catalogue; exit 0 }

$seven = Find-7z
if (-not $seven) {
    Write-Err2 "7-Zip is required to unpack the tool archives."
    Write-Host "       Install it from https://www.7-zip.org and re-run."
    exit 1
}

# ---- decide the selection -------------------------------------------------
$selected = @()

if ($Minimal) {
    $selected = @('opencode')
}
elseif ($All) {
    $selected = @($Tools | ForEach-Object { $_.Name })
}
elseif ($Only) {
    $wanted = $Only -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    $bad = $wanted | Where-Object { $_ -notin $Tools.Name }
    if ($bad) { Write-Err2 "Unknown tool(s): $($bad -join ', ')"; exit 1 }
    $selected = @($wanted)
}
else {
    $selected = Select-Tools
}

if (@($selected).Count -eq 0) {
    Write-Host "`n  Nothing selected. Exiting.`n"
    exit 0
}

# OpenCode itself is the point of the bundle - always include it, unless the
# caller is a tool-only flow (Manage-Tools updates toolchains while leaving the
# app to bin\Update-OpenCode.ps1).
if ('opencode' -notin $selected -and -not $NoOpenCode) {
    Write-Warn2 "adding OpenCode itself to the selection"
    $selected = @('opencode') + $selected
}

# android needs a JDK to run sdkmanager
if ('android' -in $selected -and 'jdk' -notin $selected -and -not (Test-ToolInstalled 'jdk')) {
    Write-Warn2 "Android SDK requires the JDK - adding it"
    $selected = $selected + 'jdk'
}

# ---- space check ----------------------------------------------------------
if (-not (Show-SpaceCheck -Names $selected)) { exit 1 }

# ---- skip already installed ----------------------------------------------
if (-not $Force) {
    $already = @($selected | Where-Object { Test-ToolInstalled $_ })
    if ($already) {
        foreach ($a in $already) {
            Write-Warn2 "$a already installed - skipping (use -Force to reinstall)"
        }
        $selected = @($selected | Where-Object { $_ -notin $already })
    }
}
if (@($selected).Count -eq 0) {
    Write-Host "`n  Nothing to do - everything selected is already installed.`n"
    exit 0
}

# ---- resolve URLs ---------------------------------------------------------
Write-Step "Resolving download URLs"
$urls = @{}
foreach ($n in $selected) {
    try {
        $u = Resolve-Url -Name $n
        if (-not $u) { throw "could not resolve a download URL" }
        $urls[$n] = $u
        Write-Ok ("{0,-9} {1}" -f $n, $u)
    } catch {
        Write-Err2 "$n : $($_.Exception.Message)"
        $urls[$n] = $null
    }
}

# ---- download in parallel -------------------------------------------------
$downloadable = @($selected | Where-Object { $urls[$_] })
Write-Step "Downloading $($downloadable.Count) item(s) in parallel"

$progDir = Join-Path $UnpackDir '_dlprogress'
New-Item -ItemType Directory -Force -Path $progDir | Out-Null

$destFor = @{}
$jobs = @(foreach ($n in $downloadable) {
    $dest = Join-Path $DlDir (Get-ArchiveName -Name $n -Url $urls[$n])
    $destFor[$n] = $dest
    $totalFile = Join-Path $progDir "$n.total"
    Start-Job -Name $n -ArgumentList $urls[$n], $dest, $totalFile -ScriptBlock {
        param($u, $d, $totalFile)
        $ProgressPreference = 'SilentlyContinue'
        # Remember the expected size first so the parent can draw a real
        # percentage while the parallel downloads are still running.
        $total = 0
        try {
            $head = [System.Net.HttpWebRequest]::Create($u)
            $head.Method = 'HEAD'
            $head.Timeout = 30000
            $head.AllowAutoRedirect = $true
            $head.UserAgent = 'OpenCode-Portable'
            $resp = $head.GetResponse()
            if ($resp.ContentLength -gt 0) { $total = $resp.ContentLength }
            $resp.Close()
        } catch { $total = 0 }
        try { [System.IO.File]::WriteAllText($totalFile, [string]$total) } catch { }

        try {
            Invoke-WebRequest -Uri $u -OutFile $d -UseBasicParsing -TimeoutSec 3600
            "OK"
        } catch {
            "FAIL $($_.Exception.Message)"
        }
    }
})

$downloadOk = @{}
$announced  = @{}
$milestone  = -10

if ($downloadable.Count -gt 0) {
    $tick = 0
    while ($true) {
        # Collect finished jobs as soon as they exit, not after everything ends.
        foreach ($j in @($jobs | Where-Object { $_.State -ne 'Running' -and -not $announced.ContainsKey($_.Name) })) {
            $r = Receive-Job -Job $j -Wait -AutoRemoveJob 2>$null
            if ("$r" -match '^OK') {
                $downloadOk[$j.Name] = $true
                Write-Ok "$($j.Name) downloaded"
            } else {
                $downloadOk[$j.Name] = $false
                Write-Err2 "$($j.Name) download failed : $r"
            }
            $announced[$j.Name] = $true
        }

        $running = @($jobs | Where-Object { $_.State -eq 'Running' })
        if ($running.Count -eq 0) { break }

        $doneBytes  = 0
        $totalBytes = 0
        $unknown    = $false
        foreach ($n in $downloadable) {
            $p = $destFor[$n]
            if (Test-Path -LiteralPath $p) { $doneBytes += (Get-Item -LiteralPath $p).Length }
            $tf = Join-Path $progDir "$n.total"
            $t = 0
            if (Test-Path -LiteralPath $tf) {
                try { $t = [int64](Get-Content -LiteralPath $tf -Raw -ErrorAction Stop).Trim() } catch { $t = 0 }
            }
            if ($t -gt 0) { $totalBytes += $t } else { $unknown = $true }
        }

        $pct = -1
        if (-not $unknown -and $totalBytes -gt 0) {
            $pct = [int]([Math]::Min(100, ($doneBytes * 100 / $totalBytes)))
        }
        $status = "{0}/{1} files, {2}" -f $announced.Count, $downloadable.Count, (Format-Bytes $doneBytes)
        if ($pct -ge 0) { $status += " of $(Format-Bytes $totalBytes) ($pct%)" }
        Show-PhaseProgress -Activity 'Downloading tools' -Status $status -Percent $pct -Id 1
        if ($pct -ge 0 -and ($pct - $milestone) -ge 5) {
            Write-TextProgress "downloading $pct%  $status"
            $milestone = $pct
        }
        $tick++
        if ($tick -le 25) { Start-Sleep -Milliseconds 150 } else { Start-Sleep -Milliseconds 400 }
    }

    # Anything still unannounced (failed to start, for example).
    foreach ($j in @($jobs | Where-Object { -not $announced.ContainsKey($_.Name) })) {
        $r = Receive-Job -Job $j -Wait -AutoRemoveJob 2>$null
        if ("$r" -match '^OK') { $downloadOk[$j.Name] = $true; Write-Ok "$($j.Name) downloaded" }
        else { $downloadOk[$j.Name] = $false; Write-Err2 "$($j.Name) download failed : $r" }
        $announced[$j.Name] = $true
    }
    Write-Progress -Id 1 -Activity 'Downloading tools' -Completed
}

# ---- install --------------------------------------------------------------
Write-Step "Installing"
$installers = @{
    'opencode' = { param($a) Install-OpenCode $a }
    'vscode'   = { param($a) Install-Vscode   $a }
    'jdk'      = { param($a) Install-Jdk      $a }
    'go'       = { param($a) Install-Go       $a }
    'node'     = { param($a) Install-Node     $a }
    'maven'    = { param($a) Install-Maven    $a }
    'git'      = { param($a) Install-Git      $a }
    'dotnet'   = { param($a) Install-Dotnet   $a }
    'python'   = { param($a) Install-Python   $a }
    'rust'     = { param($a) Install-Rust     $a }
    'android'  = { param($a) Install-Android  $a }
}

$succeeded = @()
$failed    = @()

$toolCount = @($selected).Count
for ($idx = 0; $idx -lt $toolCount; $idx++) {
    $n = $selected[$idx]
    if (-not $downloadOk.ContainsKey($n) -or -not $downloadOk[$n]) {
        $failed = @($failed) + $n
        continue
    }
    # Give this tool a slice of the install bar: base..base+span.
    $script:InstallBase = [int](100 * $idx / $toolCount)
    $script:InstallSpan = [int](100 * ($idx + 1) / $toolCount) - $script:InstallBase
    $script:ProgressLabel = $n
    Show-PhaseProgress -Activity 'Installing tools' `
        -Status ("{0} ({1}/{2})  {3}%" -f $n, ($idx + 1), $toolCount, $script:InstallBase) `
        -Percent $script:InstallBase -Id 2
    Write-TextProgress ("installing {0} ({1}/{2}, {3}%)" -f $n, ($idx + 1), $toolCount, $script:InstallBase)

    $archive = Join-Path $DlDir (Get-ArchiveName -Name $n -Url $urls[$n])
    try {
        & $installers[$n] $archive
        $succeeded = @($succeeded) + $n
    } catch {
        Write-Err2 "$n : $($_.Exception.Message)"
        $failed = @($failed) + $n
    }
}
Write-Progress -Id 2 -Activity 'Installing tools' -Completed

# ---- cleanup staging ------------------------------------------------------
if (Test-Path $UnpackDir) {
    Remove-Item $UnpackDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- summary --------------------------------------------------------------
Write-Step "Summary"
# NOTE: do not name this $all - that collides with the -All switch parameter
# (PowerShell variable names are case-insensitive).
$allTools = @($succeeded) + @($failed)
foreach ($n in $allTools) {
    $t = $Tools | Where-Object Name -eq $n
    if ($n -in $succeeded) { Write-Host ("    installed  {0,-10} {1,-26} {2,6} MB" -f $n, $t.Label, $t.SizeMB) -ForegroundColor Green }
    else                  { Write-Host ("    FAILED     {0,-10} {1,-26}" -f $n, $t.Label) -ForegroundColor Red }
}

$totalMB = 0
if ($succeeded.Count -gt 0) {
    $totalMB = ($Tools | Where-Object { $_.Name -in $succeeded } | Measure-Object SizeMB -Sum).Sum
    if ($null -eq $totalMB) { $totalMB = 0 }
}
Write-Host ""
Write-Host ("    {0} installed, {1} failed, about {2} MB on disk" -f $succeeded.Count, $failed.Count, $totalMB) -ForegroundColor Cyan
Write-Host ""

if ($succeeded.Count -gt 0) {
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "    1. Run bin\Verify.cmd to confirm every path is isolated."
    Write-Host "    2. Run Launch.cmd to start OpenCode."
    Write-Host ""
    Write-Host "  Note: bin\env.cmd builds PATH at launch time, so newly installed"
    Write-Host "        tools are picked up automatically - no edit needed."
    Write-Host ""
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
