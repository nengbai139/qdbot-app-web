# QDBot App

QDBot App 客户端 SDK - 支持 iOS/Android/Pad/Web 跨平台即时通讯和 AI 智能助手

## 项目状态

✅ **已完成** - 基础功能 + 测试 + 部署

## 功能

- [x] WebSocket 客户端
- [x] 推送通知客户端 (FCM/APNs)
- [x] 会话管理
- [x] 消息处理
- [x] AI 智能体对话（服务端 `/app/ai/*`）
- [x] Flutter 集成示例

## 服务部署

qdbot_system 已部署在: **https://www.aimatchem.com**

### API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /app/auth/login | 用户登录 |
| POST | /app/im/send | 发送消息 |
| GET | /app/im/messages | 获取消息历史 |
| GET | /app/im/sessions | 会话列表 |
| GET | /app/im/unread | 未读数 |
| POST | /app/im/read | 标记已读 |
| POST | /app/im/group/create | 创建群组 |
| GET | /app/ai/conversations | AI 对话列表 |
| POST | /app/ai/send | 发送 AI 消息（智能体） |

### 登录示例

```bash
curl -X POST https://www.aimatchem.com/app/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"your_password","deviceId":"device_001","platform":"ios"}'
```

### 发送消息示例

```bash
curl -X POST https://www.aimatchem.com/app/im/send \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"toUserId":"user_002","content":"Hello!","contentType":"text"}'
```

## 快速开始

```bash
# 1. 下载依赖
go mod tidy

# 2. 配置（编辑 qdbot_system.url 等）
vim configs/config.yaml

# 3. 运行 CLI（需认证，任选其一）
#    QDBOT_APP_TOKEN=<token>
#    QDBOT_EMAIL + QDBOT_PASSWORD（自动登录并缓存 token）
#    交互式：直接 go run，终端提示输入邮箱/密码
go run ./cmd/app/

# 调试子命令
go run ./cmd/app/ send -to user_002 -m "Hello"
go run ./cmd/app/ send -group GROUP_ID -m "Hi group"
go run ./cmd/app/ ai -m "你好"
go run ./cmd/app/ ai -conv CONV_ID -m "继续"
go run ./cmd/app/ sessions
go run ./cmd/app/ groups
go run ./cmd/app/ conversations
go run ./cmd/app/ unread
go run ./cmd/app/ help

# 4. 测试
go test ./... -cover
```

## 目录结构

```
qdbot_app/
├── cmd/app/main.go         # 主程序入口
├── client/                  # 客户端 SDK
│   ├── api.go             # REST API 客户端 (IM)
│   ├── ai.go              # REST API 客户端 (AI 智能体)
│   ├── auth.go            # 登录 / 注册
│   ├── im_group.go        # 群聊高级 API
│   ├── bot.go             # AI 数字分身配置
│   ├── websocket.go        # WebSocket 客户端
│   └── push.go            # FCM/APNs 推送
├── internal/
│   ├── app/               # 核心应用
│   │   ├── platform.go    # 平台检测
│   │   ├── session.go     # 会话管理
│   │   └── storage.go     # 本地存储
│   └── chat/              # 聊天功能
│       └── message.go     # 消息处理
├── cmd/app/flutter_bridge.go  # Flutter 桥接（experimental/frozen）
│   └── experimental/README.md # bridge 说明
├── flutter_example/       # Flutter 示例
├── configs/config.yaml    # 配置文件
└── go.mod
```

## 集成路线

> 详见 [docs/ADR-001-integration-route.md](docs/ADR-001-integration-route.md)

**结论：Flutter 直连 qdbot_system 为主路径；Go SDK 供 CLI/测试，不作为 Flutter 运行时依赖。**

| 能力 | 产品路径 | 说明 |
|------|----------|------|
| 认证 | `POST /app/auth/login` | 全端统一，Bearer Token |
| IM | REST 写 + WS 收 | 发送走 `/app/im/send`，实时走 WS |
| AI | `POST /app/ai/send` | 统一走 qdbot_system AI 智能体 |
| Go bridge | experimental | 无 FFI 绑定，不在产品路线中 |

## Flutter 示例

`flutter_example/` 直连云端 API，结构见 [flutter_example/README.md](flutter_example/README.md)。

```dart
import 'api/auth_api.dart';
import 'api/im_api.dart';
import 'api/ai_api.dart';
import 'config.dart';
import 'ws/ws_client.dart';

// 登录
final auth = AuthApi();
final resp = await auth.login(email: email, password: password, deviceId: deviceId, platform: 'ios');

// WebSocket 实时消息（指数退避重连）
final ws = WsClient(token: token, onMessage: (msg) { ... })..connect();

// 发送 IM / AI
await ImApi(token).send(toUserId: peerId, content: 'Hello');
await AiApi(token).send(content: '你好');
```

## 测试覆盖率

```
client/api_test.go            9 tests
client/ai_test.go             3 tests
client/websocket_test.go     15 tests
internal/app/platform_test.go 8 tests
internal/app/storage_test.go 10 tests
internal/chat/message_test.go 16 tests
```

## 依赖

- Go 1.22+
- gorilla/websocket
- spf13/viper
- qdbot_system (服务端: https://www.aimatchem.com)
