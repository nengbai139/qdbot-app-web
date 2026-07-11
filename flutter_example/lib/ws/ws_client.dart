import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../util/web_notify.dart';
import 'ws_connect.dart';

/// WebSocket 客户端：指数退避重连（1s → 30s，与 Go ReconnectContext 一致）
class WsClient {
  WsClient({
    required this.token,
    required this.onMessage,
    this.onConnectionChange,
  });

  final String token;
  final void Function(Map<String, dynamic> msg) onMessage;
  final void Function(bool connected)? onConnectionChange;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  var _attempt = 0;
  var _disposed = false;
  var _connected = false;
  var _connecting = false;
  var _connectGen = 0;

  bool get isConnected => _connected;

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChange?.call(value);
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void connect() {
    if (_disposed || _connecting) return;
    // ponytail: 已有活跃连接时不重复 connect，避免 iOS 上 register/unregister 双连接竞态
    if (_connected && _channel != null) return;
    _reconnectTimer?.cancel();
    _connecting = true;
    final gen = ++_connectGen;
    _closeChannel();
    try {
      final uri = Uri.parse(AppConfig.wsConnectUrl(token));
      _channel = connectWs(uri);
      _sub = _channel!.stream.listen(
        (data) {
          if (gen != _connectGen) return;
          if (!_connected) {
            _setConnected(true);
          }
          _attempt = 0; // 每次收到数据重置重试计数，保持重连快速
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final t = (msg['type'] ?? '').toString();
            if (t == 'heartbeat' || t == 'pong') return;
            onMessage(msg);
          } catch (_) {}
        },
        onError: (_) {
          if (gen != _connectGen) return;
          _connecting = false;
          _setConnected(false);
          _closeChannel();
          _scheduleReconnect();
        },
        onDone: () {
          if (gen != _connectGen) return;
          _connecting = false;
          _setConnected(false);
          _closeChannel();
          if (!_disposed) _scheduleReconnect();
        },
        cancelOnError: true,
      );
      _connecting = false;
      _startPing();
    } catch (_) {
      if (gen != _connectGen) return;
      _connecting = false;
      _setConnected(false);
      _closeChannel();
      _scheduleReconnect();
    }
  }

  void _startPing() {
    // ponytail: iOS 保活主力由 stream listener 中对 heartbeat/pong 回复 ping 完成
    // 此处仅非 web 平台额外 15s 定时 ping 作兜底
    _pingTimer?.cancel();
    if (kIsWeb) return; // web 完全靠 heartbeat 触发回复，不用定时器
    void sendPing() {
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000}));
      } catch (_) {}
    }
    sendPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => sendPing());
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // ponytail: iOS Safari 断连频繁，页面隐藏时快速重试而非无限等待
    if (kIsWeb && webDocumentHidden()) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 1), _scheduleReconnect);
      return;
    }
    _reconnectTimer?.cancel();
    // ponytail: 断连后快速重连（1s 初试，最大 10s），减少用户感知
    final secs = max(1, min(10, _attempt));
    _attempt = min(_attempt + 1, 10);
    _reconnectTimer = Timer(Duration(seconds: secs), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _closeChannel();
    _setConnected(false);
  }
}
