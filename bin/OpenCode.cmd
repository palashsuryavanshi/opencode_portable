@echo off
rem ============================================================================
rem  OpenCode Portable - main launcher
rem  Double-click this (or Launch.cmd at the USB root) to start the GUI.
rem ============================================================================
setlocal
call "%~dp0bin\env.cmd"
title OpenCode Portable

rem Make sure we are running from the stick, not a copy left behind.
if /i not "%~d0"=="%PORTABLE_ROOT%" (
  echo [!] Launch from the USB root, not from bin\.
)

rem Electron writes its profile (window size, state) to %APPDATA%\opencode-desktop.
rem Keep that on the stick too so the GUI feels identical on every machine.
start "" "%PORTABLE_ROOT%\apps\opencode\OpenCode.exe" %*
exit /b 0
