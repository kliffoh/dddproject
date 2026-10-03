@echo off
:: ================================================================
::  DDD AI WORKFORCE v6 - HOSTING CENTRE (Windows)
::  Puts DDD online and keeps it running. Pick one option, or combine:
::  e.g. 9 (run forever) + 1 (domain) or 9 + 3 (Cloudflare Tunnel).
:: ================================================================
setlocal EnableExtensions
cd /d "%~dp0"
title DDD AI Workforce v6 - Hosting Centre
set "H=node tools\deploy-helper.js"
set "ROOT=%CD%"

where node >nul 2>&1
if errorlevel 1 (
  echo  [ERROR] Node.js 22.13+ is required. Install the LTS from https://nodejs.org
  echo          or run:  winget install OpenJS.NodeJS.LTS
  pause & exit /b 1
)
if not exist "node_modules" (
  echo  Installing dependencies...
  call npm install --omit=dev
)
if not exist ".env" copy ".env.example" ".env" >nul
set "PORT="
for /f "delims=" %%p in ('%H% env-get PORT') do set "PORT=%%p"
if "%PORT%"=="" set "PORT=8765"

set "ISADMIN=0"
net session >nul 2>&1 && set "ISADMIN=1"

:menu
cls
echo.
echo  ================================================================
echo    DDD AI WORKFORCE v6  -  HOSTING CENTRE
echo    Changing How the World Works.
echo  ================================================================
if "%ISADMIN%"=="1" (echo    Running as Administrator: yes) else (echo    Running as Administrator: NO  - options 1, 3 and 9A need it)
echo.
echo    PUT DDD ONLINE
echo     1. Custom domain   - your own PC/server + free automatic HTTPS (Caddy)
echo     2. Netlify         - web app on Netlify, backend on 1 / 3 / 6-8
echo     3. Cloudflare Tunnel - your domain, no router setup, free, permanent
echo     4. Cloudflare Quick Tunnel - instant temporary public link, no account
echo     5. ngrok           - quick public link (free static domain available)
echo.
echo    CLOUD PLATFORMS (always-on, managed)
echo     6. Fly.io          - Docker + persistent volume, Johannesburg region
echo     7. Render          - Blueprint deploy from GitHub (paid plan + disk)
echo     8. Railway         - deploy with the Railway CLI
echo.
echo    KEEP IT RUNNING
echo     9. Run forever     - auto-start on boot, auto-restart on crash
echo    10. Docker Compose  - any server with Docker (optional HTTPS)
echo.
echo    11. Status and health check
echo    12. Remove auto-start tasks / services
echo     0. Exit
echo  ================================================================
set "C="
set /p "C=   Choose an option: "
if "%C%"=="1"  goto domain
if "%C%"=="2"  goto netlify
if "%C%"=="3"  goto cftunnel
if "%C%"=="4"  goto cfquick
if "%C%"=="5"  goto ngrok
if "%C%"=="6"  goto fly
if "%C%"=="7"  goto render
if "%C%"=="8"  goto railway
if "%C%"=="9"  goto forever
if "%C%"=="10" goto docker
if "%C%"=="11" goto status
if "%C%"=="12" goto remove
if "%C%"=="0"  goto end
goto menu

:: ----------------------------------------------------------------
:need_admin
echo.
echo  [!] This step needs Administrator rights.
echo      Right-click DDD_HOSTING.bat and choose "Run as administrator".
pause
goto menu

:ensure_running
%H% health >nul 2>&1
if not errorlevel 1 goto :eof
echo.
echo  [!] The DDD server is not running on port %PORT%.
set "S="
set /p "S=   Start it now in a new window? (Y/n): "
if /i "%S%"=="n" goto :eof
start "DDD Server" cmd /k node server.js
timeout /t 4 /nobreak >nul
goto :eof

