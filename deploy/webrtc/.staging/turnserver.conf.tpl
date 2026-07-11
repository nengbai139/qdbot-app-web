# coturn — 与 webrtc-relay 共用 WEBRTC_TURN_SECRET（static-auth-secret）
# 部署前替换 EXTERNAL_IP / INTERNAL_IP（阿里云 ECS 常相同）

listening-port=3478
tls-listening-port=0

listening-ip=0.0.0.0
relay-ip=INTERNAL_IP
external-ip=EXTERNAL_IP

realm=aimatchem.com
server-name=turn.aimatchem.com

fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=REPLACE_TURN_SECRET

no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1

verbose
log-file=/var/log/turnserver/turn.log

min-port=49152
max-port=65535

# ponytail: 生产可再收紧 IP 段
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
