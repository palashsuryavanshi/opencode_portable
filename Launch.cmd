@echo off
setlocal EnableDelayedExpansion
title OpenCode Portable

for %%I in ("%~dp0") do set "ROOT=%%~fI"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:menu
cls
echo.
echo  ================================================================
echo     OpenCode Portable   -   %ROOT:~-28%
echo  ================================================================
echo.
echo    1.  OpenCode GUI          <- the main app, sessions included
echo    2.  VS Code               <- portable, settings on the stick
echo    3.  Developer Shell       <- cmd with all toolchains on PATH
echo    4.  Bash Shell            <- Git Bash (Unix-like)
echo    5.  OpenCode CLI (TUI)    <- terminal client, same sessions
echo    6.  Android SDK Manager
echo    7.  Sessions: backup / restore / list
echo    8.  Verify portable setup
echo    9.  Update OpenCode       <- download & install latest stable
echo    0.  Exit
echo.
set "CHOICE="
set /p "CHOICE=  Choose: "

if "%CHOICE%"=="1" ( call "%ROOT%bin\OpenCode.cmd" & exit /b 0 )
if "%CHOICE%"=="2" ( call "%ROOT%bin\VSCode.cmd"  & exit /b 0 )
if "%CHOICE%"=="3" ( call "%ROOT%bin\Shell.cmd"    & exit /b 0 )
if "%CHOICE%"=="4" ( call "%ROOT%bin\Bash.cmd"     & exit /b 0 )
if "%CHOICE%"=="5" ( call "%ROOT%bin\OpenCodeCLI.cmd" & exit /b 0 )
if "%CHOICE%"=="6" ( call "%ROOT%bin\Android.cmd"  & exit /b 0 )
if "%CHOICE%"=="7" ( call "%ROOT%bin\Sync.cmd"     & goto menu )
if "%CHOICE%"=="8" ( call "%ROOT%bin\Verify.cmd"   & pause & goto menu )
if "%CHOICE%"=="9" ( call "%ROOT%bin\Update-OpenCode.cmd" & goto menu )
if "%CHOICE%"=="0" exit /b 0

echo   Invalid choice.
timeout /t 1 >nul
goto menu
