#!/usr/bin/env bash
# 在生产机安装 coturn + qdbot-webrtc-relay（需 root）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ponytail: sudo 默认不传 env；可用参数或 sudo VAR=... bash install.sh
TURN_SECRET="${WEBRTC_TURN_SECRET:-${1:-}}"
EXTERNAL_IP="${WEBRTC_EXTERNAL_IP:-39.96.167.94}"
INTERNAL_IP="${WEBRTC_INTERNAL_IP:-$EXTERNAL_IP}"

if [[ -z "$TURN_SECRET" ]]; then
  echo "Usage:" >&2
  echo "  sudo WEBRTC_TURN_SECRET='...' bash $0" >&2
  echo "  sudo bash $0 '<turn-secret>'" >&2
  echo "(export 后裸 sudo 不会带上 WEBRTC_TURN_SECRET)" >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y coturn
  sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null || true
fi

mkdir -p /var/log/turnserver /etc/qdbot
chown turnserver:turnserver /var/log/turnserver 2>/dev/null || chown root:root /var/log/turnserver

CONF="$(mktemp)"
sed \
  -e "s/EXTERNAL_IP/$EXTERNAL_IP/g" \
  -e "s/INTERNAL_IP/$INTERNAL_IP/g" \
  -e "s/REPLACE_TURN_SECRET/$TURN_SECRET/g" \
  "$SCRIPT_DIR/turnserver.conf.tpl" > "$CONF"
cp "$CONF" /etc/turnserver.conf
rm -f "$CONF"

ENV_FILE="/etc/qdbot/webrtc-relay.env"
tee "$ENV_FILE" >/dev/null <<EOF
WEBRTC_LISTEN=:8099
WEBRTC_TURN_SECRET=$TURN_SECRET
WEBRTC_TURN_HOST=$EXTERNAL_IP
WEBRTC_STUN_URL=stun:stun.l.google.com:19302
WEBRTC_AUTH_BASE=https://www.aimatchem.com
WEBRTC_CRED_TTL_SEC=86400
EOF
chmod 600 "$ENV_FILE"

cp "$SCRIPT_DIR/webrtc-relay.service" /etc/systemd/system/qdbot-webrtc-relay.service
systemctl daemon-reload
systemctl enable coturn qdbot-webrtc-relay
systemctl restart coturn qdbot-webrtc-relay

echo "coturn + webrtc-relay installed."
echo "TURN secret saved in $ENV_FILE"
echo "Open UDP/TCP 3478 and UDP 49152-65535 on security group."
