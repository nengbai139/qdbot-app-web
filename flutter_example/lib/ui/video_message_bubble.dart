import 'package:flutter/material.dart';

import '../util/media_url.dart';
import 'media_message.dart';
import 'video_bubble_thumb.dart';

/// 视频气泡：封面图 + 首帧预览，点击再进播放器
class VideoMessageBubble extends StatelessWidget {
  final MediaAttachment media;
  final bool isMe;
  final VoidCallback? onTap;

  const VideoMessageBubble({super.key, required this.media, required this.isMe, this.onTap});

  static const _w = 200.0;
  static const _h = 120.0;

  @override
  Widget build(BuildContext context) {
    final dur = media.durationMs > 0 ? formatDurationMs(media.durationMs) : '';
    final poster = media.poster;
    final videoUrl = media.url;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: _w,
          height: _h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster != null && poster.isNotEmpty)
                Image.network(
                  publicMediaUrl(poster),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => buildVideoBubbleThumb(videoUrl, width: _w, height: _h),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return buildVideoBubbleThumb(videoUrl, width: _w, height: _h);
                  },
                )
              else
                buildVideoBubbleThumb(videoUrl, width: _w, height: _h),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              ),
              if (dur.isNotEmpty)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(dur, style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String videoPublicUrl(String url) => publicMediaUrl(url);
