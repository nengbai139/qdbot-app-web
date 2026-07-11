import 'package:flutter/material.dart';

import 'circle_ui.dart';

/// 非 Web 平台：入会前预览占位
class MeetingPreJoinPreview extends StatelessWidget {
  final bool camOn;
  final bool meeting;

  const MeetingPreJoinPreview({super.key, required this.camOn, this.meeting = true});

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF18182A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Center(
        child: camOn
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_rounded, size: 56, color: accent.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text('摄像头预览仅支持网页版', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                ],
              )
            : Column(
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
}
