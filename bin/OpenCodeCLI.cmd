@echo off
rem ============================================================================
rem  OpenCode CLI (TUI) - same sessions as the GUI, because both point at
rem  XDG_DATA_HOME on the stick.
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title OpenCode CLI

set "CLI=%PORTABLE_ROOT%\apps\opencode\resources\opencode-cli.exe"
if not exist "%CLI%" (
  echo [!] opencode-cli not found at %CLI%
  pause
  exit /b 1
)

if "%~1"=="" (
  cd /d "%PORTABLE_ROOT%\projects"
  "%CLI%"
) else (
  "%CLI%" %*
)
