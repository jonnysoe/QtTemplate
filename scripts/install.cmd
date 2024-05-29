@echo off

:: CD to script directory so that this can be call from anywhere
set SCRIPT_PATH=%~dp0
pushd %SCRIPT_PATH%

:: Passthrough to PowerShell
powershell -File install.ps1
set SCRIPT_ERROR=%ERRORLEVEL%

:: exit
popd
exit /b %SCRIPT_ERROR%