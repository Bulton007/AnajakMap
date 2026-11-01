@echo off
setlocal
title AnajakMap - Recover Existing Backend Configuration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\recover-env.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
