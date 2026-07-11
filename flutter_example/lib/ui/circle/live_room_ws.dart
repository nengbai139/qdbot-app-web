import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config.dart';
import '../../ws/ws_connect.dart';
import 'circle_models.dart';

/// 直播间 WebSocket：弹幕、点赞、在线人数
class LiveRoomWs {
  LiveRoomWs({
    required this.token,
    required this.roomId,
    this.joinPasscode = '',
    required this.onMessage,
    this.onViewerCount,
    this.onLikeBurst,
    this.onGift,
    this.onRedPacket,
    this.onRedPacketGrab,
    this.onCohost,
    this.onCohostEnd,
    this.onCohostInvite,
    this.onPushStatus,
    this.onPkInvite,
    this.onPkStart,
    this.onPkScore,
    this.onPkEnd,
    this.onConnectionChange,
    this.onParticipants,
    this.onLobbyWaiting,
    this.onLobbyAdmitted,
    this.onLobbyList,
    this.onRemoved,
    this.onMuteAll,
    this.onUnmuteAll,
    this.onCaption,
    this.onScreenShare,
    this.onBreakoutStarted,
    this.onBreakoutAssign,
    this.onBreakoutEnded,
    this.onRecording,
  });

  final String token;
  final String roomId;
  final String joinPasscode;
  final void Function(LiveMessage msg) onMessage;
  final void Function(int count)? onViewerCount;
  final void Function(String authorId, String authorName)? onLikeBurst;
  final void Function(LiveGiftEvent gift)? onGift;
  final void Function(LiveRedPacket packet)? onRedPacket;
  final void Function(LiveRedPacketGrab grab, LiveRedPacket? packet)? onRedPacketGrab;
  final void Function(LiveCohost cohost)? onCohost;
  final void Function()? onCohostEnd;
  final void Function(String whipUrl, LiveCohost cohost, {bool sfu})? onCohostInvite;
  final void Function(bool active)? onPushStatus;
  final void Function(LivePk pk)? onPkInvite;
  final void Function(LivePk pk)? onPkStart;
  final void Function(LivePk pk)? onPkScore;
  final void Function(LivePk? pk)? onPkEnd;
  final void Function(bool connected)? onConnectionChange;
  final void Function(List<LiveParticipant> list)? onParticipants;
  final void Function(String message)? onLobbyWaiting;
  final void Function()? onLobbyAdmitted;
  final void Function(List<LiveParticipant> list)? onLobbyList;
  final void Function(String reason, {String? replayPostId})? onRemoved;
  final void Function(bool allowUnmute)? onMuteAll;
  final void Function()? onUnmuteAll;
  final void Function(LiveCaption caption)? onCaption;
  final void Function(String speakerId, String speakerName, bool active)? onScreenShare;
  final void Function(Map<String, String> assignments, String mainRoom)? onBreakoutStarted;
  final void Function(String livekitRoom)? onBreakoutAssign;
  final void Function(String mainRoom)? onBreakoutEnded;
  final void Function(bool active)? onRecording;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  var _disposed = false;
  var _connected = false;

  bool get isConnected => _connected;

  Uri _uri() {
    final base = AppConfig.baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    return Uri.parse(
      '$base${AppConfig.circleApiPath}/live/rooms/$roomId/ws?token=${Uri.encodeComponent(token)}'
      '${joinPasscode.isNotEmpty ? '&passcode=${Uri.encodeComponent(joinPasscode)}' : ''}',
    );
  }

  void connect() {
    if (_disposed) return;
    _reconnect?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _sub?.cancel();
    _channel = connectWs(_uri());
    _sub = _channel!.stream.listen(
      (data) {
        if (!_connected) {
          _connected = true;
          onConnectionChange?.call(true);
        }
        try {
          final j = jsonDecode(data as String) as Map<String, dynamic>;
          _dispatch(j);
        } catch (_) {}
      },
      onError: (_) => _onDisconnect(),
      onDone: () => _onDisconnect(),
      cancelOnError: true,
    );
  }

