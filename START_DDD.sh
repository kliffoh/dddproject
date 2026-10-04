#!/usr/bin/env bash
# DDD AI Workforce v6 — Linux/macOS launcher (foreground). For 24/7 use: ./DDD_HOSTING.sh → option 9
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
echo
echo "  DDD AI WORKFORCE MANAGEMENT SYSTEM v6 — Changing How the World Works."
echo
command -v node >/dev/null || { echo "  [ERROR] Node.js 22.13+ required: https://nodejs.org"; exit 1; }
MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$MAJOR" -ge 22 ] || { echo "  [ERROR] Node $(node -v) is too old — install 22.13 or newer."; exit 1; }
[ -d node_modules ] || npm install --omit=dev
[ -f .env ] || cp .env.example .env
PORT=$(node tools/deploy-helper.js env-get PORT); PORT=${PORT:-8765}
( sleep 3; { command -v xdg-open >/dev/null && xdg-open "http://localhost:$PORT"; } || { command -v open >/dev/null && open "http://localhost:$PORT"; } ) >/dev/null 2>&1 &
exec node server.js
