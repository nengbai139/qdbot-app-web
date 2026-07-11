import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LivePlayer extends StatefulWidget {
  final String url;

  const LivePlayer({super.key, required this.url});

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> {
  VideoPlayerController? _ctrl;
  String? _error;
  int _attempt = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _retryTimer?.cancel();
    await _ctrl?.dispose();
    _ctrl = null;
    if (!mounted) return;
    setState(() {
      _error = null;
    });
    try {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      await ctrl.setLooping(true);
      await ctrl.play();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _attempt = 0;
      });
    } catch (e) {
      if (!mounted) return;
      _attempt++;
      if (_attempt >= 8) {
        setState(() => _error = '连接超时，轻触重试');
        return;
      }
      _retryTimer = Timer(const Duration(seconds: 2), _start);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return GestureDetector(
        onTap: () {
          _attempt = 0;
          _start();
        },
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      );
    }
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
    );
  }
}
