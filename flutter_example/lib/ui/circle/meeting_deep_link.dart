import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/circle_api.dart';
import '../../config.dart';
import 'circle_navigation.dart';
import 'video_page.dart';
import 'widgets/circle_ui.dart';

/// Web 深链接：?meeting=ROOM_ID（兼容 room / roomId）
String? parseMeetingRoomFromUri(Uri uri) {
  for (final k in const ['meeting', 'room', 'roomId']) {
    final v = (uri.queryParameters[k] ?? '').trim();
    if (v.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(v)) return v;
  }
  return null;
}

String? parseMeetingPasscodeFromUri(Uri uri) {
  for (final k in const ['pwd', 'passcode', 'password']) {
    final v = (uri.queryParameters[k] ?? '').trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

String meetingJoinLink(String roomId, {String? passcode}) {
  final base = Uri.parse('${AppConfig.baseUrl}/app_web/');
  final qp = <String, String>{'meeting': roomId};
  if (passcode != null && passcode.isNotEmpty) qp['pwd'] = passcode;
  return base.replace(queryParameters: qp).toString();
}

/// 保证会议列表过滤与观众端会议文案能识别
String normalizeMeetingTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return '我的会议';
  if (t.endsWith(' · 会议')) return t;
  return '$t · 会议';
}

/// 直播标题：避免误标为会议
String normalizeLiveTitle(String title) {
  var t = title.trim();
  if (t.isEmpty) return '互动直播';
  if (t == '视频会议') return '互动直播';
  if (t.endsWith(' · 会议')) return '${t.substring(0, t.length - ' · 会议'.length)} · 直播';
  if (t.endsWith(' · 直播')) return t;
  return t;
}



/// IM 会议邀请卡片 payload（contentType=meeting_invite）或纯文本邀请
class MeetingInviteData {
  final String roomId;
  final String title;
  final String? passcode;
  final String? joinUrl;

  const MeetingInviteData({
    required this.roomId,
    required this.title,
    this.passcode,
    this.joinUrl,
  });

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'title': title,
        if (passcode != null && passcode!.isNotEmpty) 'passcode': passcode,
        if (joinUrl != null && joinUrl!.isNotEmpty) 'joinUrl': joinUrl,
      };

  factory MeetingInviteData.fromJson(Map<String, dynamic> j) => MeetingInviteData(
        roomId: (j['roomId'] ?? j['meeting'] ?? '').toString(),
        title: (j['title'] ?? '视频会议').toString(),
        passcode: (j['passcode'] ?? j['pwd'] ?? '').toString().trim().isEmpty
            ? null
            : (j['passcode'] ?? j['pwd'] ?? '').toString(),
        joinUrl: (j['joinUrl'] ?? '').toString().trim().isEmpty ? null : (j['joinUrl'] ?? '').toString(),
      );
}

String encodeMeetingInvite(MeetingInviteData invite) => jsonEncode(invite.toJson());

MeetingInviteData meetingInvitePayload({
  required String title,
  required String roomId,
  String? passcode,
}) =>
    MeetingInviteData(
      title: title,
      roomId: roomId,
      passcode: passcode,
      joinUrl: meetingJoinLink(roomId, passcode: passcode),
    );

String meetingInvitePreviewLabel(MeetingInviteData invite) {
  final t = invite.title.trim();
  return t.isNotEmpty ? '[会议邀请] $t' : '[会议邀请]';
}

bool _validMeetingRoomId(String? id) =>
    id != null && id.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);

MeetingInviteData? tryParseMeetingInvite(String raw, {String? contentType}) {
  final ct = (contentType ?? '').toLowerCase();
  if (ct == 'meeting_invite') {
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final invite = MeetingInviteData.fromJson(Map<String, dynamic>.from(j));
        if (_validMeetingRoomId(invite.roomId)) return invite;
      }
    } catch (_) {}
  }
  return tryParseMeetingInviteText(raw);
}

