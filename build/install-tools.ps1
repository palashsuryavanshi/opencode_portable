<#
  OpenCode Portable - tool installer
  Unpacks the downloaded archives into apps\ using the layout each tool
  expects when it is run "in place" rather than installed.
#>
param(
  [string]$Root = "D:\VIBECODINGPROJECTS\OpenCode Portable"
)
$ErrorActionPreference = 'Stop'
$dl   = Join-Path $Root 'downloads'
$apps = Join-Path $Root 'apps'
$tmp  = Join-Path $Root 'downloads\_unpack'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Prefer the 7-Zip bundled inside the portable (apps\7zip\7za.exe) so that no
# 7-Zip installation is required on the host.
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
$SevenZip = Resolve-7z
if (-not $SevenZip) { Write-Error 'No 7-Zip found (expected apps\7zip\7za.exe).'; exit 1 }

function Expand-To($zip, $dest, $strip = $false) {
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  if ($strip) {
    $stage = Join-Path $tmp ([guid]::NewGuid().ToString('N'))
    & $SevenZip x $zip "-o$stage" -y | Out-Null
    $child = Get-ChildItem $stage -Directory | Select-Object -First 1
    robocopy $child.FullName $dest /E /NFL /NDL /NJH /NJS /NP | Out-Null
    Remove-Item $stage -Recurse -Force
  } else {
    & $SevenZip x $zip "-o$dest" -y | Out-Null
  }
  "  installed -> $dest"
}

"Installing tools into $apps ..."

# VS Code: the ZIP ("archive") edition already supports portable mode.
# A 'data' folder next to Code.exe makes settings + extensions stick to the stick.
Expand-To (Join-Path $dl 'vscode.zip') (Join-Path $apps 'vscode') $false
New-Item -ItemType Directory -Force -Path (Join-Path $apps 'vscode\data') | Out-Null

# Temurin JDK 21: strip the jdk-21.x.y+1 wrapper folder
Expand-To (Join-Path $dl 'jdk.zip') (Join-Path $apps 'jdk') $true

# Go: strip the 'go' folder
Expand-To (Join-Path $dl 'go.zip') (Join-Path $apps 'go') $true

# Node: strip the node-vXX-win-x64 folder
Expand-To (Join-Path $dl 'node.zip') (Join-Path $apps 'node') $true

# Maven: strip the apache-maven-X.Y.Z folder
Expand-To (Join-Path $dl 'maven.zip') (Join-Path $apps 'maven') $true

# Git for Windows PortableGit is a self-extracting 7z archive whose payload is
# already flat (bin\, cmd\, etc\, mingw64\ at the root), so do NOT strip a wrapper.
Expand-To (Join-Path $dl 'portablegit.exe') (Join-Path $apps 'git') $false

# Android command-line tools must end up at cmdline-tools\latest\bin
$stage = Join-Path $tmp 'androidcmd'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
& $SevenZip x (Join-Path $dl 'androidcmd.zip') "-o$stage" -y | Out-Null
$sdk = Join-Path $apps 'android-sdk'
Remove-Item (Join-Path $sdk 'cmdline-tools') -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
Move-Item (Join-Path $stage 'cmdline-tools') (Join-Path $sdk 'cmdline-tools\latest')
Remove-Item $stage -Recurse -Force
"  installed -> $sdk\cmdline-tools\latest"

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
"INSTALL DONE"
