@echo off
rem ============================================================================
rem  OpenCode Portable - Updater wrapper (batch)
rem  Calls the PowerShell updater script.
rem ============================================================================
setlocal
for %%I in ("%~dp0..") do set "PORTABLE_ROOT=%%~fI"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

title Updating OpenCode Portable...

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\bin\Update-OpenCode.ps1" -PortableRoot "%PORTABLE_ROOT%" %*

echo.
pause