import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../util/media_url.dart';
import 'media_actions_web.dart';

Future<void> showVideoViewerImpl(BuildContext context, String src, {String? name}) async {
  final url = publicMediaUrl(src);
  if (url.isEmpty) throw Exception('视频地址无效');
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _WebVideoPage(src: url, filename: name ?? 'video.mp4')),
  );
}

Future<void> downloadVideoImpl(String src, {String? name}) async {
  final url = publicMediaUrl(src);
  if (url.isEmpty) throw Exception('视频地址无效');
  downloadMediaUrl(url, (name != null && name.isNotEmpty) ? name : 'video.mp4');
}

class _WebVideoPage extends StatefulWidget {
  final String src;
  final String filename;
  const _WebVideoPage({required this.src, required this.filename});

  @override
  State<_WebVideoPage> createState() => _WebVideoPageState();
}

class _WebVideoPageState extends State<_WebVideoPage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'qdbot-video-${widget.src.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..src = widget.src
        ..controls = true
        ..autoplay = true
        ..playsInline = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'black';
      video.addEventListener(
        'click',
        ((web.Event _) {
          video.muted = false;
        }).toJS,
      );
      return video;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.filename, style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            tooltip: '下载',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => downloadMediaUrl(widget.src, widget.filename),
          ),
          IconButton(
            tooltip: '新标签页打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openUrlInNewTab(widget.src),
          ),
        ],
      ),
      body: HtmlElementView(viewType: _viewType),
    );
  }
}
