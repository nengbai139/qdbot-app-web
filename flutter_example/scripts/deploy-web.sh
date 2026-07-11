#!/usr/bin/env bash
# 构建并部署 Flutter Web 到生产环境
set -euo pipefail
HOST="${DEPLOY_HOST:-baineng@47.93.48.164}"
REMOTE_DIR="${DEPLOY_DIR:-/var/www/qdbot_app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash scripts/fetch-web-fonts.sh
# ponytail: 禁用 PWA service worker，避免部署后登录页被 SW 反复整页 reload
flutter build web --release --base-href=/app_web/ --pwa-strategy=none
# ponytail: 空 SW 文件会让浏览器异常；构建后删掉
rm -f build/web/flutter_service_worker.js
# ponytail: bust browser cache for index/bootstrap without touching Flutter output
sed -i '' "s/flutter_bootstrap.js?v=[0-9]*/flutter_bootstrap.js?v=$(date +%s)/" build/web/index.html 2>/dev/null \
  || sed -i "s/flutter_bootstrap.js?v=[0-9]*/flutter_bootstrap.js?v=$(date +%s)/" build/web/index.html
tar -czf /tmp/qdbot_app_web.tar.gz -C build/web .
scp /tmp/qdbot_app_web.tar.gz "$HOST:/tmp/qdbot_app_web.tar.gz"
ssh "$HOST" "sudo rm -rf ${REMOTE_DIR}/* && sudo tar -xzf /tmp/qdbot_app_web.tar.gz -C ${REMOTE_DIR}/"
echo "Deployed → https://www.aimatchem.com/app_web/"
