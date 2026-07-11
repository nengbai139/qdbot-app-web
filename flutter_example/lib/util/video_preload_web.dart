import 'package:web/web.dart' as web;

import 'media_url.dart';
import 'vod_url.dart';

final _preloaded = <String>{};

/// ponytail: Web 用隐藏 video metadata 预加载，避免 link preload as=video 告警
void preloadVideoUrl(String url) {
  final href = publicMediaUrl(url);
  if (href.isEmpty || !isPlayableCircleVodUrl(href) || _preloaded.contains(href)) return;
  _preloaded.add(href);
  final video = web.document.createElement('video') as web.HTMLVideoElement
    ..preload = 'metadata'
    ..src = href
    ..muted = true
    ..style.display = 'none';
  web.document.body?.append(video);
}
