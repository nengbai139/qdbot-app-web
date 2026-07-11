import 'package:flutter/material.dart';
import 'share_util.dart';
import 'user_code_display.dart';

/// 资料卡入口场景，决定底部操作区展示什么。
enum UserProfileContext {
  /// 单聊顶栏 / 会话列表点展示码：只看对方信息，复制用 UserCodeRow 图标。
  viewOnly,

  /// 群聊点头像 / 成员列表：主操作私聊，次要操作分享对方名片。
  fromGroup,
}

/// 点击 IM 内用户头像 / 展示码后弹出的资料卡
Future<void> showUserProfileSheet(
  BuildContext context, {
  required String userId,
  String displayName = '',
  String userCode = '',
  String levelName = '',
  String levelDesc = '',
  bool premium = false,
  String? email,
  String token = '',
  UserProfileContext sheetContext = UserProfileContext.viewOnly,
  VoidCallback? onMessage,
}) {
  final name = displayName.isNotEmpty ? displayName : (userCode.isNotEmpty ? userCode : userId);
  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
  final fromGroup = sheetContext == UserProfileContext.fromGroup;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(initial, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      if (email != null && email.isNotEmpty)
                        Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            if (userCode.isNotEmpty) ...[
              const SizedBox(height: 16),
              UserCodeRow(userCode: userCode, levelName: levelName),
              if (levelDesc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(levelDesc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
            ],
            if (fromGroup && onMessage != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  onMessage();
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('发消息'),
              ),
              if (userCode.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: token.isEmpty
                      ? null
                      : () => shareUserCode(
                            ctx,
                            token: token,
                            userId: userId,
                            userCode: userCode,
                            levelName: levelName,
                            displayName: name,
                            email: email ?? '',
                          ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('分享名片'),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

/// 群成员 @ 时可识别的别名（昵称 / 展示码 / userId）
Set<String> mentionAliasesForMember(Map<String, dynamic> m) {
  return {
    (m['userId'] ?? '').toString(),
    (m['nickname'] ?? '').toString(),
    (m['displayName'] ?? '').toString(),
    (m['userCode'] ?? '').toString(),
  }.where((s) => s.isNotEmpty).toSet();
}

String mentionInsertTag(Map<String, dynamic> m) {
  final code = (m['userCode'] ?? '').toString();
  if (code.isNotEmpty) return code;
  final nick = (m['nickname'] ?? m['displayName'] ?? '').toString();
  if (nick.isNotEmpty) return nick;
  return (m['userId'] ?? '').toString();
}
