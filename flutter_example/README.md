# Flutter Integration Example

Flutter 客户端示例 — **直连 qdbot_system**（产品主路径）。

> 架构决策见 [../docs/ADR-001-integration-route.md](../docs/ADR-001-integration-route.md)

## Architecture

```
┌─────────────────────────────────────────┐
│           Flutter UI (Dart)              │
│  http · web_socket_channel · UI pages   │
└───────────────────┬─────────────────────┘
                    │ HTTPS / WSS
                    ▼
┌─────────────────────────────────────────┐
│  qdbot_system (aimatchem.com)           │
│  /app/auth/*  /app/im/*  /app/ai/*      │
└─────────────────────────────────────────┘

Go SDK (cmd/app) — CLI/测试辅助，Flutter 不依赖
```

## 统一路径

| 能力 | API |
|------|-----|
| 登录 | `POST /app/auth/login` |
| IM 发送 | `POST /app/im/send` |
| IM 实时 | `WSS /ws/app/connect?token=...` |
| AI 对话 | `POST /app/ai/send` |

**不使用** Go bridge FFI，**不使用**客户端直连 LLM；AI 统一走服务端智能体。

## Quick Start

```bash
cd flutter_example
flutter pub get
flutter run
```

配置服务端地址：`lib/config.dart`（可用 `--dart-define=QDBOT_BASE_URL=...` 覆盖）。

## Dependencies

- `http` — REST API
- `web_socket_channel` — 实时消息
- `flutter_markdown` — AI/IM Markdown 气泡

## Go bridge（experimental）

`cmd/app/flutter_bridge.go` 为实验性进程内 API，无 FFI 绑定，**不在本示例中使用**。见 ADR-001。


## 目录结构

```
lib/
├── main.dart           # App 入口
├── config.dart         # 服务端地址
├── session.dart        # Token 持久化
├── api/                # REST 封装
├── ws/ws_client.dart   # WebSocket + 重连
└── ui/                 # 页面
    ├── login_page.dart
    ├── home_page.dart
    ├── im_chats_tab.dart
    ├── chat_page.dart
    ├── group_chat_page.dart
    ├── ai_chats_tab.dart
    ├── ai_chat_page.dart
    └── profile_tab.dart
```
