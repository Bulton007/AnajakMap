@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Fresh Version 12 Public Backend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\run-fresh-backend.ps1" -Public
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
