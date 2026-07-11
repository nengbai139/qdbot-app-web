import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'circle_ui.dart';

/// ponytail: Web getUserMedia 入会前预览（Zoom 风格）
class MeetingPreJoinPreview extends StatefulWidget {
  final bool camOn;
  final bool meeting;

  const MeetingPreJoinPreview({super.key, required this.camOn, this.meeting = true});

  @override
  State<MeetingPreJoinPreview> createState() => _MeetingPreJoinPreviewState();
}

class _MeetingPreJoinPreviewState extends State<MeetingPreJoinPreview> {
  static var _seq = 0;

  late final String _viewType;
  web.HTMLVideoElement? _videoEl;
  web.MediaStream? _stream;

  @override
  void initState() {
    super.initState();
    _viewType = 'qdbot-prejoin-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..autoplay = true
        ..muted = true
        ..playsInline = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.backgroundColor = '#18182A';
      _videoEl = video;
      if (_stream != null) video.srcObject = _stream;
      return video;
    });
    if (widget.camOn) _startCam();
  }

  @override
  void didUpdateWidget(MeetingPreJoinPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.camOn != oldWidget.camOn) {
      if (widget.camOn) {
        _startCam();
      } else {
        _stopCam();
      }
    }
  }

  Future<void> _startCam() async {
    try {
      _stopCam(keepEl: true);
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(video: {true}.toJSBox))
          .toDart;
      _stream = stream;
      _videoEl?.srcObject = stream;
    } catch (_) {}
  }

  void _stopCam({bool keepEl = false}) {
    final s = _stream;
    if (s != null) {
      for (final t in s.getTracks().toDart) {
        t.stop();
      }
    }
    _stream = null;
    if (!keepEl) _videoEl?.srcObject = null;
  }

  @override
  void dispose() {
    _stopCam();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(widget.meeting);
    if (!widget.camOn) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF18182A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.25)),
              const SizedBox(height: 12),
              Text('摄像头已关闭', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
