#!/usr/bin/env bash
# ================================================================
#  DDD AI WORKFORCE v6 - HOSTING CENTRE (Linux / macOS)
#  Puts DDD online and keeps it running. Pick one option, or combine:
#  e.g. 9 (run forever) + 1 (domain) or 9 + 3 (Cloudflare Tunnel).
# ================================================================
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(pwd)"
H() { node "$ROOT/tools/deploy-helper.js" "$@"; }

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_b=$'\e[1m'; c_0=$'\e[0m'
ok()   { echo "  ${c_ok}[OK]${c_0} $*"; }
warn() { echo "  ${c_warn}[!]${c_0}  $*"; }
err()  { echo "  ${c_err}[ERROR]${c_0} $*"; }
pause(){ read -r -p "  Press Enter to continue..." _; }
ask()  { local __v; read -r -p "  $1" __v; printf '%s' "$__v"; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64) DEB_ARCH=amd64 ;; aarch64|arm64) DEB_ARCH=arm64 ;; armv7l) DEB_ARCH=arm ;; *) DEB_ARCH=amd64 ;; esac
SUDO=""; [ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

if ! have node; then
  err "Node.js 22.13+ is required: https://nodejs.org  (or: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs)"
  exit 1
fi
[ -d node_modules ] || { echo "  Installing dependencies..."; npm install --omit=dev; }
[ -f .env ] || cp .env.example .env
PORT="$(H env-get PORT)"; PORT="${PORT:-8765}"

ensure_running() {
  H health >/dev/null 2>&1 && return 0
  warn "The DDD server is not running on port $PORT."
  local a; a="$(ask 'Start it now in the background? (Y/n): ')"
  [[ "$a" =~ ^[Nn]$ ]] && return 0
  nohup node server.js >"$ROOT/ddd-server.log" 2>&1 &
  sleep 4; H health || warn "See $ROOT/ddd-server.log"
}
restart_hint() {
  echo; echo "  ${c_dim}Settings in .env changed — restart the server so it picks them up:"
  echo "    systemd: sudo systemctl restart ddd-workforce    |  PM2: pm2 restart ddd-workforce"
  echo "    manual:  stop it (Ctrl+C) and run ./START_DDD.sh${c_0}"
}

# ─── Installers ─────────────────────────────────────────────────
install_caddy() {
  have caddy && return 0
  echo "  Installing Caddy..."
  if [ "$OS" = "Darwin" ]; then have brew && brew install caddy; return; fi
  if have apt-get; then
    $SUDO apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    $SUDO apt-get update && $SUDO apt-get install -y caddy
  elif have dnf; then
    $SUDO dnf install -y 'dnf-command(copr)' && $SUDO dnf copr enable -y @caddy/caddy && $SUDO dnf install -y caddy
  else
    curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=${DEB_ARCH}" -o /tmp/caddy && chmod +x /tmp/caddy && $SUDO mv /tmp/caddy /usr/local/bin/caddy
  fi
}
install_cloudflared() {
  have cloudflared && return 0
  echo "  Installing cloudflared..."
  if [ "$OS" = "Darwin" ]; then brew install cloudflared; return; fi
  if have dpkg; then
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${DEB_ARCH}.deb" -o /tmp/cloudflared.deb && $SUDO dpkg -i /tmp/cloudflared.deb
  else
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${DEB_ARCH}" -o /tmp/cloudflared && chmod +x /tmp/cloudflared && $SUDO mv /tmp/cloudflared /usr/local/bin/cloudflared
  fi
}
install_ngrok() {
  have ngrok && return 0
  echo "  Installing ngrok..."
  if [ "$OS" = "Darwin" ]; then brew install ngrok/ngrok/ngrok; return; fi
  curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${DEB_ARCH}.tgz" -o /tmp/ngrok.tgz && $SUDO tar -xzf /tmp/ngrok.tgz -C /usr/local/bin
}

# ─── 1. Custom domain ───────────────────────────────────────────
opt_domain() {
  echo; echo "  ${c_b}=== 1. CUSTOM DOMAIN WITH AUTOMATIC HTTPS ===${c_0}"
  echo "   Before you start:"
  echo "    a) Create a DNS A record:  workforce.yourcompany.com -> this server's public IP"
  echo "    b) Allow inbound TCP 80 and 443 (cloud firewall / router port-forward)."
  echo
  local domain email rc
  domain="$(ask 'Domain (e.g. workforce.yourcompany.com): ')"
  email="$(ask 'Email for certificate notices: ')"
  H caddyfile "$domain" "$email" || { pause; return; }
  echo "  Checking DNS..."; H dns-check "$domain"; rc=$?
  if [ $rc -ne 0 ]; then [[ "$(ask 'DNS not confirmed. Continue anyway? (y/N): ')" =~ ^[Yy]$ ]] || return; fi
  install_caddy || { err "Caddy install failed: https://caddyserver.com/docs/install"; pause; return; }
  if [ "$OS" = "Darwin" ]; then
    local etc; etc="$(brew --prefix)/etc"; cp "$ROOT/deploy/generated/Caddyfile" "$etc/Caddyfile"
    brew services restart caddy
  elif [ -d /etc/caddy ] && have systemctl && systemctl cat caddy.service >/dev/null 2>&1; then
    $SUDO cp "$ROOT/deploy/generated/Caddyfile" /etc/caddy/Caddyfile
    $SUDO systemctl enable --now caddy && $SUDO systemctl reload caddy || $SUDO systemctl restart caddy
  elif have systemctl; then
    $SUDO tee /etc/systemd/system/ddd-caddy.service >/dev/null <<EOF
[Unit]
Description=DDD Caddy HTTPS proxy
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=$(command -v caddy) run --config $ROOT/deploy/generated/Caddyfile --adapter caddyfile
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF
    $SUDO systemctl daemon-reload && $SUDO systemctl enable --now ddd-caddy
  else
    nohup caddy run --config "$ROOT/deploy/generated/Caddyfile" --adapter caddyfile >"$ROOT/caddy.log" 2>&1 &
    warn "No systemd found — Caddy started in the background but will not survive a reboot."
  fi
  if have ufw && $SUDO ufw status | grep -q active; then $SUDO ufw allow 80/tcp; $SUDO ufw allow 443/tcp; fi
  ensure_running; restart_hint
  ok "Serving https://$domain  (the certificate is issued on the first visit — allow ~1 minute)."
  pause
}

# ─── 2. Netlify ─────────────────────────────────────────────────
opt_netlify() {
  echo; echo "  ${c_b}=== 2. NETLIFY ===${c_0}"
  echo "   Netlify hosts static websites only. It cannot run DDD's always-on server,"
  echo "   live WebSocket monitor or database. The web app goes on Netlify and talks"
  echo "   to your DDD backend running via option 1, 3, 6, 7 or 8."
  echo
  local backend site
  backend="$(ask 'Backend HTTPS URL (e.g. https://workforce.yourcompany.com): ')"
  H netlify-build "$backend" || { pause; return; }
  site="$(ask 'Netlify site URL if known (e.g. https://ddd-workforce.netlify.app) or Enter: ')"
  [ -n "$site" ] && H env-set "ALLOWED_ORIGINS=$site"
  echo "  Deploying with the Netlify CLI (a browser opens to sign in the first time)..."
  npx --yes netlify-cli deploy --prod --dir "$ROOT/deploy/netlify/dist"
  warn "If Netlify assigned a different URL, re-run this option with it, then restart the backend."
  [ -n "$site" ] && restart_hint
  pause
}

# ─── 3. Cloudflare Tunnel (token / service) ─────────────────────
opt_cftunnel() {
  echo; echo "  ${c_b}=== 3. CLOUDFLARE TUNNEL (recommended for most offices) ===${c_0}"
  echo "   Your domain, free HTTPS, WebSockets, no port-forwarding, survives reboots."
  echo "    1. Add your domain to Cloudflare (free plan)."
  echo "    2. https://one.dash.cloudflare.com -> Networks -> Tunnels -> Create (Cloudflared)."
  echo "    3. Copy the token (long eyJ... string) from the install command."
  echo "    4. Public Hostname: workforce.yourcompany.com  ->  HTTP  localhost:$PORT"
  echo
  install_cloudflared || { err "cloudflared install failed."; pause; return; }
  local token host
  token="$(ask 'Paste the tunnel token: ')"; [ -z "$token" ] && return
  host="$(ask 'Public hostname you configured: ')"
  $SUDO cloudflared service uninstall >/dev/null 2>&1 || true
  $SUDO cloudflared service install "$token" || { err "Service install failed."; pause; return; }
  [ -n "$host" ] && H env-set "PUBLIC_URL=https://$host" TRUST_PROXY=1
  ensure_running; restart_hint
  ok "Tunnel service installed. Visit https://$host  (combine with option 9 for the DDD server)."
  pause
}

# ─── 4. Quick tunnel ────────────────────────────────────────────
opt_cfquick() {
  echo; echo "  ${c_b}=== 4. CLOUDFLARE QUICK TUNNEL ===${c_0}"
  echo "   Random https://xxxx.trycloudflare.com link, no account. Changes every run"
  echo "   and stops when you press Ctrl+C. For demos — use option 3 for production."
  install_cloudflared || { pause; return; }
  ensure_running
  echo "  Press Ctrl+C to stop the tunnel and return."
  cloudflared tunnel --url "http://localhost:$PORT" || true
}

# ─── 5. ngrok ───────────────────────────────────────────────────
opt_ngrok() {
  echo; echo "  ${c_b}=== 5. NGROK ===${c_0}"
  echo "   Sign up at https://dashboard.ngrok.com, copy your Authtoken; optionally claim a free static domain."
  install_ngrok || { pause; return; }
  local tok dom
  tok="$(ask 'Authtoken (Enter to skip if configured): ')"; [ -n "$tok" ] && ngrok config add-authtoken "$tok"
  dom="$(ask 'Static domain (e.g. ddd-work.ngrok-free.app) or Enter for random: ')"
  ensure_running
  if [ -n "$dom" ]; then H env-set "PUBLIC_URL=https://$dom" TRUST_PROXY=1; ngrok http "$PORT" --url="$dom" || true
  else ngrok http "$PORT" || true; fi
}

# ─── 6. Fly.io ──────────────────────────────────────────────────
opt_fly() {
  echo; echo "  ${c_b}=== 6. FLY.IO ===${c_0}"
  echo "   Docker + persistent volume, never sleeps, HTTPS on https://APP.fly.dev"
  echo "   (custom domain later: flyctl certs add your.domain). Requires a card on file."
  local FLY; FLY="$(command -v flyctl || command -v fly || echo "$HOME/.fly/bin/flyctl")"
  if [ ! -x "$FLY" ]; then curl -fsSL https://fly.io/install.sh | sh; FLY="$HOME/.fly/bin/flyctl"; fi
  local app region sp
  app="$(ask 'App name (lowercase, e.g. ddd-workforce-ke): ')"
  region="$(ask 'Region [jnb = Johannesburg]: ')"; region="${region:-jnb}"
  H fly-toml "$app" "$region" || { pause; return; }
  "$FLY" auth whoami >/dev/null 2>&1 || "$FLY" auth login
  "$FLY" apps create "$app" || true
  "$FLY" volumes create ddd_data --size 1 --region "$region" --app "$app" --yes || true
  sp="$(ask 'SuperAdmin (DEV-001) password for the cloud copy (Enter to skip): ')"
  [ -n "$sp" ] && "$FLY" secrets set "SUPER_ADMIN_PASS=$sp" --app "$app" --stage
  "$FLY" deploy --app "$app" && ok "Open https://$app.fly.dev"
  pause
}

# ─── 7. Render / 8. Railway ─────────────────────────────────────
git_push() {
  have git || { err "Install git first."; return 1; }
  [ -d .git ] || { git init -b main >/dev/null && echo "  Created a Git repository."; }
  git add -A && git commit -m "DDD AI Workforce v6" >/dev/null 2>&1 || true
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "  Create an EMPTY PRIVATE repository on GitHub/GitLab first."
    local repo; repo="$(ask 'Repository URL: ')"; [ -z "$repo" ] && return 1
    git remote add origin "$repo"
  fi
  git push -u origin HEAD
}
open_url() { if have xdg-open; then xdg-open "$1" >/dev/null 2>&1 & elif have open; then open "$1"; else echo "  Open: $1"; fi; }

opt_render() {
  echo; echo "  ${c_b}=== 7. RENDER ===${c_0}"
  echo "   Deploys from Git using render.yaml. Needs a paid Starter instance (free"
  echo "   instances sleep and cannot keep the database disk)."
  git_push || { pause; return; }
  echo "  Now: Render Dashboard -> New -> Blueprint -> choose this repository."
  echo "  Fill in SUPER_ADMIN_PASS (and ANTHROPIC_API_KEY if you have one)."
  open_url "https://dashboard.render.com/blueprints"; pause
}
opt_railway() {
  echo; echo "  ${c_b}=== 8. RAILWAY ===${c_0}"
  echo "   After the first deploy add a Volume mounted at /data and DDD_DATA_DIR=/data"
  echo "   in the Railway dashboard, or the database is lost on redeploy."
  npx --yes @railway/cli login && npx --yes @railway/cli init && npx --yes @railway/cli up
  echo "  Then: Settings -> Networking -> Generate Domain (or add your own)."
  open_url "https://railway.com/dashboard"; pause
}

# ─── 9. Run forever ─────────────────────────────────────────────
opt_forever() {
  echo; echo "  ${c_b}=== 9. RUN FOREVER ===${c_0}"
  echo "   A. systemd service (Linux, recommended) — starts at boot, restarts in 3 s"
  echo "   B. PM2 process manager (Linux or macOS)  — restarts on crash, survives reboot"
  local f; f="$(ask 'Choose A or B: ')"
  H env-set "DDD_DATA_DIR=$(H data-dir)"
  case "$f" in
    [Aa])
      have systemctl || { err "systemd not available — use B."; pause; return; }
      sed -e "s#__USER__#$(id -un)#" -e "s#__DIR__#$ROOT#" -e "s#__NODE__#$(command -v node)#" \
        "$ROOT/deploy/linux/ddd-workforce.service.template" | $SUDO tee /etc/systemd/system/ddd-workforce.service >/dev/null
      $SUDO systemctl daemon-reload && $SUDO systemctl enable --now ddd-workforce
      sleep 4; H health
      ok "Installed. Logs: journalctl -u ddd-workforce -f   |   Restart: sudo systemctl restart ddd-workforce" ;;
    [Bb])
      have pm2 || npm install -g pm2 || $SUDO npm install -g pm2
      pm2 start "$ROOT/deploy/ecosystem.config.js" && pm2 save
      echo "  Registering PM2 to start at boot..."
      $SUDO env PATH="$PATH:$(dirname "$(command -v node)")" "$(command -v pm2)" startup "$( [ "$OS" = Darwin ] && echo launchd || echo systemd )" -u "$(id -un)" --hp "$HOME"
      pm2 save
      ok "PM2 manages DDD.  pm2 status | pm2 logs ddd-workforce | pm2 restart ddd-workforce" ;;
  esac
  pause
}

