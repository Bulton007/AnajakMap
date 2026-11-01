@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Check Fresh AI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\check-ai.ps1" -ProjectName "anajakmap-v12"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
