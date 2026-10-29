@echo off
setlocal EnableDelayedExpansion
title OpenCode Portable

for %%I in ("%~dp0") do set "ROOT=%%~fI"

:menu
cls
echo.
echo  ================================================================
echo     OpenCode Portable   -   %ROOT%
echo  ================================================================
echo.
echo    1.  OpenCode GUI           --  main app, sessions included
echo    2.  OpenCode CLI (TUI)     --  terminal client, same sessions
echo    3.  Sessions               --  backup / restore / list / import
echo    4.  Verify portable setup
echo    5.  Update OpenCode        --  latest app + refresh every toolchain
echo    6.  Update tools           --  re-download installed toolchains
echo    7.  Manage tools           --  install / remove / launch toolchains
echo    0.  Exit
echo.
set "CHOICE="
set /p "CHOICE=  Choose: " || exit /b 0

rem Normalise the input: strip stray quotes and whitespace so that both
rem typed input and piped input (echo 1) work.
set "CHOICE=%CHOICE:"=%"
set "CHOICE=%CHOICE: =%"

if not defined CHOICE goto menu

if not exist "%ROOT%bin\OpenCode.cmd" (
  echo.
  echo   [!] Launchers not found in "%ROOT%bin".
  echo       Run this from the USB root, not from a subfolder.
  pause
  exit /b 1
)

if "%CHOICE%"=="1" ( call "%ROOT%bin\OpenCode.cmd"    & exit /b 0 )
if "%CHOICE%"=="2" ( call "%ROOT%bin\OpenCodeCLI.cmd" & exit /b 0 )
if "%CHOICE%"=="3" ( call "%ROOT%bin\Sync.cmd"        & goto menu )
if "%CHOICE%"=="4" ( call "%ROOT%bin\Verify.cmd"      & pause & goto menu )
if "%CHOICE%"=="5" ( call "%ROOT%bin\Update-OpenCode.cmd" -UpdateTools & goto menu )
if "%CHOICE%"=="6" ( call "%ROOT%bin\Manage-Tools.cmd" -Update & goto menu )
if "%CHOICE%"=="7" ( call "%ROOT%bin\Manage-Tools.cmd" & goto menu )
if "%CHOICE%"=="0" exit /b 0

echo   Invalid choice.
timeout /t 1 >nul
goto menu