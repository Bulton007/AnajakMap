@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Update AI 2026.10.28.1
echo AnajakMap AI setup launcher v2026.10.28.1
echo Script: "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\update-ai.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\update-ai.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
