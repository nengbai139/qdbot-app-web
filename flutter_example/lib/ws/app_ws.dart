import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ws_client.dart';

/// ponytail: 全局 WS，HomePage 重建时不 dispose，避免 Safari 断连→重建→13 API 风暴
class AppWs {
  AppWs._();

  static WsClient? _client;
  static String? _token;
  static final _messages = StreamController<Map<String, dynamic>>.broadcast();
  static final connected = ValueNotifier(true);

  static Stream<Map<String, dynamic>> get messages => _messages.stream;

  static void ensureStarted(String token) {
    if (_client != null && _token == token) return;
    stop();
    _token = token;
    _client = WsClient(
      token: token,
      onConnectionChange: (c) {
        if (connected.value != c) connected.value = c;
      },
      onMessage: _messages.add,
    )..connect();
  }

  static void stop() {
    _client?.dispose();
    _client = null;
    _token = null;
    connected.value = true;
  }
}
