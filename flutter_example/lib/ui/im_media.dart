import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../util/media_url.dart';
import '../util/open_file_url.dart';
import 'file_message.dart';

final _imageExtRe = RegExp(r'\.(jpg|jpeg|png|gif|webp)$', caseSensitive: false);

bool isImageFilename(String? name) => _imageExtRe.hasMatch((name ?? '').toLowerCase());

String? imageUrlFromMessage(dynamic m) {
  final ct = (m['contentType'] ?? '').toString();
  final c = (m['content'] ?? '').toString();
  if (ct == 'image') {
    if (c.startsWith('http')) return c;
    try {
      final j = jsonDecode(c);
      if (j is Map) {
        final url = (j['url'] ?? '').toString();
        if (url.startsWith('http')) return url;
      }
    } catch (_) {}
  }
  if (ct == 'file') {
    final file = tryParseFileMessage(c, contentType: ct);
    if (file != null && file.url.isNotEmpty && isImageFilename(file.name)) return file.url;
  }
  return null;
}

/// 点击图片全屏预览；多图时可左右滑动
void showImageViewer(
  BuildContext context,
  String url, {
  List<String>? urls,
  int initialIndex = 0,
}) {
  final list = (urls ?? [url]).map(publicMediaUrl).where((u) => u.isNotEmpty).toList();
  if (list.isEmpty) return;
  var idx = initialIndex;
  if (idx < 0 || idx >= list.length) idx = list.indexOf(publicMediaUrl(url));
  if (idx < 0) idx = 0;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ImageGalleryPage(urls: list, initialIndex: idx),
    ),
  );
}

class _ImageGalleryPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ImageGalleryPage({required this.urls, required this.initialIndex});

  @override
  State<_ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<_ImageGalleryPage> {
  late final PageController _pageCtrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.urls.length > 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.72),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          title: multi
              ? Text(
                  '${_index + 1} / ${widget.urls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                )
              : null,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Center(
                child: InteractiveViewer(
                  // ponytail: 禁单指平移，把左右滑留给 PageView 切图
                  panEnabled: false,
                  scaleEnabled: true,
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(
                    widget.urls[i],
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator(color: Colors.white70));
                    },
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
                  ),
                ),
              ),
            ),
            if (multi) ...[
              if (_index > 0)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryNavBtn(
                      icon: Icons.chevron_left,
                      onTap: () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    ),
                  ),
                ),
              if (_index < widget.urls.length - 1)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryNavBtn(
                      icon: Icons.chevron_right,
                      onTap: () => _pageCtrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GalleryNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GalleryNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class PickedImageBytes {
  final List<int> bytes;
  final String? name;
  const PickedImageBytes(this.bytes, {this.name});
}

Future<PickedImageBytes?> pickImageBytes() async {
  final list = await pickMultipleImageBytes(maxCount: 1);
  return list.isEmpty ? null : list.first;
}

Future<List<PickedImageBytes>> pickMultipleImageBytes({int maxCount = 9}) async {
  if (maxCount < 1) return const [];
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return const [];
    final out = <PickedImageBytes>[];
    for (final file in result.files) {
      if (out.length >= maxCount) break;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      out.add(PickedImageBytes(bytes, name: file.name));
    }
    if (out.isEmpty) throw Exception('无法读取图片，请换一张或缩小后重试');
    return out;
  } catch (e) {
    throw Exception('无法选择图片: $e');
  }
}

class PickedFileBytes {
  final List<int> bytes;
  final String? name;
  final int durationMs;
  final List<int>? waveform;
  const PickedFileBytes(this.bytes, {this.name, this.durationMs = 0, this.waveform});
}

Future<PickedFileBytes?> pickVideoBytes() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('无法读取视频');
    }
    return PickedFileBytes(bytes, name: file.name);
  } catch (e) {
    throw Exception('无法选择视频: $e');
  }
}

Future<PickedFileBytes?> pickFileBytes() async {
  try {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('无法读取文件');
    }
    return PickedFileBytes(bytes, name: file.name);
  } catch (e) {
    throw Exception('无法选择文件: $e');
  }
}

Future<void> openFileUrl(String url, {String? name}) async {
  final src = publicMediaUrl(url);
  if (src.isEmpty) return;
  await openRemoteFile(src, name: name);
}

bool isFileMessage(dynamic m) => (m['contentType'] ?? '').toString() == 'file';

bool isImageMessage(dynamic m) {
  final type = (m['contentType'] ?? '').toString();
  if (type == 'image') return true;
  final c = (m['content'] ?? '').toString();
  return c.startsWith('http') && RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false).hasMatch(c);
}

String messageSearchText(dynamic m) {
  final ct = (m['contentType'] ?? '').toString();
  final c = (m['content'] ?? '').toString();
  if (ct == 'file') {
    try {
      final j = jsonDecode(c);
      if (j is Map) return '${j['name'] ?? ''} ${j['url'] ?? ''}';
    } catch (_) {}
  }
  if (ct == 'voice' || ct == 'audio' || ct == 'video') {
    try {
      final j = jsonDecode(c);
      if (j is Map) return '${j['name'] ?? ''} ${j['url'] ?? ''}';
    } catch (_) {}
    return ct == 'video' ? '[视频]' : '[语音]';
  }
  return c;
}

List<dynamic> filterMessagesByQuery(List<dynamic> messages, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return messages;
  return messages.where((m) => messageSearchText(m).toLowerCase().contains(q)).toList();
}
