import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../util/media_url.dart';

Widget buildVideoBubbleThumb(String url, {double width = 200, double height = 120}) {
  return _IoVideoThumb(url: url, width: width, height: height);
}

class _IoVideoThumb extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  const _IoVideoThumb({required this.url, required this.width, required this.height});

  @override
  State<_IoVideoThumb> createState() => _IoVideoThumbState();
}

class _IoVideoThumbState extends State<_IoVideoThumb> {
  VideoPlayerController? _controller;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final src = publicMediaUrl(widget.url);
    if (src.isEmpty) {
      _failed = true;
      return;
    }
    _controller = VideoPlayerController.networkUrl(Uri.parse(src));
    unawaited(
      _controller!
          .initialize()
          .timeout(const Duration(seconds: 8))
          .then((_) async {
        await _controller!.seekTo(const Duration(milliseconds: 80));
        await _controller!.pause();
        if (mounted) setState(() {});
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      }),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null || !c.value.isInitialized) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: Icon(Icons.videocam_outlined, size: 40, color: Colors.white.withValues(alpha: 0.22)),
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