:restart_hint
echo.
echo  [i] Settings in .env changed. Restart the DDD server so it picks them up:
echo      close the server window and run START_DDD.bat again,
echo      or, if you used option 9:  schtasks /end /tn "DDD Workforce" ^&^& schtasks /run /tn "DDD Workforce"
goto :eof

:: ================================================================
:domain
cls
echo.
echo  === 1. CUSTOM DOMAIN WITH AUTOMATIC HTTPS ======================
echo.
echo   Before you start:
echo    a) Buy/own a domain and create a DNS "A" record, e.g.
echo         workforce.yourcompany.com  -^>  your public IP
echo    b) On your router, forward TCP ports 80 and 443 to this PC.
echo    c) Keep this PC on (combine with option 9 for auto-start).
echo.
if "%ISADMIN%"=="0" goto need_admin
set "DOMAIN=" & set "EMAIL="
set /p "DOMAIN=   Domain (e.g. workforce.yourcompany.com): "
set /p "EMAIL=   Email for certificate notices: "
%H% caddyfile %DOMAIN% %EMAIL%
if errorlevel 1 (pause & goto menu)
echo.
echo   Checking DNS...
%H% dns-check %DOMAIN%
set "DNSRC=%errorlevel%"
if "%DNSRC%"=="0" goto dom_dns_ok
set "S="
set /p "S=   DNS is not confirmed yet. Continue anyway? (y/N): "
if /i not "%S%"=="y" goto menu
:dom_dns_ok

set "CADDY="
for /f "delims=" %%c in ('where caddy 2^>nul') do if not defined CADDY set "CADDY=%%c"
if not defined CADDY if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\caddy.exe" set "CADDY=%LOCALAPPDATA%\Microsoft\WinGet\Links\caddy.exe"
if not defined CADDY (
  echo   Installing Caddy web server...
  winget install -e --id CaddyServer.Caddy --accept-package-agreements --accept-source-agreements
  if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\caddy.exe" set "CADDY=%LOCALAPPDATA%\Microsoft\WinGet\Links\caddy.exe"
)
if not defined CADDY for /f "delims=" %%c in ('where caddy 2^>nul') do if not defined CADDY set "CADDY=%%c"
if not defined CADDY if exist "%ROOT%\deploy\generated\caddy.exe" set "CADDY=%ROOT%\deploy\generated\caddy.exe"
if defined CADDY goto dom_have_caddy
echo  [ERROR] Caddy not found. Download caddy.exe from https://caddyserver.com/download
echo          into "%ROOT%\deploy\generated\" and run this option again.
pause
goto menu
:dom_have_caddy

:: Copy caddy next to the config so the SYSTEM task never depends on a user profile path
copy /y "%CADDY%" "%ROOT%\deploy\generated\caddy.exe" >nul 2>&1
set "CADDY=%ROOT%\deploy\generated\caddy.exe"

echo   Opening Windows Firewall for ports 80 and 443...
netsh advfirewall firewall delete rule name="DDD HTTPS" >nul 2>&1
netsh advfirewall firewall add rule name="DDD HTTPS" dir=in action=allow protocol=TCP localport=80,443 >nul

echo   Registering Caddy to start automatically at boot...
schtasks /create /tn "DDD Caddy" /tr "\"%CADDY%\" run --config \"%ROOT%\deploy\generated\Caddyfile\" --adapter caddyfile" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul
schtasks /end /tn "DDD Caddy" >nul 2>&1
schtasks /run /tn "DDD Caddy" >nul
call :ensure_running
call :restart_hint
echo.
echo  [OK] Caddy is serving https://%DOMAIN%  (certificate is issued on first visit; allow ~1 minute)
echo       Note: some routers cannot reach their own public domain from inside the office.
echo       Staff on the office network can always use  http://THIS-PC-LAN-IP:%PORT%
pause
goto menu

