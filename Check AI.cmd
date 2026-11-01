@echo off
setlocal
title AnajakMap - Check AI on this hosting PC
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\check-ai.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
