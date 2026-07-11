# ADR-001: 客户端集成路线与 AI/认证统一

**状态**: 已采纳  
**日期**: 2026-07-01  
**决策者**: qdbot_app 团队

---

## 背景

当前存在两条并行、未收敛的客户端路径：

| 路径 | 现状 |
|------|------|
| **Flutter 直连** | `flutter_example` 通过 HTTP/WS 直连 `qdbot_system`，功能最完整（认证、IM、群聊、AI、数字分身） |
| **Go bridge** | `cmd/app/flutter_bridge.go` 为进程内 API，无 FFI/gomobile 绑定，Flutter 未调用 |
| **Go CLI** | 依赖 `QDBOT_APP_TOKEN` 环境变量，无登录流程 |

AI 统一走 qdbot_system **`/app/ai/*` REST**（Flutter 已实现）。

---

## 决策

### 1. 集成路线：**Flutter 直连 qdbot_system 为主路径**

```
┌──────────────────────────────────────────────────────────────┐
│  flutter_example（及未来正式 App）                             │
│  Dart: ApiClient + WsClient + UI                             │
└───────────────────────────┬──────────────────────────────────┘
                            │ HTTPS / WSS
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  qdbot_system (https://www.aimatchem.com)                    │
│  认证 · IM · 群聊 · AI 编排 · 推送                           │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Go SDK (cmd/app) — 辅助角色，非 Flutter 运行时依赖           │
│  CLI 调试 · 自动化测试 · 可选 headless 守护进程               │
└──────────────────────────────────────────────────────────────┘
```

**不选 Go bridge 作为主路径的理由：**

1. Flutter 示例已覆盖 20+ 服务端 API，bridge 仅封装其中一小部分
2. bridge 无 FFI 绑定，接入成本高（iOS/Android 编译链、Web 不可用）
3. 业务逻辑以服务端为准，客户端应保持薄层（YAGNI）
4. Flutter Web 是目标平台之一，直连天然支持

**Go SDK 保留用途：**

- `go run ./cmd/app/` — 开发/联调 CLI
- CI 集成测试、脚本化 IM 操作
- 未来若需 **离线缓存 sidecar**，再评估独立本地进程（HTTP localhost），而非 FFI

**Go bridge 处置：**

- 标记为 **experimental / frozen**，不继续投入
- 不在 Flutter 产品路线中依赖 `-flutter` 模式
- 若将来有「必须在 Go 中跑的逻辑」（加密、重计算），再开 ADR-002 评估 sidecar 或 FFI

---

### 2. 认证统一：**唯一入口 `/app/auth/*`**

所有客户端（Flutter、Go CLI、未来原生 App）必须通过 qdbot_system 认证，禁止各端自行发明 token 来源。

#### 标准流程

```
1. POST /app/auth/login          → { token, userId, userCode, ... }
2. POST /app/auth/register       → 注册（含 tenant/business/device 等扩展字段）
3. POST /app/auth/verification/send-code  → 验证码
4. 所有 REST: Authorization: Bearer <token>
5. WebSocket: wss://.../ws/app/connect?token=<token>
```

#### 各端职责

| 端 | 认证方式 | Token 存储 |
|----|----------|------------|
| **Flutter** | `/app/auth/login`（已实现） | 内存 + 后续 `flutter_secure_storage` |
| **Go CLI** | 新增 `client.Login()` 调同一 API | `storage` 持久化 token 文件 |
| **Go bridge** | 不用于产品；若调试则传入 token | N/A |

#### 废弃/禁止

- ❌ CLI 主路径依赖 `QDBOT_APP_TOKEN` 环境变量（保留为 CI/调试 override）
- ❌ 客户端本地签发或硬编码 token
- ❌ README 中 `userId` 登录示例（与实际 `email+password` 不一致）

---

### 3. AI 统一：**唯一产品路径 `/app/ai/*` REST**

AI 推理、模型选择、API Key 管理均在 **qdbot_system 服务端**完成；客户端只负责对话 UI 与消息同步。

