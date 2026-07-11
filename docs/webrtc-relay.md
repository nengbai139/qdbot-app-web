# WebRTC 独立服务

1:1 通话仍用 **IM 信令**（`call_signal`），媒体打洞/中继由独立服务提供。

## 组件

| 组件 | 作用 | 端口 |
|------|------|------|
| `qdbot-webrtc-relay` | 校验 App Token，签发临时 TURN 凭证 | `:8099` HTTP |
| `coturn` | STUN/TURN 媒体中继 | `3478` UDP/TCP，中继 `49152-65535` UDP |

## API

```http
GET /v1/ice-servers
Authorization: Bearer <app_token>
```

响应示例：

```json
{
  "ttl": 86400,
  "iceServers": [
    { "urls": ["stun:stun.l.google.com:19302"] },
    {
      "urls": [
        "turn:39.96.167.94:3478?transport=udp",
        "turn:39.96.167.94:3478?transport=tcp"
      ],
      "username": "1730000000:qdbot",
      "credential": "base64-hmac"
    }
  ]
}
```

## 部署

```bash
# 1. 生成共享密钥（relay 与 coturn 必须相同）
export WEBRTC_TURN_SECRET="$(openssl rand -hex 32)"

# 2. 上传二进制
bash deploy/webrtc/deploy.sh

# 3. SSH 到服务器安装
ssh baineng@39.96.167.94
export WEBRTC_TURN_SECRET='...'
sudo bash /opt/qdbot/webrtc/install.sh
```

## Nginx

```nginx
location /webrtc/ {
    proxy_pass http://127.0.0.1:8099/;
    proxy_set_header Authorization $http_authorization;
}
```

客户端默认请求：`https://www.aimatchem.com/webrtc/v1/ice-servers`

## 安全组 / 防火墙

- 入站：`3478` UDP+TCP
- 入站：`49152-65535` UDP（coturn relay）
- 出站：全开（或至少允许回连对端）

## 客户端配置

`lib/config.dart`：

- `QDBOT_WEBRTC_URL` — relay 根路径，默认 `https://www.aimatchem.com/webrtc`

## 与 SFU 的区别

当前方案是 **P2P + TURN 兜底**，适合 1:1。若要做群通话或多路转发，再升级为 LiveKit/mediasoup SFU。
