import 'dart:convert';

import '../util/file_mime.dart';
import '../util/voice_waveform.dart';

List<int>? _parseWaveformField(dynamic raw) {
  final list = parseWaveformList(raw);
  return list.isEmpty ? null : list;
}

class MediaAttachment {
  final String url;
  final int durationMs;
  final String? name;
  final int size;
  final String? poster;
  final List<int>? waveform;

  const MediaAttachment({
    required this.url,
    this.durationMs = 0,
    this.name,
    this.size = 0,
    this.poster,
    this.waveform,
  });
}

/// 识别 video 类型，或 file 类型里扩展名为视频的文件
MediaAttachment? tryParseVideoMessage(String content, {required String contentType}) {
  final ct = contentType.toLowerCase();
  if (ct == 'video') {
    return tryParseMediaMessage(content, contentType: ct, kinds: {'video'});
  }
  if (ct == 'file') {
    try {
      final j = jsonDecode(content);
      if (j is Map) {
        final name = (j['name'] ?? '').toString();
        if (isVideoFilename(name)) {
          return MediaAttachment(
            url: (j['url'] ?? '').toString(),
            name: name.isEmpty ? null : name,
            size: (j['size'] as num?)?.toInt() ?? 0,
            poster: (j['poster'] ?? '').toString().isEmpty ? null : (j['poster'] ?? '').toString(),
            waveform: _parseWaveformField(j['waveform']),
          );
        }
      }
    } catch (_) {}
  }
  return null;
}

MediaAttachment? tryParseMediaMessage(
  String content, {
  required String contentType,
  Set<String>? kinds,
}) {
  final ct = contentType.toLowerCase();
  if (kinds != null && !kinds.contains(ct)) return null;
  if (kinds == null && ct != 'voice' && ct != 'audio' && ct != 'video') return null;
  try {
    final j = jsonDecode(content);
    if (j is Map) {
      return MediaAttachment(
        url: (j['url'] ?? '').toString(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString().isEmpty ? null : (j['name'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        poster: (j['poster'] ?? '').toString().isEmpty ? null : (j['poster'] ?? '').toString(),
        waveform: _parseWaveformField(j['waveform']),
      );
    }
  } catch (_) {}
  if (content.startsWith('http')) {
    return MediaAttachment(url: content);
  }
  return null;
}

String encodeMediaMessage({
  required String url,
  int durationMs = 0,
  String? name,
  int size = 0,
  String? poster,
  List<int>? waveform,
}) =>
    jsonEncode({
      'url': url,
      if (durationMs > 0) 'durationMs': durationMs,
      if (name != null && name.isNotEmpty) 'name': name,
      if (size > 0) 'size': size,
      if (poster != null && poster.isNotEmpty) 'poster': poster,
      if (waveform != null && waveform.isNotEmpty) 'waveform': waveform,
    });

String formatDurationMs(int ms) {
  if (ms <= 0) return '0:00';
  final totalSec = (ms / 1000).round();
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

bool isCallSignalMessage(dynamic m) => (m['contentType'] ?? '').toString() == 'call_signal';

bool isHiddenImMessage(dynamic m) => isCallSignalMessage(m);
