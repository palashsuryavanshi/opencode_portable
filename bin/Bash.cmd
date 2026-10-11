@echo off
rem ============================================================================
rem  Git Bash - a real Unix-like shell (satisfies the "linux dev tools" need
rem  without WSL, which cannot be made portable).
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title Portable Bash

set "BASH=%PORTABLE_ROOT%\apps\git\bin\bash.exe"
if not exist "%BASH%" (
  echo [!] Git Bash not found at %BASH%
  pause
  exit /b 1
)

if "%~1"=="" (
  "%BASH%" --login -i -c "cd '%PORTABLE_ROOT%/projects' 2>/dev/null || cd ~; exec bash --login -i"
) else (
  "%BASH%" -lc "%*"
)
