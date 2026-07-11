import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// 客户端打字机效果（服务端暂无 SSE 时的体验补偿）
class TextReveal {
  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();

  void reveal({
    required String full,
    required void Function(String partial) onUpdate,
    VoidCallback? onDone,
    Duration interval = const Duration(milliseconds: 18),
  }) {
    cancel();
    if (full.isEmpty) {
      onUpdate('');
      onDone?.call();
      return;
    }
    final step = full.length > 800 ? 14 : (full.length > 300 ? 8 : 4);
    var pos = 0;
    _timer = Timer.periodic(interval, (t) {
      pos = min(pos + step, full.length);
      onUpdate(full.substring(0, pos));
      if (pos >= full.length) {
        t.cancel();
        _timer = null;
        onDone?.call();
      }
    });
  }
}
