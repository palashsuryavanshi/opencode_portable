@echo off
rem ============================================================================
rem  Android SDK manager / ADB, running entirely from the stick.
rem  Keep redirection and operator characters out of echoed text, because
rem  cmd interprets them even inside a plain echo.
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title Android Portable

set "SDK=%ANDROID_HOME%"
set "SDKM=%SDK%\cmdline-tools\latest\bin\sdkmanager.bat"

if not exist "%SDKM%" goto :nosdk
if "%~1"=="" goto :help

rem --- forward arguments to sdkmanager ---
rem Redirect stdin from NUL: the SDK tool blocks waiting on stdin when it
rem inherits a console, which otherwise looks like a hang to the user.
"%SDKM%" --sdk_root="%SDK%" %* <NUL
exit /b %errorlevel%

:nosdk
echo.
echo [!] Android command-line tools not found:
echo       %SDKM%
echo.
echo     Re-run:  build\setup-android.ps1
echo.
pause
exit /b 1

:help
echo.
echo   Android SDK root : %SDK%
echo   Java            : %JAVA_HOME%
echo.
echo   Examples:
echo     Android.cmd --list
echo     Android.cmd --list_installed
echo     Android.cmd build-tools/36.0.0
echo     Android.cmd platforms/android-36
echo     Android.cmd --uninstall platforms/android-34
echo.
echo   ADB - connect a phone with USB debugging enabled:
echo     adb devices
echo     adb install [path to app.apk]
echo.
"%SDKM%" --sdk_root="%SDK%" --list_installed <NUL
echo.
pause
exit /b 0