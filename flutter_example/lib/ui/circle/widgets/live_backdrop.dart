import 'package:flutter/material.dart';

import '../../../util/media_url.dart';
import '../../app_theme.dart';

/// 直播等待态背景墙：封面图 + 渐变遮罩，无图时用品牌渐变。
class LiveBackdrop extends StatelessWidget {
  final String? coverUrl;
  final Widget? child;
  final bool dimmed;

  const LiveBackdrop({
    super.key,
    this.coverUrl,
    this.child,
    this.dimmed = true,
  });

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A1F2E),
      Color(0xFF3A4F6B),
      Color(0xFFE5484D),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final url = publicMediaUrl(coverUrl ?? '');
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(gradient: _gradient)),
        if (url.isNotEmpty)
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (dimmed)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        if (child != null) Center(child: child),
      ],
    );
  }
}

/// 直播列表卡片默认封面（无 host 头像时）
Widget liveListCoverFallback() {
  return const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE5484D),
          AppTheme.brandBlue,
        ],
      ),
    ),
    child: Center(
      child: Icon(Icons.sensors, size: 56, color: Colors.white38),
    ),
  );
}
