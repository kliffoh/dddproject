@echo off
setlocal
cd /d "%~dp0"
title DDD AI Workforce v6
cls
echo.
echo  ============================================================
echo   DDD AI WORKFORCE MANAGEMENT SYSTEM v6
echo   Changing How the World Works.
echo  ============================================================
echo.
where node >nul 2>&1
if errorlevel 1 (echo  [ERROR] Node.js not found. Run SETUP.bat first. & pause & exit /b 1)
if not exist "node_modules" (
  echo  Dependencies missing. Running setup...
  call SETUP.bat
  if errorlevel 1 exit /b 1
)
if not exist ".env" copy ".env.example" ".env" >nul

:: Settings live in .env (port, AI key, public URL, capacity). Edit with Notepad.
:: To put DDD online or make it start automatically, run DDD_HOSTING.bat.

node tools\deploy-helper.js health >nul 2>&1
if not errorlevel 1 (
  echo  DDD is already running. Opening the browser...
  start "" "http://localhost:8765"
  timeout /t 3 /nobreak >nul
  exit /b 0
)
echo  Starting DDD server... (press Ctrl+C to stop)
echo  Staff on your network: see the LAN address printed below.
echo.
start "" /min cmd /c "timeout /t 3 /nobreak >nul & start "" http://localhost:8765"
node server.js
echo.
echo  DDD server stopped.
pause
endlocal