# ─── 10. Docker ─────────────────────────────────────────────────
opt_docker() {
  echo; echo "  ${c_b}=== 10. DOCKER COMPOSE ===${c_0}"
  have docker || { echo "  Install Docker: curl -fsSL https://get.docker.com | sh"; pause; return; }
  if [[ "$(ask 'Add automatic HTTPS for a domain? (y/N): ')" =~ ^[Yy]$ ]]; then
    local d e; d="$(ask 'Domain: ')"; e="$(ask 'Email: ')"
    H env-set "CADDY_DOMAIN=$d" "CADDY_EMAIL=$e" "PUBLIC_URL=https://$d" TRUST_PROXY=1
    docker compose --profile https up -d --build
  else
    docker compose up -d --build
  fi
  docker compose ps
  ok "Containers restart automatically (restart: unless-stopped). Enable Docker at boot: sudo systemctl enable docker"
  pause
}

# ─── 11. Status / 12. Remove ────────────────────────────────────
opt_status() {
  echo; echo "  ${c_b}=== STATUS ===${c_0}"
  H health; local pu; pu="$(H env-get PUBLIC_URL)"; [ -n "$pu" ] && H health "$pu"
  if have systemctl; then
    for u in ddd-workforce caddy ddd-caddy cloudflared; do
      systemctl cat "$u.service" >/dev/null 2>&1 && printf "   %-15s %s\n" "$u" "$(systemctl is-active "$u" 2>/dev/null)"
    done
  fi
  have pm2 && pm2 jlist 2>/dev/null | grep -q ddd-workforce && echo "   PM2: ddd-workforce registered"
  echo "   LAN addresses:"
  if have hostname && hostname -I >/dev/null 2>&1; then for ip in $(hostname -I); do echo "     http://$ip:$PORT"; done
  else ipconfig getifaddr en0 2>/dev/null | sed "s#.*#     http://&:$PORT#"; fi
  pause
}
opt_remove() {
  echo "  Removing DDD services (your data is untouched)..."
  if have systemctl; then
    for u in ddd-workforce ddd-caddy; do $SUDO systemctl disable --now "$u" 2>/dev/null && $SUDO rm -f "/etc/systemd/system/$u.service" && echo "   removed $u"; done
    $SUDO systemctl daemon-reload
  fi
  have pm2 && pm2 delete ddd-workforce 2>/dev/null && pm2 save && echo "   removed PM2 app"
  have cloudflared && $SUDO cloudflared service uninstall 2>/dev/null && echo "   removed Cloudflare Tunnel service"
  pause
}

