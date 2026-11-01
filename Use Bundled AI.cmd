@echo off
setlocal DisableDelayedExpansion
title AnajakMap - Use Bundled Gemini Configuration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\update-ai.ps1" -UseBundledConfiguration
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %ANAJAK_EXIT%
