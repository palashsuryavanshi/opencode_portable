@echo off
rem ============================================================================
rem  OpenCode Portable - main launcher
rem  Starts the OpenCode GUI. Called from Launch.cmd (option 1) or directly.
rem ============================================================================
setlocal
rem %~dp0 is this script's folder (...\bin\), so env.cmd sits next to us.
call "%~dp0env.cmd"
title OpenCode Portable

if not defined PORTABLE_ROOT (
  echo [!] env.cmd failed to load - cannot resolve the portable root.
  pause
  exit /b 1
)

set "OPENCODE_EXE=%PORTABLE_ROOT%\apps\opencode\OpenCode.exe"

if not exist "%OPENCODE_EXE%" (
  echo.
  echo [!] OpenCode GUI not found at:
  echo       %OPENCODE_EXE%
  echo.
  echo     On a fresh copy, install the app first:
  echo       bin\Update-OpenCode.cmd
  echo     or from Launch.cmd choose option 9.
  echo.
  pause
  exit /b 1
)

start "" "%OPENCODE_EXE%" %*
exit /b 0