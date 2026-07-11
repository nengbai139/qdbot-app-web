import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/im_api.dart';
import '../user_pick_sheet.dart';
import 'meeting_deep_link.dart';

/// 会议邀请：IM 通讯录 + 群聊 + 复制链接 + 系统分享
Future<void> showMeetingInviteSheet(
  BuildContext context, {
  required String token,
  required String userId,
  required String title,
  required String roomId,
  String? passcode,
}) {
  final im = ImApi(token);
  final invite = meetingInvitePayload(title: title, roomId: roomId, passcode: passcode);
  final invitePayload = encodeMeetingInvite(invite);
  final inviteText = meetingInviteText(title: title, roomId: roomId, passcode: passcode);
  final inviteLink = meetingJoinLink(roomId, passcode: passcode);

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
            const Text('邀请参会者', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              title.isNotEmpty ? title : '视频会议',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _inviteToUsers(context, im: im, userId: userId, invitePayload: invitePayload);
              },
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('发给通讯录好友'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _inviteToGroup(context, im: im, invitePayload: invitePayload);
              },
              icon: const Icon(Icons.group_outlined),
              label: const Text('发到群聊'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inviteText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制邀请内容，请打开微信粘贴发送')),
                );
              },
              icon: const Icon(Icons.chat_outlined),
              label: const Text('复制发微信'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inviteLink));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制邀请链接')));
              },
              icon: const Icon(Icons.link),
              label: const Text('复制邀请链接'),
            ),
            const SizedBox(height: 4),
            Text(
              '第三方可在浏览器打开链接，登录后输入密码入会',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(ShareParams(text: inviteText));
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('更多分享'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _inviteToUsers(
  BuildContext context, {
  required ImApi im,
  required String userId,
  required String invitePayload,
}) async {
  final recent = await _recentPeers(im);
  if (!context.mounted) return;
  final ids = await showUserPickSheet(
    context,
    im: im,
    title: '邀请参会者',
    multiSelect: true,
    confirmLabel: '发送邀请',
    excludeUserIds: {userId},
    recentUsers: recent,
    currentUserId: userId,
    showContactsBrowse: true,
  );
  if (ids == null || ids.isEmpty || !context.mounted) return;

  var ok = 0;
  for (final id in ids) {
    try {
      final resp = await im.send(toUserId: id, content: invitePayload, contentType: 'meeting_invite');
      if (resp.statusCode == 200) ok++;
    } catch (_) {}
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok > 0 ? '会议邀请已发送给 $ok 位好友' : '发送失败，请稍后重试')),
  );
}

Future<void> _inviteToGroup(
  BuildContext context, {
  required ImApi im,
  required String invitePayload,
}) async {
  final groupId = await _pickGroup(context, im);
  if (groupId == null || !context.mounted) return;
  try {
    final resp = await im.send(groupId: groupId, content: invitePayload, contentType: 'meeting_invite');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp.statusCode == 200 ? '会议邀请已发送到群聊' : '发送失败: ${resp.body}')),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }
}

Future<String?> _pickGroup(BuildContext context, ImApi im) async {
  List<dynamic> groups = [];
  try {
    final resp = await im.groups();
    if (resp.statusCode == 200) {
      groups = (jsonDecode(resp.body)['groups'] as List<dynamic>?) ?? [];
    }
  } catch (_) {}

  if (!context.mounted) return null;
  if (groups.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无群聊')));
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择群聊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final g = groups[i];
                final id = (g['groupId'] ?? '').toString();
                final name = (g['groupName'] ?? g['name'] ?? '群聊').toString();
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.group, size: 18)),
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
