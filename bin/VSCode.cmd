@echo off
rem ============================================================================
rem  VS Code (portable ZIP edition)
rem  The ZIP build keeps settings/extensions in a 'data' folder next to Code.exe,
rem  so we point --user-data-dir and --extensions-dir at the stick explicitly.
rem  That keeps your themes, keybinds and installed extensions on the USB.
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title VS Code Portable

set "VSCODE_EXE=%PORTABLE_ROOT%\apps\vscode\Code.exe"
if not exist "%VSCODE_EXE%" (
  echo [!] VS Code not found at %VSCODE_EXE%
  pause
  exit /b 1
)

if not exist "%PORTABLE_ROOT%\data\vscode-user" mkdir "%PORTABLE_ROOT%\data\vscode-user" >nul 2>&1
if not exist "%PORTABLE_ROOT%\data\vscode-extensions" mkdir "%PORTABLE_ROOT%\data\vscode-extensions" >nul 2>&1

if "%~1"=="" (
  start "" "%VSCODE_EXE%" ^
    --user-data-dir="%PORTABLE_ROOT%\data\vscode-user" ^
    --extensions-dir="%PORTABLE_ROOT%\data\vscode-extensions" ^
    "%PORTABLE_ROOT%\projects"
) else (
  start "" "%VSCODE_EXE%" ^
    --user-data-dir="%PORTABLE_ROOT%\data\vscode-user" ^
    --extensions-dir="%PORTABLE_ROOT%\data\vscode-extensions" ^
    %*
)
exit /b 0
