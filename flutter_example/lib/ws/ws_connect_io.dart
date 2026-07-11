import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ponytail: pingInterval=10s 让 Dart 底层发协议层 ping，辅助 iOS 保持 TCP 连接
WebSocketChannel connectWs(Uri uri) => IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 10));
