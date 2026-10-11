@echo off
call bin\env.cmd
call :test XDG_DATA_HOME "%XDG_DATA_HOME%"
exit /b 0

:test
set "ARG=%~2"
echo arg1=%1
echo arg2=%ARG%
echo sub=%ARG:~0,2%
if /i "%ARG:~0,2%"=="%PORTABLE_ROOT:~0,2%" (echo match) else (echo nomatch)
exit /b 0