MeetingInviteData? tryParseMeetingInviteText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final looksLikeInvite = text.contains('视频会议') ||
      text.contains('会议号') ||
      RegExp(r'[?&]meeting=', caseSensitive: false).hasMatch(text);
  if (!looksLikeInvite) return null;

  String? roomId;
  String? passcode;
  String? joinUrl;

  final urlMatch = RegExp(r'https?://\S+').firstMatch(text);
  if (urlMatch != null) {
    joinUrl = urlMatch.group(0);
    final uri = Uri.tryParse(joinUrl!);
    if (uri != null) {
      roomId = parseMeetingRoomFromUri(uri);
      passcode = parseMeetingPasscodeFromUri(uri);
    }
  }

  roomId ??= RegExp(r'会议号[：:]\s*(\S+)').firstMatch(text)?.group(1);
  passcode ??= RegExp(r'入会密码[：:]\s*(\S+)').firstMatch(text)?.group(1);

  if (!_validMeetingRoomId(roomId)) return null;

  var title = RegExp(r'主题[：:]\s*(.+)').firstMatch(text)?.group(1)?.trim() ?? '';
  if (title.contains('\n')) title = title.split('\n').first.trim();
  if (title.isEmpty) title = '视频会议';

  return MeetingInviteData(
    roomId: roomId!,
    title: title,
    passcode: passcode?.isNotEmpty == true ? passcode : null,
    joinUrl: joinUrl ?? meetingJoinLink(roomId!, passcode: passcode),
  );
}



/// 第三方链接入会：无密码参数时弹窗输入
Future<String?> promptMeetingPasscode(BuildContext context, {String? initial}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final pwd = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('入会密码', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '请输入主持人提供的密码',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('加入'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  final t = pwd?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// 邀请链接 / 会议号入会（含密码校验）
Future<void> joinMeetingByInvite(
  BuildContext context, {
  required String token,
  required String userId,
  required String roomId,
  String passcode = '',
}) async {
  final api = CircleApi(token);
  final room = await api.getLiveRoom(roomId);
  if (!context.mounted) return;
  var pwd = passcode.trim();
  if (room.hasJoinPassword && room.hostId != userId && pwd.isEmpty) {
    pwd = await promptMeetingPasscode(context) ?? '';
    if (!context.mounted || pwd.isEmpty) return;
  }
  if (room.hasJoinPassword && room.hostId != userId && pwd.isNotEmpty) {
    await api.joinCheckLiveRoom(roomId, passcode: pwd);
  }
  if (!context.mounted) return;
  if (!room.isMeeting) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该房间不是视频会议')));
    return;
  }
  if (!room.meetingJoinable) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会议服务未就绪，请稍后重试')));
    return;
  }
  await openMeetingRoom(context, token: token, userId: userId, room: room, joinPasscode: pwd);
}

String meetingInviteText({required String title, required String roomId, String? passcode}) {
  final pwdLine = passcode != null && passcode.isNotEmpty ? '入会密码：$passcode\n' : '';
  return '邀请你加入视频会议\n'
      '主题：$title\n'
      '会议号：$roomId\n'
      '$pwdLine'
      '一键加入：${meetingJoinLink(roomId, passcode: passcode)}';
}

void openMeetingReplay(BuildContext context, {required String token, required String userId, required String postId}) {
  if (postId.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => VideoPage(token: token, userId: userId, initialPostId: postId)),
  );
}

String meetingRemovedMessage(String reason) {
  if (reason == 'host removed') return '主持人已将你移出会议';
  final lower = reason.toLowerCase();
  if (reason.contains('结束') || lower.contains('ended') || lower == 'room_closed') {
    return '主持人已结束会议';
  }
  return reason.isNotEmpty && reason != 'removed' ? reason : '会议已断开';
}

bool meetingEndedByHost(String reason) {
  if (reason == 'host removed') return false;
  final lower = reason.toLowerCase();
  return reason.contains('结束') || lower.contains('ended') || lower == 'room_closed' || reason == 'removed';
}

Future<void> showMeetingEndedNotice(
  BuildContext context, {
  required String token,
  required String userId,
  required String reason,
  String? replayPostId,
  String title = '会议已结束',
  String replayMessage = '主持人已结束会议，录像已保存（仅参会成员可在视频圈查看）。',
}) async {
  if (!context.mounted) return;
  if (!meetingEndedByHost(reason)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(meetingRemovedMessage(reason))));
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: kMeetingSurface,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(
        replayPostId != null && replayPostId.isNotEmpty ? replayMessage : meetingRemovedMessage(reason),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.45),
      ),
      actions: [
        if (replayPostId != null && replayPostId.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
            onPressed: () {
              Navigator.pop(ctx);
              openMeetingReplay(context, token: token, userId: userId, postId: replayPostId);
            },
            child: const Text('观看录像'),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('返回')),
      ],
    ),
  );
}
