import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void copyUserCode(BuildContext context, String code, {String? shareText}) {
  Clipboard.setData(ClipboardData(text: shareText ?? code));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(shareText != null ? '分享文案已复制' : '靓号 $code 已复制')),
  );
}

/// 靓号等级角标（levelName 为「普通」时不显示）
class PremiumLevelChip extends StatelessWidget {
  final String levelName;
  final bool compact;

  const PremiumLevelChip({super.key, required this.levelName, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (levelName.isEmpty || levelName == '普通') return const SizedBox.shrink();
    final bg = Colors.amber.shade100;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
      ),
      child: Text(
        levelName,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: Colors.amber.shade900,
        ),
      ),
    );
  }
}

/// 资料卡上的展示码行：大号 ID + 等级 + 复制
class UserCodeRow extends StatelessWidget {
  final String userCode;
  final String levelName;
  final bool showCopy;

  const UserCodeRow({
    super.key,
    required this.userCode,
    this.levelName = '',
    this.showCopy = true,
  });

  @override
  Widget build(BuildContext context) {
    if (userCode.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userCode,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Colors.grey.shade800,
                ),
              ),
              if (levelName.isNotEmpty && levelName != '普通') ...[
                const SizedBox(height: 4),
                PremiumLevelChip(levelName: levelName),
              ],
            ],
          ),
        ),
        if (showCopy)
          IconButton(
            tooltip: '复制靓号',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy, size: 20, color: Colors.grey.shade600),
            onPressed: () => copyUserCode(context, userCode),
          ),
      ],
    );
  }
}
