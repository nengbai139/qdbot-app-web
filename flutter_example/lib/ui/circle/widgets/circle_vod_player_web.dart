import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../util/media_url.dart';
import '../../../util/vod_url.dart';

class CircleVodPlayer extends StatefulWidget {
  final String url;
  final String posterUrl;
  final bool active;
  final bool playing;

  const CircleVodPlayer({
    super.key,
    required this.url,
    this.posterUrl = '',
    this.active = false,
    this.playing = true,
  });

  @override
  State<CircleVodPlayer> createState() => _CircleVodPlayerState();
}

class _CircleVodPlayerState extends State<CircleVodPlayer> {
  late final String _viewType;
  web.HTMLVideoElement? _video;
  bool _muted = true;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'qdbot-vod-${widget.url.hashCode}-${identityHashCode(this)}';
    _register();
  }

  void _register() {
    final src = publicMediaUrl(widget.url);
    if (!isPlayableCircleVodUrl(src)) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        return web.document.createElement('div') as web.HTMLDivElement
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'black';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _failed = true);
      });
      return;
    }
    final poster = publicMediaUrl(widget.posterUrl);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..src = src
        ..controls = false
        ..autoplay = false
        ..playsInline = true
        ..loop = true
        ..muted = true
        ..crossOrigin = 'anonymous'
        ..preload = 'auto'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.backgroundColor = 'black';
      if (poster.isNotEmpty) video.poster = poster;
      video.addEventListener(
        'canplay',
        ((web.Event _) {
          if (!mounted) return;
          setState(() {
            _ready = true;
            _failed = false;
          });
          _syncPlayback();
        }).toJS,
      );
      video.addEventListener(
        'error',
        ((web.Event _) {
          if (!mounted) return;
          setState(() => _failed = true);
        }).toJS,
      );
      _video = video;
      _syncPlayback();
      return video;
    });
  }

  @override
  void didUpdateWidget(CircleVodPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      final video = _video;
      if (video != null) {
        video.src = publicMediaUrl(widget.url);
        final poster = publicMediaUrl(widget.posterUrl);
        if (poster.isNotEmpty) {
          video.poster = poster;
        } else {
          video.removeAttribute('poster');
        }
        setState(() {
          _ready = false;
          _failed = false;
        });
      }
    }
    if (old.active != widget.active || old.playing != widget.playing) {
      _syncPlayback();
    }
  }

  bool get _shouldPlay => widget.active && widget.playing;

  void _syncPlayback() => _shouldPlay ? _play() : _pause();

  void _play() {
    final video = _video;
    if (video == null) return;
    video.muted = _muted;
    video.play();
  }

  void _pause() {
    _video?.pause();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      final video = _video;
      if (video != null) video.muted = _muted;
    });
  }

  void _retry() {
    final video = _video;
    if (video == null) return;
    setState(() => _failed = false);
    video.load();
    if (widget.active) _syncPlayback();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready && !_failed)
          const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2)),
        if (_failed)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_empty_rounded, color: Colors.white38, size: 36),
                const SizedBox(height: 8),
                Text(
                  isPlayableCircleVodUrl(widget.url) ? '播放失败，轻触重试' : '回放暂不可用',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (isPlayableCircleVodUrl(widget.url))
                  TextButton(onPressed: _retry, child: const Text('重试', style: TextStyle(color: Colors.white))),
              ],
            ),
          ),
        if (_muted && _ready && !_failed)
          Positioned(
            right: 12,
            top: 12,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_off_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text('轻触开声', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
