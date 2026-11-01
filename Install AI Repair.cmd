@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Install AI Setup Repair v2026.10.28.1
echo AnajakMap AI Setup Repair Installer v2026.10.28.1
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\repair-ai-setup.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
