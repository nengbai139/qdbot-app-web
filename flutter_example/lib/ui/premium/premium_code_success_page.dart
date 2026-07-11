import 'package:flutter/material.dart';
import 'premium_deep_link.dart';
import 'share_util.dart';
import 'user_code_display.dart';

/// 靓号购买/换号成功页
class PremiumCodeSuccessPage extends StatelessWidget {
  final String userCode;
  final String levelName;
  final String? levelDesc;
  final String doneLabel;
  final String token;
  final String userId;
  final VoidCallback? onDone;

  const PremiumCodeSuccessPage({
    super.key,
    required this.userCode,
    this.levelName = '',
    this.levelDesc,
    this.doneLabel = '完成',
    this.token = '',
    this.userId = '',
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final premium = levelName.isNotEmpty && levelName != '普通';
    final shareText = premium
        ? '我的 AIM 靓号：$userCode（$levelName）'
        : '我的 AIM 展示码：$userCode';

    return Scaffold(
      appBar: AppBar(title: const Text('靓号已生效')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(Icons.celebration, size: 72, color: Colors.amber.shade700),
            const SizedBox(height: 16),
            Text(
              premium ? '恭喜获得靓号' : '展示码已更新',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.amber.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      userCode,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    if (premium) ...[
                      const SizedBox(height: 12),
                      PremiumLevelChip(levelName: levelName),
                    ],
                    if (levelDesc != null && levelDesc!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(levelDesc!, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '好友可通过搜索此展示码添加你；也可复制分享给他人。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: token.isEmpty
                  ? null
                  : () => shareUserCode(
                        context,
                        token: token,
                        userId: userId,
                        userCode: userCode,
                        levelName: levelName,
                      ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享名片'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => copyUserCode(context, userCode),
              icon: const Icon(Icons.copy),
              label: const Text('复制靓号'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => copyUserCode(context, userCode, shareText: shareLinkForUserCode(userCode)),
              icon: const Icon(Icons.link),
              label: const Text('复制分享链接'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => copyUserCode(context, userCode, shareText: shareText),
              icon: const Icon(Icons.share_outlined),
              label: const Text('复制分享文案'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (onDone != null) {
                  onDone!();
                } else {
                  Navigator.pop(context, true);
                }
              },
              child: Text(doneLabel),
            ),
          ],
        ),
      ),
    );
  }
}
