import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:web/web.dart' as web;

@JS('qdbotWrapVirtualBg')
external JSPromise<JSObject> _wrapVirtualBg(JSAny cameraStream, String backdropUrl);

/// ponytail: 复用 WHIP 同款 MediaPipe 合成，经 LiveKit TrackProcessor 推流
class QdbotVirtualBgProcessor extends TrackProcessor<VideoProcessorOptions> {
  QdbotVirtualBgProcessor(this.backdropUrl);

  final String backdropUrl;
  MediaStreamTrack? _processed;
  JSFunction? _vbgStop;

  @override
  String get name => 'qdbot-virtual-bg';

  @override
  MediaStreamTrack? get processedTrack => _processed;

  @override
  Future<void> init(VideoProcessorOptions options) => _apply(options.track);

  @override
  Future<void> restart(VideoProcessorOptions options) async {
    await destroy();
    await _apply(options.track);
  }

  Future<void> _apply(MediaStreamTrack track) async {
    final url = backdropUrl.trim();
    if (url.isEmpty || track is! MediaStreamTrackWeb) {
      _processed = track;
      return;
    }
    try {
      final cam = web.MediaStream();
      cam.addTrack(track.jsTrack);
      final r = await _wrapVirtualBg(cam as JSAny, url).toDart;
      final streamObj = r.getProperty('stream'.toJS);
      if (streamObj == null) {
        _processed = track;
        return;
      }
      final jsStream = web.MediaStream(streamObj as JSObject);
      final vts = jsStream.getVideoTracks().toDart;
      if (vts.isEmpty) {
        _processed = track;
        return;
      }
      _processed = MediaStreamTrackWeb(vts.first);
      final stopFn = r.getProperty('stop'.toJS);
      _vbgStop = stopFn is JSFunction ? stopFn : null;
    } catch (_) {
      _processed = track;
    }
  }

  @override
  Future<void> destroy() async {
    try {
      _vbgStop?.callAsFunction();
    } catch (_) {}
    _vbgStop = null;
    _processed = null;
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}
}

TrackProcessor<VideoProcessorOptions>? meetingVirtualBgProcessor(String backdropUrl) {
  if (backdropUrl.trim().isEmpty) return null;
  return QdbotVirtualBgProcessor(backdropUrl);
}
