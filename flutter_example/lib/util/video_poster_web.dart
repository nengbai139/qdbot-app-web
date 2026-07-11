import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_mime.dart';

Future<Uint8List?> captureVideoPosterJpeg(List<int> bytes, {String? filename}) async {
  if (bytes.isEmpty) return null;
  final mime = mimeForFilename(filename ?? 'video.mp4');
  final u8 = Uint8List.fromList(bytes);
  final blobParts = ([u8.toJS].toJS) as JSArray<web.BlobPart>;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mime));
  final objUrl = web.URL.createObjectURL(blob);
  try {
    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..src = objUrl
      ..muted = true
      ..playsInline = true
      ..preload = 'auto';
    await _waitVideoEvent(video, 'loadeddata', const Duration(seconds: 10));
    if (video.videoWidth == 0 || video.videoHeight == 0) return null;
    video.currentTime = 0.08;
    await _waitVideoEvent(video, 'seeked', const Duration(seconds: 5));
    const maxW = 320.0;
    final scale = video.videoWidth > maxW ? maxW / video.videoWidth : 1.0;
    final cw = (video.videoWidth * scale).round().clamp(1, 640);
    final ch = (video.videoHeight * scale).round().clamp(1, 360);
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = cw
      ..height = ch;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(video, 0, 0, cw.toDouble(), ch.toDouble());
    final dataUrl = canvas.toDataURL('image/jpeg', 0.82.toJS);
    return _dataUrlToBytes(dataUrl);
  } catch (_) {
    return null;
  } finally {
    web.URL.revokeObjectURL(objUrl);
  }
}

Future<void> _waitVideoEvent(web.HTMLVideoElement video, String type, Duration timeout) {
  final c = Completer<void>();
  late JSFunction handler;
  handler = ((web.Event _) {
    video.removeEventListener(type, handler);
    if (!c.isCompleted) c.complete();
  }).toJS;
  video.addEventListener(type, handler);
  return c.future.timeout(timeout, onTimeout: () {
    video.removeEventListener(type, handler);
  });
}

Uint8List? _dataUrlToBytes(String dataUrl) {
  final i = dataUrl.indexOf(',');
  if (i < 0) return null;
  try {
    return base64Decode(dataUrl.substring(i + 1));
  } catch (_) {
    return null;
  }
}
