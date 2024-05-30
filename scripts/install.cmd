@echo off

:: Call with script directory so that this can be call from anywhere
:: NOTE: %~dp0 ends with directory separator
set SCRIPT_PATH=%~dp0

:: Passthrough to PowerShell
powershell -File %SCRIPT_PATH%install.ps1

:: exit
exit /b %ERRORLEVEL%