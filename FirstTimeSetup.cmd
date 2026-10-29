@echo off
setlocal
title OpenCode Portable - First-time setup (Windows only)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FirstTimeSetup.ps1" %*
pause