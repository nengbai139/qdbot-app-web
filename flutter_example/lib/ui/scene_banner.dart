import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 场景说明条（AI 不会发到群、@ 唤醒分身等）
class SceneBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? backgroundColor;

  const SceneBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? AppTheme.brandBlue.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.brandBlue),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800))),
          ],
        ),
      ),
    );
  }
}
