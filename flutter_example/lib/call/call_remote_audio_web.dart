import 'dart:js_interop';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

web.HTMLAudioElement? _remoteAudio;

/// ponytail: Web 上 RTCVideoView 的视频标签恒 muted；插件内 audio 元素 autoplay 常被拦，需显式 play()
Future<void> syncRemoteCallAudio(MediaStream? stream) async {
  if (stream == null) {
    stopRemoteCallAudio();
    return;
  }
  final tracks = stream.getAudioTracks();
  if (tracks.isEmpty) return;
  for (final t in tracks) {
    t.enabled = true;
  }

  final jsStream = (stream as dynamic).jsStream as web.MediaStream;
  final audioOnly = web.MediaStream();
  for (final t in jsStream.getAudioTracks().toDart) {
    audioOnly.addTrack(t);
  }

  _remoteAudio ??= web.HTMLAudioElement()
    ..id = 'qdbot_call_remote_audio'
    ..autoplay = true;
  _remoteAudio!
    ..muted = false
    ..srcObject = audioOnly;
  if (_remoteAudio!.parentElement == null) {
    web.document.body?.append(_remoteAudio!);
  }
  try {
    await _remoteAudio!.play().toDart;
  } catch (_) {}
}

void stopRemoteCallAudio() {
  _remoteAudio?.pause();
  _remoteAudio?.srcObject = null;
  _remoteAudio?.remove();
  _remoteAudio = null;
}
