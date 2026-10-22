@echo off
setlocal
title AnajakMap - Start Backend
echo Starting AnajakMap backend...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AnajakMapBackend\AnajakMapBackend\scripts\start-oneclick.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
if not "%ANAJAK_EXIT%"=="0" (
  echo Startup failed. Read the message above before trying again.
) else (
  echo Backend runs in Docker. You can close this window.
)
pause
exit /b %ANAJAK_EXIT%
