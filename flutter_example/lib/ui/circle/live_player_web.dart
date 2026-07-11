import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('qdbotAttachLiveHls')
external void _attachLiveHls(web.HTMLVideoElement video, String url);

@JS('qdbotDetachLiveHls')
external void _detachLiveHls(web.HTMLVideoElement video);

class LivePlayer extends StatefulWidget {
  final String url;

  const LivePlayer({super.key, required this.url});

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> {
  late final String _viewType;
  web.HTMLVideoElement? _video;

  @override
  void initState() {
    super.initState();
    // ponytail: viewType 与 State 绑定，重建时由父级 ValueKey 保活，避免误拆 HLS
    _viewType = 'qdbot-live-${widget.url.hashCode}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..controls = false
        ..autoplay = true
        ..playsInline = true
        ..muted = false
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.backgroundColor = 'transparent';
      _video = video;
      _attachLiveHls(video, widget.url);
      return video;
    });
  }

  @override
  void dispose() {
    final video = _video;
    if (video != null) _detachLiveHls(video);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
