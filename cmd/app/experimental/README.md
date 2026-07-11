# Experimental: Flutter Bridge

**状态：frozen** — 不在产品路线中，无 FFI/gomobile 绑定。

## 说明

`../flutter_bridge.go` 提供进程内 Go API，供早期 FFI 集成实验使用。
正式 Flutter 客户端应 **直连 qdbot_system**（见 `flutter_example/`）。

## 运行（仅调试）

```bash
QDBOT_EMAIL=user@example.com QDBOT_PASSWORD=xxx go run ./cmd/app/ -flutter
```

## 不提供

- gomobile / dart:ffi 绑定
- 与 Flutter 示例的 API 对齐保证
- 产品级维护

升级路径见 [ADR-001](../../docs/ADR-001-integration-route.md)。
