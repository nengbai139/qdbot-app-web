#!/usr/bin/env bash
# 在生产机安装 coturn + qdbot-webrtc-relay（需 root）
set -euo pipefail

TURN_SECRET="${WEBRTC_TURN_SECRET:-}"
EXTERNAL_IP="${WEBRTC_EXTERNAL_IP:-39.96.167.94}"
INTERNAL_IP="${WEBRTC_INTERNAL_IP:-$EXTERNAL_IP}"

if [[ -z "$TURN_SECRET" ]]; then
  echo "Set WEBRTC_TURN_SECRET before running" >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y coturn
  sudo sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null || true
fi

sudo mkdir -p /var/log/turnserver /etc/qdbot
sudo chown turnserver:turnserver /var/log/turnserver 2>/dev/null || sudo chown root:root /var/log/turnserver

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONF="$(mktemp)"
sed \
  -e "s/EXTERNAL_IP/$EXTERNAL_IP/g" \
  -e "s/INTERNAL_IP/$INTERNAL_IP/g" \
  -e "s/REPLACE_TURN_SECRET/$TURN_SECRET/g" \
  "$ROOT/deploy/webrtc/turnserver.conf.tpl" > "$CONF"
sudo cp "$CONF" /etc/turnserver.conf
rm -f "$CONF"

ENV_FILE="/etc/qdbot/webrtc-relay.env"
sudo tee "$ENV_FILE" >/dev/null <<EOF
WEBRTC_LISTEN=:8099
WEBRTC_TURN_SECRET=$TURN_SECRET
WEBRTC_TURN_HOST=$EXTERNAL_IP
WEBRTC_STUN_URL=stun:stun.l.google.com:19302
WEBRTC_AUTH_BASE=https://www.aimatchem.com
WEBRTC_CRED_TTL_SEC=86400
EOF
sudo chmod 600 "$ENV_FILE"

sudo cp "$ROOT/deploy/webrtc/webrtc-relay.service" /etc/systemd/system/qdbot-webrtc-relay.service
sudo systemctl daemon-reload
sudo systemctl enable coturn qdbot-webrtc-relay
sudo systemctl restart coturn qdbot-webrtc-relay

echo "coturn + webrtc-relay installed."
echo "Open UDP/TCP 3478 and UDP 49152-65535 on security group."
