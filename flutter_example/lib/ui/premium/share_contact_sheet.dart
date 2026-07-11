import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../api/auth_api.dart';
import '../../api/im_api.dart';
import '../../util/save_bytes.dart';
import '../forward_target_sheet.dart';
import '../user_pick_sheet.dart';
import 'contact_card.dart';
import 'contact_card_poster.dart';
import 'premium_deep_link.dart';
import 'user_code_display.dart';
import 'user_profile_sheet.dart';

Future<void> showShareContactSheet(
  BuildContext context, {
  required ImApi im,
  required ContactCardData card,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
            const Text('分享名片', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Center(child: ContactCardPreview(card: card)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _shareToUsers(context, im, card);
              },
              icon: const Icon(Icons.person_outline),
              label: const Text('发给好友'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _shareToGroup(context, im, card);
              },
              icon: const Icon(Icons.group_outlined),
              label: const Text('发到群聊'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await showContactCardPosterShare(context, card);
              },
              icon: const Icon(Icons.image_outlined),
              label: const Text('微信 / 朋友圈（分享图）'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      copyUserCode(context, card.userCode, shareText: shareLinkForUserCode(card.userCode));
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('复制链接'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _systemShare(card),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('更多分享'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _shareToUsers(BuildContext context, ImApi im, ContactCardData card) async {
  final recent = await _recentPeers(im);
  if (!context.mounted) return;
  final ids = await showUserPickSheet(
    context,
    im: im,
    title: '选择好友',
    multiSelect: true,
    confirmLabel: '发送名片',
    recentUsers: recent,
  );
  if (ids == null || ids.isEmpty || !context.mounted) return;

  final payload = encodeContactCard(card);
  var ok = 0;
  for (final id in ids) {
    try {
      final resp = await im.send(toUserId: id, content: payload, contentType: 'contact_card');
      if (resp.statusCode == 200) ok++;
    } catch (_) {}
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok > 0 ? '名片已发送给 $ok 位好友' : '发送失败，请稍后重试')),
  );
}

Future<void> _shareToGroup(BuildContext context, ImApi im, ContactCardData card) async {
  final target = await pickForwardTarget(context, im);
  if (target == null || target.kind != 'group' || !context.mounted) return;

  final payload = encodeContactCard(card);
  try {
    final resp = await im.send(groupId: target.id, content: payload, contentType: 'contact_card');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp.statusCode == 200 ? '名片已发送到群聊' : '发送失败: ${resp.body}')),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }
}

Future<List<Map<String, String>>> _recentPeers(ImApi im) async {
  try {
    final resp = await im.sessions();
    if (resp.statusCode != 200) return [];
    final sessions = (jsonDecode(resp.body)['sessions'] as List<dynamic>?) ?? [];
    final out = <Map<String, String>>[];
    for (final s in sessions) {
      if (s is! Map) continue;
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? '').toString();
      if (peerId.isEmpty) continue;
      out.add({
        'userId': peerId,
        'displayName': (s['peerName'] ?? peerId).toString(),
      });
      if (out.length >= 12) break;
    }
    return out;
  } catch (_) {
    return [];
  }
}

void _systemShare(ContactCardData card) {
  final link = shareLinkForUserCode(card.userCode);
  final who = card.title;
  final text = card.premium
      ? '$who · 靓号 ${card.userCode}（${card.levelName}）\n$link'
      : '$who · 展示码 ${card.userCode}\n$link';
  SharePlus.instance.share(ShareParams(text: text, subject: 'AIM 名片 ${card.userCode}'));
}

/// 生成竖版名片图：保存 / 系统分享，适合微信、朋友圈
Future<void> showContactCardPosterShare(BuildContext context, ContactCardData card) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final bytes = await captureContactCardPoster(context, card);
  if (context.mounted) Navigator.pop(context);
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分享图生成失败，请重试')));
    }
    return;
  }
  if (!context.mounted) return;

  final link = shareLinkForUserCode(card.userCode);
  final filename = 'aim-${card.userCode}.png';

  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('分享名片图片', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                '保存图片后发到微信好友或朋友圈；好友扫码即可添加你',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('链接已复制')));
                      },
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('复制链接'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final ok = await saveBytesAsFile(bytes, filename);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(ok ? '图片已保存，可去微信分享' : '请长按图片保存')),
                          );
                        }
                      },
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('保存图片'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile.fromData(bytes, mimeType: 'image/png', name: filename)],
                        text: '${card.title} · ${card.userCode}\n$link',
                        subject: 'AIM 名片 ${card.userCode}',
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('系统分享'),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 聊天内点击名片：查看资料 / 发消息
Future<void> openContactCard(
  BuildContext context, {
  required ContactCardData card,
  required String token,
  required String myUserId,
  VoidCallback? onOpenChat,
}) async {
  var data = card;
  if (data.userId.isEmpty && data.userCode.isNotEmpty) {
    try {
      final resp = await AuthApi().userByCode(data.userCode);
      if (resp.statusCode == 200) {
        data = ContactCardData.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
      }
    } catch (_) {}
  }
  if (!context.mounted) return;
  if (data.userId.isNotEmpty && data.userId == myUserId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这是你自己的名片')));
    return;
  }
  await showUserProfileSheet(
    context,
    userId: data.userId,
    displayName: data.displayName,
    userCode: data.userCode,
    levelName: data.levelName,
    email: data.email,
    token: token,
    premium: data.premium,
    sheetContext: UserProfileContext.viewOnly,
    onMessage: onOpenChat,
  );
}
