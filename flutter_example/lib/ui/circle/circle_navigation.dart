import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import 'circle_models.dart';
import 'live_host_page.dart';
import 'live_room_page.dart';
import 'meeting_sfu_page.dart';
import 'user_circle_page.dart';

void openUserCircle(
  BuildContext context, {
  required String token,
  required String viewerId,
  required String authorId,
  String authorName = '',
  String authorCode = '',
  String authorEmail = '',
  String authorAvatar = '',
}) {
  if (authorId.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => UserCirclePage(
        token: token,
        viewerId: viewerId,
        authorId: authorId,
        authorName: authorName,
        authorCode: authorCode,
        authorEmail: authorEmail,
        authorAvatar: authorAvatar,
      ),
    ),
  );
}

void openUserCircleFromPost(
  BuildContext context, {
  required String token,
  required String viewerId,
  required CirclePost post,
}) {
  openUserCircle(
    context,
    token: token,
    viewerId: viewerId,
    authorId: post.authorId,
    authorName: post.authorName,
    authorCode: post.authorCode,
    authorEmail: post.authorEmail,
    authorAvatar: post.authorAvatar,
  );
}

void openUserCircleFromLiveHost(
  BuildContext context, {
  required String token,
  required String viewerId,
  required LiveRoom room,
}) {
  openUserCircle(
    context,
    token: token,
    viewerId: viewerId,
    authorId: room.hostId,
    authorName: room.hostName,
  );
}

void openUserCircleFromLiveMessage(
  BuildContext context, {
  required String token,
  required String viewerId,
  required LiveMessage message,
}) {
  openUserCircle(
    context,
    token: token,
    viewerId: viewerId,
    authorId: message.authorId,
    authorName: message.authorName,
  );
}

String? meetingUnavailableReason(LiveRoom room) {
  if (!room.isMeeting) return '不是视频会议';
  if (!room.isSfu) return '会议服务未就绪，请稍后重试';
  return null;
}

void _showMeetingUnavailable(BuildContext context, LiveRoom room) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(meetingUnavailableReason(room) ?? '无法加入会议')),
  );
}

/// 按房间号打开：直播圈 → 直播间；视频会议 → LiveKit
Future<T?> openCircleRoomById<T>(
  BuildContext context, {
  required String token,
  required String userId,
  required String roomId,
  String joinPasscode = '',
}) async {
  if (roomId.isEmpty) return null;
  try {
    final room = await CircleApi(token).getLiveRoom(roomId);
    if (!context.mounted) return null;
    return openCircleRoom<T>(context, token: token, userId: userId, room: room, joinPasscode: joinPasscode);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法进入房间：$e')));
    }
    return null;
  }
}

Future<T?> openCircleRoom<T>(
  BuildContext context, {
  required String token,
  required String userId,
  required LiveRoom room,
  String joinPasscode = '',
}) {
  if (room.isMeeting) {
    return openMeetingRoom<T>(context, token: token, userId: userId, room: room, joinPasscode: joinPasscode);
  }
  return openLiveBroadcastRoom<T>(context, token: token, userId: userId, room: room);
}

/// 直播圈（roomType=live）：打赏/PK/WHIP
Future<T?> openLiveBroadcastRoom<T>(
  BuildContext context, {
  required String token,
  required String userId,
  required LiveRoom room,
}) {
  if (room.isMeeting) {
    return openMeetingRoom<T>(context, token: token, userId: userId, room: room);
  }
  if (room.hostId == userId) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveHostPage(token: token, userId: userId, initialRoom: room),
      ),
    );
  }
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
      builder: (_) => LiveRoomPage(token: token, userId: userId, roomId: room.roomId),
    ),
  );
}

/// 视频会议（roomType=meeting）：仅 LiveKit SFU
Future<T?> openMeetingRoom<T>(
  BuildContext context, {
  required String token,
  required String userId,
  required LiveRoom room,
  String joinPasscode = '',
}) {
  if (!room.isMeeting) {
    return openLiveBroadcastRoom<T>(context, token: token, userId: userId, room: room);
  }
  if (!room.isSfu) {
    _showMeetingUnavailable(context, room);
    return Future.value(null);
  }
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
      builder: (_) => MeetingSfuPage(
        token: token,
        userId: userId,
        room: room,
        isHost: room.hostId == userId,
        joinPasscode: joinPasscode,
        skipPreJoin: room.hostId == userId,
      ),
    ),
  );
}
