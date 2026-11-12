@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_questa.ps1" %*
set "SIM_EXIT=%ERRORLEVEL%"
echo.
if not "%SIM_EXIT%"=="0" echo Questa regression FAILED.
pause
exit /b %SIM_EXIT%
