import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'file_mime.dart';
import 'media_actions_web.dart';
import 'media_url.dart';
import 'save_bytes_web.dart';

web.HTMLAudioElement? _audio;
String? _objectUrl;
String? _playingSrc;
void Function()? _onStateChanged;

void bindPlatformPlaybackEvents(void Function() fn) {
  _onStateChanged = fn;
}

void _emit() => _onStateChanged?.call();

String? platformPlayingUrl() {
  final a = _audio;
  if (a == null || a.paused) return null;
  return _playingSrc;
}

Future<void> _release() async {
  _audio?.pause();
  _audio?.onended = null;
  _audio = null;
  _playingSrc = null;
  if (_objectUrl != null) {
    web.URL.revokeObjectURL(_objectUrl!);
    _objectUrl = null;
  }
}

String _resolveFilename(String src, String? filename) {
  if (filename != null && filename.isNotEmpty) return filename;
  final path = Uri.tryParse(src)?.path ?? '';
  final base = path.split('/').last;
  if (base.contains('.')) return base;
  return 'voice.webm';
}

/// 旧版上传误存为 .jpg 时，仍按消息里的文件名/魔数推断音频 MIME。
String _mimeForVoiceBytes(String filename, Uint8List bytes) {
  final fromName = mimeForFilename(filename);
  if (fromName.startsWith('audio/')) return fromName;
  if (bytes.length >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
    return 'audio/webm';
  }
  if (bytes.length >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
    return 'audio/mp4';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xFB) return 'audio/mpeg';
  return 'audio/webm';
}

Future<void> _playBlob(Uint8List bytes, String mime) async {
  final blobParts = ([bytes.toJS].toJS) as JSArray<web.BlobPart>;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mime));
  _objectUrl = web.URL.createObjectURL(blob);
  final audio = web.document.createElement('audio') as web.HTMLAudioElement..src = _objectUrl!;
  audio.onended = ((web.Event _) {
    _release().then((_) => _emit());
  }).toJS;
  _audio = audio;
  await audio.play().toDart;
}

Future<void> platformToggle(String src, {String? filename}) async {
  final norm = publicMediaUrl(src);
  if (norm.isEmpty) throw Exception('语音地址无效');
  if (_playingSrc == norm && _audio != null && !_audio!.paused) {
    _audio!.pause();
    _emit();
    return;
  }
  await _release();

  final name = _resolveFilename(norm, filename);
  _playingSrc = norm;

  // 新上传（正确扩展名/Content-Type）可直接播；旧 .jpg 误标走 blob 兜底
  final path = Uri.tryParse(norm)?.path.toLowerCase() ?? '';
  final likelyLegacy = path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');

  if (!likelyLegacy) {
    try {
      final audio = web.document.createElement('audio') as web.HTMLAudioElement..src = norm;
      audio.onended = ((web.Event _) {
        _release().then((_) => _emit());
      }).toJS;
      _audio = audio;
      await audio.play().toDart;
      _emit();
      return;
    } catch (_) {
      await _release();
      _playingSrc = norm;
    }
  }

  final resp = await http.get(Uri.parse(norm));
  if (resp.statusCode != 200) {
    await _release();
    throw Exception('加载语音失败 (${resp.statusCode})');
  }
  final bytes = Uint8List.fromList(resp.bodyBytes);
  if (bytes.isEmpty) {
    await _release();
    throw Exception('语音文件为空');
  }
  final mime = _mimeForVoiceBytes(name, bytes);
  try {
    await _playBlob(bytes, mime);
    _emit();
  } catch (e) {
    await _release();
    throw Exception('无法播放语音: $e');
  }
}

Future<void> platformStopAll() async {
  await _release();
  _emit();
}

Future<void> platformDownload(String src, {String? filename}) async {
  final norm = publicMediaUrl(src);
  final name = _resolveFilename(norm, filename);
  try {
    final resp = await http.get(Uri.parse(norm));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      await saveBytesAsFile(Uint8List.fromList(resp.bodyBytes), name);
      return;
    }
  } catch (_) {}
  downloadMediaUrl(norm, name);
}
