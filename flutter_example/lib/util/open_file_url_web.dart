import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'file_mime.dart';
import 'media_actions_web.dart';
import 'save_bytes_web.dart';

Future<void> openFileUrlImpl(String src, {String? name}) async {
  final filename = (name != null && name.isNotEmpty) ? name : 'download';
  if (isVideoFilename(filename)) {
    downloadMediaUrl(src, filename);
    return;
  }
  if (isAudioFilename(filename)) {
    try {
      final resp = await http.get(Uri.parse(src));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        await saveBytesAsFile(Uint8List.fromList(resp.bodyBytes), filename);
        return;
      }
    } catch (_) {}
    downloadMediaUrl(src, filename);
    return;
  }
  if (fileViewableInBrowser(filename)) {
    openUrlInNewTab(src);
    return;
  }
  // ponytail: 小文件走 blob 下载；大文件同源直链
  final head = await http.head(Uri.parse(src));
  final len = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
  if (len > 0 && len <= 8 * 1024 * 1024) {
    final resp = await http.get(Uri.parse(src));
    if (resp.statusCode != 200) throw Exception('下载失败 (${resp.statusCode})');
    await saveBytesAsFile(Uint8List.fromList(resp.bodyBytes), filename);
    return;
  }
  downloadMediaUrl(src, filename);
}
