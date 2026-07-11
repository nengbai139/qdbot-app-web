import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../live_web_audio.dart';

/// 直播静音提示：浏览器自动播放策略需用户点击开声
class LiveAudioUnmuteOverlay extends StatefulWidget {
  const LiveAudioUnmuteOverlay({super.key});

  @override
  State<LiveAudioUnmuteOverlay> createState() => _LiveAudioUnmuteOverlayState();
}

class _LiveAudioUnmuteOverlayState extends State<LiveAudioUnmuteOverlay> {
  bool _hidden = false;
  bool _needsUnmute = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _refresh();
  }

  void _refresh() {
    if (!kIsWeb || _hidden) return;
    final needs = LiveWebAudio.needsUnmute();
    if (needs != _needsUnmute && mounted) setState(() => _needsUnmute = needs);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_hidden) _refresh();
    });
  }

  void _unmute() {
    if (!kIsWeb) return;
    LiveWebAudio.unmuteAll();
    setState(() {
      _hidden = true;
      _needsUnmute = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _hidden || !_needsUnmute) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 72,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        child: Center(
          child: InkWell(
            onTap: _unmute,
            borderRadius: BorderRadius.circular(24),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_off_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('点击开启声音', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
