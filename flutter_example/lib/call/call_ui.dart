import 'package:flutter/material.dart';

import 'call_signal.dart';

/// 微信式圆形控制按钮
class CallRoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color bg;
  final Color fg;
  final double size;

  const CallRoundButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.bg = const Color(0x33FFFFFF),
    this.fg = Colors.white,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: fg, size: size * 0.46),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 12)),
      ],
    );
  }
}

/// 来电全屏弹窗（微信风格）
class CallIncomingDialog extends StatelessWidget {
  final String peerName;
  final CallMedia media;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  const CallIncomingDialog({
    super.key,
    required this.peerName,
    required this.media,
    required this.onReject,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = media == CallMedia.video;
    final initial = peerName.isNotEmpty ? peerName[0].toUpperCase() : '?';
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white24,
              child: Text(initial, style: const TextStyle(fontSize: 36, color: Colors.white)),
            ),
            const SizedBox(height: 20),
            Text(
              peerName,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? '邀请你视频通话' : '邀请你语音通话',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CallRoundButton(
                    icon: Icons.call_end,
                    label: '拒绝',
                    bg: const Color(0xFFE53935),
                    onPressed: onReject,
                    size: 64,
                  ),
                  CallRoundButton(
                    icon: isVideo ? Icons.videocam : Icons.call,
                    label: '接听',
                    bg: const Color(0xFF43A047),
                    onPressed: onAccept,
                    size: 64,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}

String formatCallDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
