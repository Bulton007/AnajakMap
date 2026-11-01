@echo off
setlocal
title AnajakMap - Connect Test Phone
echo Connecting your Android test phone to the local backend...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flutter_app\connect-device.ps1"
set "ANAJAK_EXIT=%ERRORLEVEL%"
echo.
if not "%ANAJAK_EXIT%"=="0" (
  echo Connection failed. Read the message above and try again.
)
pause
exit /b %ANAJAK_EXIT%
