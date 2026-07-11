import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// 网页推流本地预览（video#qdbot-whip-preview，由 WHIP JS 写入画面）
class LiveWhipPreview extends StatefulWidget {
  const LiveWhipPreview({super.key});

  @override
  State<LiveWhipPreview> createState() => _LiveWhipPreviewState();
}

class _LiveWhipPreviewState extends State<LiveWhipPreview> {
  static bool _registered = false;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'qdbot-whip-preview-view';
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        final video = web.document.createElement('video') as web.HTMLVideoElement
          ..id = 'qdbot-whip-preview'
          ..autoplay = true
          ..muted = true
          ..playsInline = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.backgroundColor = 'transparent';
        return video;
      });
      _registered = true;
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
