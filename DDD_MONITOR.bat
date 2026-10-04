@echo off
cd /d "%~dp0"
for /f "delims=" %%p in ('node tools\deploy-helper.js env-get PORT') do set "PORT=%%p"
if "%PORT%"=="" set "PORT=8765"
echo.
echo  Opening the Live Monitor. Sign in as Supervisor, Manager or Admin.
start "" "http://localhost:%PORT%/#monitor"
