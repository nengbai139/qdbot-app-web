import 'dart:async';

/// ponytail: 全局 IM/AI 消息广播，HomePage 重建时不 close，避免聊天页 WS 断流
class AppMsgBus {
  AppMsgBus._();

  static final im = StreamController<Map<String, dynamic>>.broadcast();
  static final ai = StreamController<Map<String, dynamic>>.broadcast();

  static void publishIm(Map<String, dynamic> msg) {
    if (!im.isClosed) im.add(msg);
  }

  static void publishAi(Map<String, dynamic> msg) {
    if (!ai.isClosed) ai.add(msg);
  }
}