  void _dispatch(Map<String, dynamic> j) {
    switch ((j['type'] ?? '').toString()) {
      case 'message':
        onMessage(LiveMessage.fromJson(j));
      case 'viewer_count':
        onViewerCount?.call((j['count'] as num?)?.toInt() ?? 0);
      case 'participants':
        final raw = j['list'];
        if (raw is List) {
          final list = raw
              .whereType<Map>()
              .map((m) => LiveParticipant.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          onParticipants?.call(list);
        }
      case 'lobby_waiting':
        onLobbyWaiting?.call((j['message'] ?? '等待主持人准许入会').toString());
      case 'lobby_admitted':
        onLobbyAdmitted?.call();
      case 'lobby_list':
        final lobbyRaw = j['list'];
        if (lobbyRaw is List) {
          final list = lobbyRaw
              .whereType<Map>()
              .map((m) => LiveParticipant.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          onLobbyList?.call(list);
        }
      case 'removed':
        final rid = (j['replayPostId'] ?? '').toString();
        onRemoved?.call(
          (j['reason'] ?? 'removed').toString(),
          replayPostId: rid.isEmpty ? null : rid,
        );
      case 'room_ended':
        final rid2 = (j['replayPostId'] ?? '').toString();
        onRemoved?.call('会议已结束', replayPostId: rid2.isEmpty ? null : rid2);
      case 'mute_all':
        onMuteAll?.call(j['allowUnmute'] == true);
      case 'unmute_all':
        onUnmuteAll?.call();
      case 'caption':
        onCaption?.call(LiveCaption.fromJson(j));
      case 'breakout_started':
        final raw = j['assignments'];
        final assign = <String, String>{};
        if (raw is Map) raw.forEach((k, v) => assign[k.toString()] = v.toString());
        onBreakoutStarted?.call(assign, (j['mainRoom'] ?? '').toString());
      case 'breakout_assign':
        onBreakoutAssign?.call((j['livekitRoom'] ?? '').toString());
      case 'recording':
        onRecording?.call(j['active'] == true);
      case 'breakout_ended':
        onBreakoutEnded?.call((j['mainRoom'] ?? '').toString());
      case 'screen_share':
        onScreenShare?.call(
          (j['speakerId'] ?? '').toString(),
          (j['speakerName'] ?? '').toString(),
          j['active'] == true,
        );
      case 'like':
        onLikeBurst?.call(
          (j['authorId'] ?? '').toString(),
          (j['authorName'] ?? '').toString(),
        );
      case 'gift':
        onGift?.call(LiveGiftEvent.fromJson(j));
      case 'redpacket':
        final p = j['packet'];
        if (p is Map) onRedPacket?.call(LiveRedPacket.fromJson(Map<String, dynamic>.from(p)));
      case 'redpacket_grab':
        final p = j['packet'];
        onRedPacketGrab?.call(
          LiveRedPacketGrab.fromJson(j),
          p is Map ? LiveRedPacket.fromJson(Map<String, dynamic>.from(p)) : null,
        );
      case 'cohost_request':
      case 'cohost_active':
        final c = j['cohost'];
        if (c is Map) onCohost?.call(LiveCohost.fromJson(Map<String, dynamic>.from(c)));
      case 'cohost_end':
        onCohostEnd?.call();
      case 'cohost_invite':
        final c = j['cohost'];
        final whip = (j['whipPublishUrl'] ?? '').toString();
        final sfu = j['sfu'] == true;
        if (c is Map && (whip.isNotEmpty || sfu)) {
          onCohostInvite?.call(whip, LiveCohost.fromJson(Map<String, dynamic>.from(c)), sfu: sfu);
        }
      case 'push_status':
        onPushStatus?.call(j['pushActive'] == true);
      case 'pk_invite':
      case 'pk_start':
      case 'pk_score':
        final p = j['pk'];
        if (p is Map) {
          final pk = LivePk.fromJson(Map<String, dynamic>.from(p));
          switch ((j['type'] ?? '').toString()) {
            case 'pk_invite':
              onPkInvite?.call(pk);
            case 'pk_start':
              onPkStart?.call(pk);
            case 'pk_score':
              onPkScore?.call(pk);
          }
        }
      case 'pk_end':
        final p = j['pk'];
        onPkEnd?.call(p is Map ? LivePk.fromJson(Map<String, dynamic>.from(p)) : null);
      case 'pong':
        break;
    }
  }

  void _onDisconnect() {
    if (_disposed) return;
    if (_connected) {
      _connected = false;
      onConnectionChange?.call(false);
    }
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), connect);
  }

  void sendChat(String text) {
    if (!_connected || text.trim().isEmpty) return;
    _sink({'type': 'chat', 'text': text.trim()});
  }

  void sendLike() {
    if (!_connected) return;
    _sink({'type': 'like'});
  }

  void sendCaption({required String text, required String captionId, bool isFinal = true}) {
    if (!_connected || text.trim().isEmpty) return;
    _sink({'type': 'caption', 'text': text.trim(), 'captionId': captionId, 'final': isFinal});
  }

  void sendScreenShare({required bool active}) {
    if (!_connected) return;
    _sink({'type': 'screen_share', 'active': active});
  }

  void _sink(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _connected = false;
  }
}
