@echo off
rem ============================================================================
rem  Verify the portable install: every path must point at the stick, and the
rem  session database must be present. Run this on any new machine first.
rem ============================================================================
setlocal EnableDelayedExpansion
call "%~dp0env.cmd"
title Verify Portable

echo.
echo  ================================================================
echo   OpenCode Portable - verification
echo   root: %PORTABLE_ROOT%
echo  ================================================================
echo.

set "FAIL=0"
set "ROOTDRIVE=%PORTABLE_ROOT:~0,2%"

echo  [1] path isolation
call :isolate XDG_DATA_HOME   "%XDG_DATA_HOME%"
call :isolate XDG_CONFIG_HOME "%XDG_CONFIG_HOME%"
call :isolate XDG_CACHE_HOME  "%XDG_CACHE_HOME%"
call :isolate APPDATA         "%APPDATA%"
echo.

echo  [2] chat sessions
if exist "%XDG_DATA_HOME%\opencode\opencode.db" (
  set "DBSIZE=0"
  for %%A in ("%XDG_DATA_HOME%\opencode\opencode.db") do set "DBSIZE=%%~zA"
  set /a DBSIZE=DBSIZE/1048576
  echo      ok   opencode.db  !DBSIZE! MB
) else (
  echo      info opencode.db not found - fresh install (sign in to create)
)
if exist "%XDG_CONFIG_HOME%\opencode\opencode.jsonc" (
  echo      ok   opencode.jsonc
) else (
  echo      warn no opencode.jsonc
)
if exist "%XDG_CONFIG_HOME%\opencode\auth.json" (
  for %%A in ("%XDG_CONFIG_HOME%\opencode\auth.json") do set "AUTHSIZE=%%~zA"
  if !AUTHSIZE! GTR 2 (
    echo      ok   auth.json - already signed in
  ) else (
    echo      ok   auth.json - empty (sign in on first run)
  )
  goto :auth_done
) else (
  echo      warn no auth.json
)
:auth_done
echo.

echo  [3] toolchains
call :tool java java.exe  required
call :tool node node.exe  required
call :tool go   go.exe    required
call :tool git  git.exe   required
call :tool mvn  mvn.cmd   optional
call :tool adb  adb.exe   optional
call :tool python python.exe  optional
call :tool pip  pip.bat   optional
call :tool dotnet dotnet.exe  optional
call :tool cargo cargo.exe  optional
call :tool rustc rustc.exe  optional
call :tool rustup rustup.exe  optional
if exist "%PORTABLE_ROOT%\apps\opencode\OpenCode.exe" (
  echo      ok   OpenCode GUI
) else (
  echo      FAIL OpenCode GUI missing
  set "FAIL=1"
)
echo.

echo  ================================================================
if "!FAIL!"=="0" (
  echo   RESULT: ready to use
) else (
  echo   RESULT: problems found - see FAIL above
)
echo  ================================================================
echo.
exit /b 0

rem ---------------------------------------------------------------------------
:isolate
set "ARG=%~2"
if /i "%ARG:~0,2%"=="%ROOTDRIVE%" (
  echo      ok   %~1 on the stick
) else (
  echo      FAIL %~1 points off the stick: %~2
  set "FAIL=1"
)
exit /b 0

:tool
where "%~2" >nul 2>&1
if %errorlevel%==0 (
  echo      ok   %~1
) else (
  if /i "%~3"=="required" (
    echo      miss %~1
    set "FAIL=1"
  ) else (
    echo      miss %~1 - optional
  )
)
exit /b 0