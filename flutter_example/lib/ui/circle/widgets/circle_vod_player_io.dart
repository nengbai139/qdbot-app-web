import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../util/media_url.dart';

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
  VideoPlayerController? _ctrl;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ctrl?.dispose();
    _ctrl = null;
    if (!mounted) return;
    setState(() {
      _failed = false;
    });
    final src = publicMediaUrl(widget.url);
    if (src.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(src),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _ctrl = ctrl);
      _syncPlayback(ctrl);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(CircleVodPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _init();
      return;
    }
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (old.active != widget.active || old.playing != widget.playing) {
      _syncPlayback(ctrl);
    }
  }

  bool get _shouldPlay => widget.active && widget.playing;

  void _syncPlayback(VideoPlayerController ctrl) {
    if (_shouldPlay) {
      ctrl.play();
    } else {
      ctrl.pause();
    }
  }

  void _toggleMute() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    setState(() => _muted = !_muted);
    ctrl.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: _init,
          child: const Text('播放失败，轻触重试', style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        ),
        if (_muted)
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
