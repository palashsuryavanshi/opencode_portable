@echo off
rem ============================================================================
rem  Android SDK manager / ADB, running entirely from the stick.
rem ============================================================================
setlocal
call "%~dp0env.cmd"
title Android Portable

set "SDK=%ANDROID_HOME%"
set "SDKM=%SDK%\cmdline-tools\latest\bin\sdkmanager.bat"

if not exist "%SDKM%" (
  echo [!] Android command-line tools not found at %SDKM%
  echo     Re-run:  build\setup-android.ps1
  pause
  exit /b 1
)

if "%~1"=="" (
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
  echo   ADB (connect a phone with USB debugging on):
  echo     adb devices
  echo     adb install path\to\app.apk
  echo.
  "%SDKM%" --sdk_root="%SDK%" --list_installed
  pause
) else (
  "%SDKM%" --sdk_root="%SDK%" %*
)
