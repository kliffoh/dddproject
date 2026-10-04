@echo off
setlocal
cd /d "%~dp0"
title DDD AI Workforce v6 - Admin Centre
for /f "delims=" %%d in ('node tools\deploy-helper.js data-dir') do set "DATA=%%d"
for /f "delims=" %%p in ('node tools\deploy-helper.js env-get PORT') do set "PORT=%%p"
if "%PORT%"=="" set "PORT=8765"
:menu
cls
echo.
echo  ============================================================
echo   DDD AI WORKFORCE v6 - ADMIN COMMAND CENTRE
echo  ============================================================
echo   Data folder: %DATA%
echo.
echo   1. Open DDD in browser
echo   2. Server health
echo   3. Show LAN addresses for staff
echo   4. Open log folder
echo   5. Open backups folder (hourly database snapshots)
echo   6. Back up the database now (copy latest snapshot to Desktop)
echo   7. Import employees from CSV (bulk onboarding)
echo   8. Edit settings (.env)
echo   9. Hosting Centre (put online / run forever)
echo   0. Exit
echo  ============================================================
set "C="
set /p "C= Select: "
if "%C%"=="1" start "" "http://localhost:%PORT%" & goto menu
if "%C%"=="2" node tools\deploy-helper.js health & pause & goto menu
if "%C%"=="3" (for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4"') do echo    http:%%i:%PORT%) & pause & goto menu
if "%C%"=="4" explorer "%DATA%\logs" & goto menu
if "%C%"=="5" explorer "%DATA%\backups" & goto menu
if "%C%"=="6" goto backup
if "%C%"=="7" goto import
if "%C%"=="8" notepad ".env" & goto menu
if "%C%"=="9" call DDD_HOSTING.bat & goto menu
if "%C%"=="0" goto done
goto menu
:backup
set "LATEST="
for /f "delims=" %%f in ('dir /b /o-d "%DATA%\backups\backup_*.sqlite3" 2^>nul') do if not defined LATEST set "LATEST=%%f"
if not defined LATEST (echo  No snapshot yet - the first one is taken a minute after the server starts. & pause & goto menu)
copy /y "%DATA%\backups\%LATEST%" "%USERPROFILE%\Desktop\" >nul && echo  Copied %LATEST% to your Desktop.
pause
goto menu
:import
echo.
echo  CSV columns: id,name,email,department,role,job_title,phone,birthday,hire_date
echo  A template is in tools\employees_template.csv
set "CSV="
set /p "CSV= Path to CSV file: "
node tools\import-employees.js "%CSV%"
pause
goto menu
:done
endlocal
