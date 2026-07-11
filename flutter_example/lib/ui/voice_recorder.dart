import 'dart:async';

import 'im_media.dart';

/// 平台录音后端（Web 用原生 MediaRecorder，移动端用 record 包）
abstract class VoiceRecorderBackend {
  Future<void> start();
  Future<PickedFileBytes?> stop({required int durationMs});
  Future<void> cancel();
  void dispose();

  /// 录音时实时音量 0..1，用于面板波形动画。
  Stream<double>? get levelStream;
}
