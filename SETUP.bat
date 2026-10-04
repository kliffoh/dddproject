@echo off
setlocal
cd /d "%~dp0"
title DDD AI Workforce v6 - Setup
cls
echo.
echo  ============================================================
echo   DDD AI WORKFORCE v6 - Setup
echo  ============================================================
echo.
where node >nul 2>&1
if errorlevel 1 (
  echo  Node.js not found. Installing Node.js LTS with winget...
  winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
  echo.
  echo  Close this window and run SETUP.bat again so Windows picks up Node.js.
  pause & exit /b 1
)
for /f "delims=" %%v in ('node -p "process.versions.node"') do set "NV=%%v"
node -e "const[a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)"
if errorlevel 1 (
  echo  [ERROR] Node.js %NV% is too old. DDD needs 22.13 or newer:
  echo          winget upgrade OpenJS.NodeJS.LTS
  pause & exit /b 1
)
echo  Node.js %NV%  [OK]
echo  Installing dependencies (pure JavaScript - no compiler needed)...
call npm install --omit=dev
if errorlevel 1 (echo  [ERROR] npm install failed - check your internet connection. & pause & exit /b 1)
if not exist ".env" copy ".env.example" ".env" >nul
echo.
echo  ============================================================
echo   Setup complete.
echo     START_DDD.bat    - run DDD on this PC / office network
echo     DDD_HOSTING.bat  - put DDD online and keep it running 24/7
echo  ============================================================
pause
endlocal
