@echo off
rem ============================================================================
rem  OpenCode Portable - tool manager
rem  Add or remove toolchains (VS Code, Python, Android SDK, ...) without
rem  touching data\ (sessions) or projects\.
rem
rem  Usage:
rem    Manage-Tools.cmd                      interactive menu
rem    Manage-Tools.cmd -List                show what is installed
rem    Manage-Tools.cmd -Add "python,go"     install tools
rem    Manage-Tools.cmd -Remove "vscode"     remove a tool
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title Manage Tools

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-Tools.ps1" %*
set "RC=%ERRORLEVEL%"

rem Keep the window open for the interactive menu, stay quiet for scripted use.
if "%~1"=="" pause
exit /b %RC%
