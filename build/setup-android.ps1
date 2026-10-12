<#
  OpenCode Portable - Android SDK setup
  Installs the Android SDK entirely inside the portable folder.
  sdkmanager is a normal Java program, so it honours the portable JAVA_HOME
  and writes only under ANDROID_SDK_ROOT.
#>
param(
  [string]$Root = "D:\VIBECODINGPROJECTS\OpenCode Portable",
  [switch]$WithStudio
)
$ErrorActionPreference = 'Continue'

$jdk    = Join-Path $Root 'apps\jdk'
$sdk    = Join-Path $Root 'apps\android-sdk'
$sdkm   = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$env:JAVA_HOME = $jdk
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "$jdk\bin;$sdk\cmdline-tools\latest\bin;$sdk\platform-tools;$env:PATH"

if (-not (Test-Path $sdkm)) { "ERROR: sdkmanager not found at $sdkm"; exit 1 }

"== accepting SDK licences =="
# The current cmdline-tools delegate to the new `android` CLI, which no longer
# needs --licenses (the licence files are written on first install instead).
# Kept for older cmdline-tools revisions that still require it.
1..40 | ForEach-Object { 'y' } | & $sdkm --sdk_root="$sdk" --licenses 2>&1 |
  Select-Object -Last 2

# NOTE: this Android CLI takes sdk-style paths with FORWARD SLASHES
# ("build-tools/35.0.0"), not the old semicolon form ("build-tools;35.0.0").
$packages = @(
  'build-tools/35.0.0',
  'platforms/android-35',
  'build-tools/34.0.0',
  'platforms/android-34'
)

"== installing packages: $($packages -join ', ') =="
foreach ($p in $packages) {
  "-> $p"
  & $sdkm --sdk_root="$sdk" $p 2>&1 | Select-Object -Last 2
}

if ($WithStudio) {
  "== downloading Android Studio (optional, NOT guaranteed portable) =="
  $zip = Join-Path $Root 'downloads\androidstudio.zip'
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri 'https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2025.1.1.14/android-studio-2025.1.1.14-windows.exe' -OutFile $zip -UseBasicParsing -TimeoutSec 3600
    "downloaded $((Get-Item $zip).Length / 1MB) MB"
  } catch {
    "studio download skipped: $($_.Exception.Message)"
  }
}

"== done =="
Get-ChildItem $sdk -Directory | Select-Object -ExpandProperty Name
