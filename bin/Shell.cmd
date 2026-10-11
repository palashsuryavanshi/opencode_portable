@echo off
rem ============================================================================
rem  Developer shell with every portable toolchain on PATH.
rem  Starts cmd.exe; pass /k to keep it open, or any command to run it once.
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title Portable Dev Shell

echo.
echo  ============================================================
echo   Portable Dev Shell
echo   root: %PORTABLE_ROOT%
echo  ============================================================
echo.

rem capture versions before the banner (no delayed expansion needed)
for /f "delims=" %%v in ('node -v 2^>nul') do set "node_version=%%v"
for /f "delims=" %%v in ('python --version 2^>nul') do set "py_version=%%v"
for /f "delims=" %%v in ('dotnet --version 2^>nul') do set "dotnet_version=%%v"
for /f "delims=" %%v in ('cargo --version 2^>nul') do set "cargo_version=%%v"

where java   >nul 2>&1 && echo   [ok] Java   : %JAVA_HOME%
where node   >nul 2>&1 && echo   [ok] Node   : %node_version%
where go     >nul 2>&1 && echo   [ok] Go     : %GOROOT%
where git    >nul 2>&1 && echo   [ok] Git    : PortableGit
where mvn    >nul 2>&1 && echo   [ok] Maven  : %MAVEN_HOME%
where python >nul 2>&1 && echo   [ok] Python : %py_version%
where dotnet >nul 2>&1 && echo   [ok] .NET    : %dotnet_version%
where cargo  >nul 2>&1 && echo   [ok] Rust     : %cargo_version%
where adb    >nul 2>&1 && echo   [ok] adb    : %ANDROID_HOME%
echo.
echo   opencode CLI : opencode-cli
echo   bash         : bash
echo.
echo   projects live in: %PORTABLE_ROOT%\projects
echo   opencode data : %XDG_DATA_HOME%
echo.
echo  ============================================================
echo.

cd /d "%PORTABLE_ROOT%\projects"

if "%~1"=="" (
  cmd /k
) else (
  %*
)
