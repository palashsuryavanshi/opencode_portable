@echo off
setlocal
call "%~dp0env.cmd"
title Sessions

for %%I in ("%~dp0") do set "HERE=%%~fI"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if "%~1"=="" set "ACTION=list"

echo.
echo  ================================================================
echo   OpenCode sessions - %ACTION%
echo  ================================================================
echo.
echo   1. backup    - snapshot current sessions to data\backups
echo   2. restore   - load the newest snapshot back
echo   3. list      - show snapshots
echo   4. import    - pull sessions from THIS PC's OpenCode install
echo.
set /p "PICK=  Choose (or type an action): "
if "%PICK%"=="" set "PICK=%ACTION%"
if /i "%PICK%"=="1" set "ACTION=backup"
if /i "%PICK%"=="2" set "ACTION=restore"
if /i "%PICK%"=="3" set "ACTION=list"
if /i "%PICK%"=="4" set "ACTION=import-host"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%HERE%sync-sessions.ps1" -Action "%ACTION%"
echo.
pause