:: ================================================================
:netlify
cls
echo.
echo  === 2. NETLIFY ===================================================
echo.
echo   Netlify hosts static websites. It cannot run DDD's always-on server,
echo   live WebSocket monitor or database. So:
echo     - the web app (index.html) is published on Netlify, and
echo     - it talks to your DDD backend running via option 1, 3, 6, 7 or 8.
echo.
set "BACKEND="
set /p "BACKEND=   Your backend HTTPS URL (e.g. https://workforce.yourcompany.com): "
%H% netlify-build %BACKEND%
if errorlevel 1 (pause & goto menu)
echo.
set "SITE="
set /p "SITE=   Netlify site URL if known (e.g. https://ddd-workforce.netlify.app) or Enter: "
if not "%SITE%"=="" %H% env-set ALLOWED_ORIGINS=%SITE%
echo.
echo   Deploying with the Netlify CLI (a browser window opens to sign in the first time)...
call npx --yes netlify-cli deploy --prod --dir "deploy\netlify\dist"
echo.
echo  [i] If Netlify gave you a different site URL, re-run this option and enter it,
echo      then restart the backend so it accepts requests from that site.
if not "%SITE%"=="" call :restart_hint
pause
goto menu

:: ================================================================
:cftunnel
cls
echo.
echo  === 3. CLOUDFLARE TUNNEL (recommended for most offices) =========
echo.
echo   Publishes DDD on your own domain through Cloudflare: free HTTPS,
echo   WebSockets supported, no router port-forwarding, runs as a Windows
echo   service so it survives reboots.
echo.
echo   One-time setup in the browser:
echo    1. Add your domain to Cloudflare (free plan is fine).
echo    2. Open https://one.dash.cloudflare.com  -^>  Networks  -^>  Tunnels
echo    3. Create a tunnel (type Cloudflared), name it "ddd-workforce".
echo    4. Copy the token from the install command shown (the long eyJ... string).
echo    5. Add a Public Hostname, e.g.  workforce.yourcompany.com
echo         Service type: HTTP     URL: localhost:%PORT%
echo.
if "%ISADMIN%"=="0" goto need_admin
call :find_cloudflared
if not defined CFD (pause & goto menu)
set "TOKEN=" & set "HOST="
set /p "TOKEN=   Paste the tunnel token: "
if "%TOKEN%"=="" goto menu
set /p "HOST=   Public hostname you configured (e.g. workforce.yourcompany.com): "
"%CFD%" service uninstall >nul 2>&1
"%CFD%" service install %TOKEN%
if errorlevel 1 (echo  [ERROR] Service install failed. & pause & goto menu)
if not "%HOST%"=="" %H% env-set PUBLIC_URL=https://%HOST% TRUST_PROXY=1
call :ensure_running
call :restart_hint
echo.
echo  [OK] Cloudflare Tunnel service installed. Visit https://%HOST%
echo       Combine with option 9 so the DDD server also starts at boot.
pause
goto menu

:find_cloudflared
set "CFD="
for /f "delims=" %%c in ('where cloudflared 2^>nul') do if not defined CFD set "CFD=%%c"
if not defined CFD if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\cloudflared.exe" set "CFD=%LOCALAPPDATA%\Microsoft\WinGet\Links\cloudflared.exe"
if not defined CFD if exist "%ProgramFiles(x86)%\cloudflared\cloudflared.exe" set "CFD=%ProgramFiles(x86)%\cloudflared\cloudflared.exe"
if defined CFD goto :eof
echo   Installing cloudflared...
winget install -e --id Cloudflare.cloudflared --accept-package-agreements --accept-source-agreements
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\cloudflared.exe" set "CFD=%LOCALAPPDATA%\Microsoft\WinGet\Links\cloudflared.exe"
if not defined CFD if exist "%ProgramFiles(x86)%\cloudflared\cloudflared.exe" set "CFD=%ProgramFiles(x86)%\cloudflared\cloudflared.exe"
if not defined CFD for /f "delims=" %%c in ('where cloudflared 2^>nul') do if not defined CFD set "CFD=%%c"
if not defined CFD echo  [ERROR] cloudflared not found. Get it from https://github.com/cloudflare/cloudflared/releases
goto :eof

