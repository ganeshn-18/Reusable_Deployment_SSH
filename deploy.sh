#!/usr/bin/env bash
# deploy.sh - lives on the SERVER inside your deploy_path (e.g. /var/www/my-app)
# The GitHub workflow runs: cd <deploy_path> && ./deploy.sh
#
# Setup once on the server:
#   chmod +x deploy.sh
#   git clone <repo-url> .        (server needs read access, e.g. a deploy key)
 
set -euo pipefail
 
BRANCH="${BRANCH:-main}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"
 
# Prevent two deploys running at the same time
exec 9>/tmp/deploy-"$(basename "$APP_DIR")".lock
flock -n 9 || { echo "Another deploy is running. Exiting."; exit 1; }
 
echo "==> [$(date '+%F %T')] Deploying $(basename "$APP_DIR") (branch: $BRANCH)"
 
# 1. Get latest code
git fetch --all --prune
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"
 
# 2. Build / restart: keep ONLY the block that matches your app -------------
 
# --- Option A: Docker Compose ---
if [ -f docker-compose.yml ] || [ -f compose.yaml ]; then
  docker compose pull || true
  docker compose up -d --build --remove-orphans
  docker image prune -f
 
# --- Option B: Node.js app with PM2 ---
elif [ -f package.json ]; then
  npm ci --omit=dev
  npm run build --if-present
  pm2 reload ecosystem.config.js --update-env 2>/dev/null || pm2 restart all
 
# --- Option C: Python app with systemd ---
elif [ -f requirements.txt ]; then
  [ -d venv ] || python3 -m venv venv
  ./venv/bin/pip install -r requirements.txt
  sudo systemctl restart my-app.service
 
else
  echo "No known app type found; code updated only."
fi
 
echo "==> Deploy finished successfully"
 
