@echo off
rem ============================================================================
rem  OpenCode Portable - environment
rem  Included by the launchers. Redirects EVERY path to the USB drive so that
rem  nothing is written to the host PC and everything follows the stick.
rem ============================================================================

rem --- resolve portable root (parent of bin\) ---
for %%I in ("%~dp0..") do set "PORTABLE_ROOT=%%~fI"
set "PORTABLE_ROOT=%PORTABLE_ROOT:"=%"

rem --- OpenCode session data: THE portable part ---
set "XDG_DATA_HOME=%PORTABLE_ROOT%\data\opencode-data"
set "XDG_CONFIG_HOME=%PORTABLE_ROOT%\data\opencode-config"
set "XDG_CACHE_HOME=%PORTABLE_ROOT%\data\opencode-cache"
set "XDG_STATE_HOME=%PORTABLE_ROOT%\data\opencode-state"
set "OPENCODE_CONFIG_DIR=%XDG_CONFIG_HOME%\opencode"
rem never let the app self-update in place (it would rewrite the USB copy)
set "OPENCODE_DISABLE_AUTOUPDATE=1"

rem --- isolate user profile writes (Electron, git, npm, ...) ---
set "APPDATA=%PORTABLE_ROOT%\data\appdata\Roaming"
set "LOCALAPPDATA=%PORTABLE_ROOT%\data\appdata\Local"
set "USERPROFILE=%PORTABLE_ROOT%\data\home"
set "HOME=%PORTABLE_ROOT%\data\home"
set "TEMP=%PORTABLE_ROOT%\data\tmp"
set "TMP=%PORTABLE_ROOT%\data\tmp"

rem --- toolchains ---
if exist "%PORTABLE_ROOT%\apps\jdk" (
  rem the JDK root is the folder that actually contains bin\java.exe
  for /d %%D in ("%PORTABLE_ROOT%\apps\jdk") do (
    if exist "%%~fD\bin\java.exe" set "JAVA_HOME=%%~fD"
  )
)
if exist "%PORTABLE_ROOT%\apps\android-sdk" (
  set "ANDROID_HOME=%PORTABLE_ROOT%\apps\android-sdk"
  set "ANDROID_SDK_ROOT=%PORTABLE_ROOT%\apps\android-sdk"
)
if exist "%PORTABLE_ROOT%\apps\go" set "GOROOT=%PORTABLE_ROOT%\apps\go"
set "GOPATH=%PORTABLE_ROOT%\data\gopath"
set "GOCACHE=%PORTABLE_ROOT%\data\gocache"
set "MAVEN_HOME=%PORTABLE_ROOT%\apps\maven"
set "GRADLE_USER_HOME=%PORTABLE_ROOT%\data\gradle"
set "npm_config_cache=%PORTABLE_ROOT%\data\npm-cache"
set "PIP_CACHE_DIR=%PORTABLE_ROOT%\data\pip-cache"
if exist "%PORTABLE_ROOT%\apps\dotnet" set "DOTNET_ROOT=%PORTABLE_ROOT%\apps\dotnet"
if exist "%PORTABLE_ROOT%\data\cargo\bin" set "CARGO_HOME=%PORTABLE_ROOT%\data\cargo"
if exist "%PORTABLE_ROOT%\data\rustup" set "RUSTUP_HOME=%PORTABLE_ROOT%\data\rustup"

rem --- build the PATH: portable tools first, then whatever the host had ---
set "_PORTABLE_PATH=%PORTABLE_ROOT%\apps\opencode\resources"
if exist "%PORTABLE_ROOT%\apps\jdk\bin" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%JAVA_HOME%\bin"
if exist "%PORTABLE_ROOT%\apps\android-sdk\cmdline-tools" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools"
if exist "%PORTABLE_ROOT%\apps\go\bin" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%GOROOT%\bin;%GOPATH%\bin"
if exist "%PORTABLE_ROOT%\apps\maven\bin" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%MAVEN_HOME%\bin"
if exist "%PORTABLE_ROOT%\apps\node" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%PORTABLE_ROOT%\apps\node"
if exist "%PORTABLE_ROOT%\apps\python" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%PORTABLE_ROOT%\apps\python;%PORTABLE_ROOT%\apps\python\Scripts"
if exist "%PORTABLE_ROOT%\apps\dotnet" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%DOTNET_ROOT%"
if exist "%PORTABLE_ROOT%\data\cargo\bin" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%CARGO_HOME%\bin"
if exist "%PORTABLE_ROOT%\apps\git" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%PORTABLE_ROOT%\apps\git\cmd;%PORTABLE_ROOT%\apps\git\bin"
if exist "%PORTABLE_ROOT%\apps\vim" set "_PORTABLE_PATH=%_PORTABLE_PATH%;%PORTABLE_ROOT%\apps\vim"
set "PATH=%_PORTABLE_PATH%;%PORTABLE_ROOT%\bin;%PATH%"

rem --- make the dirs that some tools assume already exist ---
for %%D in (
  "%APPDATA%" "%LOCALAPPDATA%" "%TEMP%" "%GOPATH%" "%GOCACHE%"
  "%GRADLE_USER_HOME%" "%npm_config_cache%" "%PIP_CACHE_DIR%"
  "%XDG_CACHE_HOME%" "%XDG_STATE_HOME%" "%PORTABLE_ROOT%\projects"
) do if not exist %%D mkdir %%D >nul 2>&1
