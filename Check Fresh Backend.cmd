@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Check Fresh Backend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\frontend-contract-smoke.ps1" -BaseUrl "http://127.0.0.1:18090/api/v1/"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
