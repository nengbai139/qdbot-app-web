#!/usr/bin/env bash
# 构建 relay 二进制并部署到生产机
set -euo pipefail
HOST="${DEPLOY_HOST:-baineng@39.96.167.94}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STAGE="$ROOT/deploy/webrtc/.staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
GOOS=linux GOARCH=amd64 go build -o "$STAGE/qdbot-webrtc-relay" ./cmd/webrtc-relay
cp "$ROOT/deploy/webrtc/turnserver.conf.tpl" \
   "$ROOT/deploy/webrtc/webrtc-relay.service" \
   "$ROOT/deploy/webrtc/install.sh" \
   "$ROOT/deploy/webrtc/webrtc-relay.env.example" \
   "$ROOT/deploy/webrtc/nginx-snippet.conf" \
   "$STAGE/"

ssh "$HOST" 'sudo mkdir -p /opt/qdbot/webrtc /usr/local/bin'
scp "$STAGE/qdbot-webrtc-relay" "$HOST:/tmp/qdbot-webrtc-relay"
scp "$STAGE/turnserver.conf.tpl" "$STAGE/webrtc-relay.service" "$STAGE/install.sh" \
    "$STAGE/webrtc-relay.env.example" "$STAGE/nginx-snippet.conf" "$HOST:/tmp/"
ssh "$HOST" 'set -e
  sudo cp /tmp/qdbot-webrtc-relay /usr/local/bin/
  sudo chmod +x /usr/local/bin/qdbot-webrtc-relay /tmp/install.sh
  sudo mv /tmp/turnserver.conf.tpl /tmp/webrtc-relay.service /tmp/install.sh \
    /tmp/webrtc-relay.env.example /tmp/nginx-snippet.conf /opt/qdbot/webrtc/
'
echo "Binary uploaded. On server run:"
echo "  export WEBRTC_TURN_SECRET='<same-secret-as-coturn>'"
echo "  sudo bash /opt/qdbot/webrtc/install.sh"
echo ""
echo "Nginx: see /opt/qdbot/webrtc/nginx-snippet.conf"