:: ================================================================
:cfquick
cls
echo.
echo  === 4. CLOUDFLARE QUICK TUNNEL ==================================
echo.
echo   Gives you a random https://xxxx.trycloudflare.com link in seconds.
echo   No account needed - but the link changes every time and stops when
echo   the window closes. Great for demos; use option 3 for production.
echo.
call :find_cloudflared
if not defined CFD (pause & goto menu)
call :ensure_running
start "DDD Quick Tunnel - keep this window open" cmd /k ""%CFD%" tunnel --url http://localhost:%PORT%"
echo  [OK] Look in the new window for the https://....trycloudflare.com link and share it.
pause
goto menu

:: ================================================================
:ngrok
cls
echo.
echo  === 5. NGROK ======================================================
echo.
echo   1. Sign up free at https://dashboard.ngrok.com
echo   2. Copy your Authtoken (Getting Started -^> Your Authtoken)
echo   3. Optional: claim your free static domain (Domains page)
echo.
set "NG="
for /f "delims=" %%c in ('where ngrok 2^>nul') do if not defined NG set "NG=%%c"
if not defined NG (
  winget install -e --id Ngrok.Ngrok --accept-package-agreements --accept-source-agreements
  if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe" set "NG=%LOCALAPPDATA%\Microsoft\WinGet\Links\ngrok.exe"
)
if not defined NG (echo  [ERROR] ngrok not found: https://ngrok.com/download & pause & goto menu)
set "NTOK=" & set "NDOM="
set /p "NTOK=   Authtoken (Enter to skip if already configured): "
if not "%NTOK%"=="" "%NG%" config add-authtoken %NTOK%
set /p "NDOM=   Static domain (e.g. ddd-work.ngrok-free.app) or Enter for random: "
call :ensure_running
if "%NDOM%"=="" (
  start "DDD ngrok - keep this window open" cmd /k ""%NG%" http %PORT%"
) else (
  %H% env-set PUBLIC_URL=https://%NDOM% TRUST_PROXY=1
  start "DDD ngrok - keep this window open" cmd /k ""%NG%" http %PORT% --url=%NDOM%"
)
echo  [OK] ngrok started in a new window. For a permanent setup prefer option 3.
pause
goto menu

:: ================================================================
:fly
cls
echo.
echo  === 6. FLY.IO =====================================================
echo.
echo   Runs DDD in Docker on Fly.io with a persistent volume. The machine
echo   never sleeps, restarts automatically and gets free HTTPS on
echo   https://APP.fly.dev (custom domain:  flyctl certs add your.domain).
echo   Fly requires a payment card on the account.
echo.
set "FLY="
for /f "delims=" %%c in ('where flyctl 2^>nul') do if not defined FLY set "FLY=%%c"
if not defined FLY if exist "%USERPROFILE%\.fly\bin\flyctl.exe" set "FLY=%USERPROFILE%\.fly\bin\flyctl.exe"
if not defined FLY (
  echo   Installing flyctl...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr https://fly.io/install.ps1 -useb | iex"
  if exist "%USERPROFILE%\.fly\bin\flyctl.exe" set "FLY=%USERPROFILE%\.fly\bin\flyctl.exe"
)
if not defined FLY (echo  [ERROR] flyctl not found: https://fly.io/docs/flyctl/install/ & pause & goto menu)
set "APP=" & set "REGION="
set /p "APP=   App name (lowercase, e.g. ddd-workforce-ke): "
set /p "REGION=   Region [jnb = Johannesburg]: "
if "%REGION%"=="" set "REGION=jnb"
%H% fly-toml %APP% %REGION%
if errorlevel 1 (pause & goto menu)
"%FLY%" auth whoami >nul 2>&1 || "%FLY%" auth login
"%FLY%" apps create %APP%
"%FLY%" volumes create ddd_data --size 1 --region %REGION% --app %APP% --yes
set "SP="
set /p "SP=   Set a SuperAdmin (DEV-001) password for the cloud copy (Enter to skip): "
if not "%SP%"=="" "%FLY%" secrets set SUPER_ADMIN_PASS=%SP% --app %APP% --stage
"%FLY%" deploy --app %APP%
echo.
echo  [OK] If the deploy succeeded, open https://%APP%.fly.dev
pause
goto menu

:: ================================================================
:render
cls
echo.
echo  === 7. RENDER ====================================================
echo.
echo   Render deploys from a Git repository using render.yaml (included).
echo   Needs a paid "Starter" instance: free instances sleep and cannot
echo   keep the database disk.
echo.
call :git_push
echo.
echo   Now: Render Dashboard -^> New -^> Blueprint -^> pick this repository.
echo   Fill in SUPER_ADMIN_PASS (and ANTHROPIC_API_KEY if you have one).
start "" "https://dashboard.render.com/blueprints"
pause
goto menu

:git_push
where git >nul 2>&1
if errorlevel 1 (echo  [ERROR] Git is required: winget install Git.Git & goto :eof)
if not exist ".git" (git init -b main >nul && echo   Created a Git repository.)
git add -A
git commit -m "DDD AI Workforce v6" >nul 2>&1
set "REPO="
for /f "delims=" %%r in ('git remote get-url origin 2^>nul') do set "REPO=%%r"
if defined REPO goto gp_push
echo   Create an EMPTY PRIVATE repository on GitHub/GitLab first.
set /p "REPO=   Repository URL (https://github.com/you/ddd-workforce.git): "
if "%REPO%"=="" goto :eof
git remote add origin %REPO%
:gp_push
git push -u origin HEAD
goto :eof

:: ================================================================
:railway
cls
echo.
echo  === 8. RAILWAY ===================================================
echo.
echo   Uses railway.json (Dockerfile build, auto-restart, health check).
echo   After the first deploy, add a Volume mounted at /data in the Railway
echo   dashboard, and the variable DDD_DATA_DIR=/data, or data is lost on redeploy.
echo.
call npx --yes @railway/cli login
call npx --yes @railway/cli init
call npx --yes @railway/cli up
echo.
echo  [i] Then in Railway: Settings -^> Networking -^> Generate Domain (or add your own).
start "" "https://railway.com/dashboard"
pause
goto menu

:: ================================================================
:forever
cls
echo.
echo  === 9. RUN FOREVER ===============================================
echo.
echo    A. Windows startup task + watchdog (built in, recommended)
echo       Starts at boot even before anyone logs in; restarts within
echo       5 seconds if the server ever stops. Needs Administrator.
echo    B. Start when I log in (no Administrator needed, hidden window)
echo    C. PM2 process manager (Node ecosystem tool)
echo.
set "F="
set /p "F=   Choose A, B or C: "
:: A fixed data folder means the SYSTEM account and your account share one database.
for /f "delims=" %%d in ('%H% data-dir') do set "DDIR=%%d"
%H% env-set "DDD_DATA_DIR=%DDIR%"
if /i "%F%"=="A" goto forever_a
if /i "%F%"=="B" goto forever_b
if /i "%F%"=="C" goto forever_c
goto menu

:forever_a
if "%ISADMIN%"=="0" goto need_admin
schtasks /create /tn "DDD Workforce" /tr "\"%ROOT%\deploy\windows\ddd-forever.bat\"" /sc onstart /ru SYSTEM /rl HIGHEST /f
netsh advfirewall firewall delete rule name="DDD Workforce" >nul 2>&1
netsh advfirewall firewall add rule name="DDD Workforce" dir=in action=allow protocol=TCP localport=%PORT% >nul
schtasks /run /tn "DDD Workforce"
timeout /t 5 /nobreak >nul
%H% health
echo  [OK] DDD now starts automatically at boot and restarts itself if it stops.
echo       Log: %ROOT%\ddd-forever.log
pause
goto menu

:forever_b
> "%ROOT%\deploy\windows\ddd-hidden.vbs" echo CreateObject("WScript.Shell").Run """%ROOT%\deploy\windows\ddd-forever.bat""", 0, False
schtasks /create /tn "DDD Workforce" /tr "wscript.exe \"%ROOT%\deploy\windows\ddd-hidden.vbs\"" /sc onlogon /f
schtasks /run /tn "DDD Workforce"
timeout /t 5 /nobreak >nul
%H% health
echo  [OK] DDD starts hidden whenever you log in, and restarts itself if it stops.
pause
goto menu

:forever_c
call npm install -g pm2 pm2-windows-startup
call pm2 start "%ROOT%\deploy\ecosystem.config.js"
call pm2 save
call pm2-startup install
echo  [OK] PM2 is managing DDD.  Useful:  pm2 status ^| pm2 logs ddd-workforce ^| pm2 restart ddd-workforce
pause
goto menu

:: ================================================================
:docker
cls
echo.
echo  === 10. DOCKER COMPOSE ===========================================
echo.
where docker >nul 2>&1
if errorlevel 1 (echo  [ERROR] Install Docker Desktop: https://www.docker.com/products/docker-desktop & pause & goto menu)
set "DH="
set /p "DH=   Add automatic HTTPS for a domain? (y/N): "
if /i not "%DH%"=="y" goto docker_plain
set "DOMAIN=" & set "EMAIL="
set /p "DOMAIN=   Domain: "
set /p "EMAIL=   Email: "
%H% env-set CADDY_DOMAIN=%DOMAIN% CADDY_EMAIL=%EMAIL% PUBLIC_URL=https://%DOMAIN% TRUST_PROXY=1
docker compose --profile https up -d --build
goto docker_done
:docker_plain
docker compose up -d --build
:docker_done
echo.
docker compose ps
echo  [OK] Containers restart automatically ("restart: unless-stopped").
echo       Enable "Start Docker Desktop when you sign in" in Docker settings.
pause
goto menu

:: ================================================================
:status
cls
echo.
echo  === STATUS =======================================================
echo.
%H% health
set "PU="
for /f "delims=" %%u in ('%H% env-get PUBLIC_URL') do set "PU=%%u"
if not "%PU%"=="" %H% health %PU%
echo.
schtasks /query /tn "DDD Workforce" >nul 2>&1 && (echo   Auto-start task "DDD Workforce": installed) || (echo   Auto-start task "DDD Workforce": not installed)
schtasks /query /tn "DDD Caddy" >nul 2>&1 && (echo   HTTPS task "DDD Caddy":          installed) || (echo   HTTPS task "DDD Caddy":          not installed)
sc query cloudflared >nul 2>&1 && (echo   Cloudflare Tunnel service:        installed) || (echo   Cloudflare Tunnel service:        not installed)
echo.
echo   LAN addresses for staff on the office network:
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4"') do echo      http:%%i:%PORT%
echo.
pause
goto menu

:: ================================================================
:remove
cls
echo.
echo  Removing DDD auto-start tasks and services...
if "%ISADMIN%"=="0" goto need_admin
schtasks /end /tn "DDD Workforce" >nul 2>&1
schtasks /delete /tn "DDD Workforce" /f >nul 2>&1 && echo   Removed task "DDD Workforce"
schtasks /end /tn "DDD Caddy" >nul 2>&1
schtasks /delete /tn "DDD Caddy" /f >nul 2>&1 && echo   Removed task "DDD Caddy"
call :find_cloudflared >nul 2>&1
if defined CFD "%CFD%" service uninstall >nul 2>&1 && echo   Removed Cloudflare Tunnel service
echo   Your data and database are untouched.
pause
goto menu

:end
endlocal
exit /b 0