# ─── Menu ───────────────────────────────────────────────────────
while true; do
  clear
  cat <<EOF

  ${c_b}================================================================
    DDD AI WORKFORCE v6  -  HOSTING CENTRE   ($OS/$ARCH)
    Changing How the World Works.
  ================================================================${c_0}
   PUT DDD ONLINE
     1. Custom domain   - your own server + free automatic HTTPS (Caddy)
     2. Netlify         - web app on Netlify, backend on 1 / 3 / 6-8
     3. Cloudflare Tunnel - your domain, no port-forwarding, permanent
     4. Cloudflare Quick Tunnel - instant temporary link, no account
     5. ngrok           - quick public link (free static domain available)

   CLOUD PLATFORMS (always-on, managed)
     6. Fly.io          - Docker + persistent volume, Johannesburg region
     7. Render          - Blueprint deploy from Git (paid plan + disk)
     8. Railway         - deploy with the Railway CLI

   KEEP IT RUNNING
     9. Run forever     - systemd / PM2: start at boot, restart on crash
    10. Docker Compose  - any server with Docker (optional HTTPS)

    11. Status and health check
    12. Remove services
     0. Exit
  ================================================================
EOF
  case "$(ask 'Choose an option: ')" in
    1) opt_domain ;; 2) opt_netlify ;; 3) opt_cftunnel ;; 4) opt_cfquick ;; 5) opt_ngrok ;;
    6) opt_fly ;; 7) opt_render ;; 8) opt_railway ;; 9) opt_forever ;; 10) opt_docker ;;
    11) opt_status ;; 12) opt_remove ;; 0) exit 0 ;;
  esac
done
