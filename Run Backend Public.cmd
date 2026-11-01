@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Run Backend Public
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\run-ready-backend.ps1" -Public
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