#### 标准 API

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/app/ai/conversations` | 对话列表 |
| GET | `/app/ai/conversations/{convId}/messages` | 历史消息 |
| POST | `/app/ai/send` | 发送（body: `{ convId?, content, contentType }`） |

#### 实时更新

- **发送**：`POST /app/ai/send`（同步返回或 partial response）
- **推送**：WebSocket 消息带 `convId` 字段时刷新对应对话（Flutter 已实现）
- **轮询**：仅作 WS 不可用时的 fallback，目标间隔 ≥5s 或可配置关闭

#### 废弃/禁止

| 路径 | 处置 |
|------|------|
| 客户端直连 LLM（DeepSeek 等） | **已删除**，统一 `/app/ai/send` |
| WebSocket `ai_chat` 发送 | **已删除**，AI 写操作仅 REST |

---

### 4. WebSocket 职责边界

WebSocket **只负责实时事件**，不负责业务写操作的主路径：

| 事件 type | 用途 | 写操作是否走 WS |
|-----------|------|----------------|
| `im` | 单聊/群聊新消息 | 否，发送走 `POST /app/im/send` |
| `im_revoke` | 消息撤回通知 | 否，撤回走 `POST /app/im/revoke/{msgId}` |
| `*` + `convId` | AI 对话更新通知 | 否，发送走 `POST /app/ai/send` |

---

## 目标架构（Flutter）

```
flutter_example/lib/
├── config.dart          # baseUrl, wsUrl（单一配置源）
├── api/
│   ├── auth_api.dart    # /app/auth/*
│   ├── im_api.dart      # /app/im/*
│   ├── ai_api.dart      # /app/ai/*
│   └── bot_api.dart     # /app/im/bot/*
├── ws/
│   └── ws_client.dart   # 连接、重连、事件分发
└── ui/                  # 页面（从 main.dart 拆出）
```

Go SDK 镜像同一 API 面（`client/auth.go`, `client/ai.go` 等），供 CLI 与测试使用，**不**被 Flutter import。

---

## 迁移步骤（按优先级）

### Phase 0 — 文档与标记（本 ADR）

- [x] 确定集成路线
- [x] README / flutter_example README 与 ADR 对齐
- [x] bridge / 本地 AI 加 deprecation 注释

### Phase 1 — Flutter 收敛

- [x] 抽 `config.dart`，消除硬编码 URL
- [x] 抽 `AuthApi` / `ImApi` / `AiApi` / `BotApi`
- [x] AI 页去掉 2s 轮询，优先 WS `convId` 事件
- [x] Token 存 `flutter_secure_storage`

### Phase 2 — Go SDK 对齐

- [x] `client/ai.go`: SendAI, ListAIConversations, GetAIMessages
- [x] `client/auth.go`: Login, Register, SendVerificationCode
- [x] CLI 启动：token 优先级 env → storage → email/password 登录
- [x] `chat.Service.SendMessage` 调 `APIClient.SendIM`

### Phase 3 — 清理

- [x] 移除本地 DeepSeek（`internal/chat/ai.go`）
- [x] bridge 标记 experimental（`cmd/app/experimental/README.md`）
- [x] Go client 群聊高级 API + BotConfig（`client/im_group.go`, `client/bot.go`）

### Phase 4 — CLI 与 UX polish

- [x] Flutter UI 拆分至 `lib/ui/`，API 层 `lib/api/`
- [x] Session 自动登录 + 记住邮箱/platform
- [x] WebSocket 指数退避重连（Flutter `WsClient` + Go `ReconnectContext`）
- [x] Go CLI 交互式登录（TTY stdin）
- [x] Go CLI 子命令：`send` / `ai` / `sessions` / `groups` / `conversations` / `unread` / `help`
- [x] `send -group` 群聊发送
- [x] Flutter 断线横幅提示

#### Go CLI 参考

```bash
# 守护进程
go run ./cmd/app/

# 单聊
go run ./cmd/app/ send -to user_002 -m "Hello"

# 群聊
go run ./cmd/app/ send -group grp_xxx -m "Hi everyone"

# AI 智能体
go run ./cmd/app/ ai -m "你好"
go run ./cmd/app/ ai -conv conv_xxx -m "继续"

# 会话列表
go run ./cmd/app/ sessions

# 群列表
go run ./cmd/app/ groups

# AI 对话列表
go run ./cmd/app/ conversations

# 未读数
go run ./cmd/app/ unread

go run ./cmd/app/ help
```

认证优先级：`QDBOT_APP_TOKEN` → `storage/auth_token.json` → `QDBOT_EMAIL`+`QDBOT_PASSWORD` → 交互输入。

---

## 后果

**正面：**

- 单一真相源（qdbot_system），减少三轨 AI、双轨认证的 bug 面
- Flutter 可独立迭代 UI，不阻塞 Go 编译链
- Go SDK 聚焦 CLI/测试，职责清晰

**负面 / 风险：**

- Dart 与 Go 存在 API 封装重复 → 以 OpenAPI/服务端文档为契约，Go 侧 generated client 可后续引入
- 离线能力弱 → 若产品需要，Phase 3+ 再开 sidecar ADR

---

## 参考

- Flutter 实际调用：`flutter_example/lib/api/`, `lib/ws/ws_client.dart`, `lib/ui/`
- Go REST 封装：`client/api.go`
- 服务端部署：`configs/config.yaml` → `https://www.aimatchem.com`
