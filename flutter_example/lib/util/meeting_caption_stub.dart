import 'dart:async';

typedef MeetingCaptionCallback = void Function(String text, bool isFinal, {String? error});

/// 非 Web 平台暂无实时 STT
class MeetingCaptionEngine {
  String? start({String lang = 'zh-CN', MeetingCaptionCallback? onResult}) => '仅网页版支持实时字幕';

  void stop() {}

  bool get running => false;
}
