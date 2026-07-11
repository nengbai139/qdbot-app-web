import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../api/circle_api.dart';
import '../../session.dart';
import '../../util/meeting_caption.dart';
import '../../util/meeting_minutes.dart';
import '../../util/meeting_translate.dart';
import 'circle_models.dart';
import 'live_room_ws.dart';
import 'meeting_deep_link.dart';
import 'meeting_replay_viewers_sheet.dart';
import 'meeting_invite_sheet.dart';
import 'meeting_virtual_bg.dart';
import 'widgets/live_backdrop_shop_sheet.dart';
import 'widgets/circle_ui.dart';
import 'widgets/circle_room_shell.dart';
import 'widgets/meeting_breakout_sheet.dart';
import 'widgets/meeting_caption_overlay.dart';
import 'widgets/meeting_participants_sheet.dart';


String _fmtLiveKitError(Object e) {
  final s = e.toString();
  if (s.contains('MissingPlugin')) {
    return '浏览器插件未加载，请硬刷新页面（Cmd+Shift+R）后重试';
  }
  if (s.contains('NotAllowed') || s.contains('not allowed') || s.contains('Permission') || s.contains('permission')) {
    return '摄像头/麦克风权限被拒绝，请点「开视频」或「开麦」手动开启';
  }
  return s.replaceFirst('LiveKit Exception: ', 'LiveKit：');
}

bool _isMobilePortrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide < 600 && s.height >= s.width;
}

/// ponytail: LiveKit SFU + circle WS（等候室/静音/字幕/分组）
class MeetingSfuPage extends StatefulWidget {
  final String token;
  final String userId;
  final LiveRoom room;
  final bool isHost;
  final String joinPasscode;
  final bool skipPreJoin;

  const MeetingSfuPage({
    super.key,
    required this.token,
    required this.userId,
    required this.room,
    this.isHost = false,
    this.joinPasscode = '',
    this.skipPreJoin = false,
  });

  @override
  State<MeetingSfuPage> createState() => _MeetingSfuPageState();
}

class _MeetingSfuPageState extends State<MeetingSfuPage> {
  late final CircleApi _api = CircleApi(widget.token);
  Room? _lkRoom;
  LiveRoomWs? _liveWs;
  final _chatCtrl = TextEditingController();
  final _chatMsgs = <LiveMessage>[];
  final _captionLines = <LiveCaption>[];
  List<LiveParticipant> _participants = const [];
  List<LiveParticipant> _lobby = const [];
  bool _connecting = true;
  bool _inLobby = false;
  String _lobbyMessage = '等待主持人准许入会';
  String? _error;
  bool _micOn = false;
  bool _camOn = true;
  bool _screenSharing = false;
  bool _muteAllActive = false;
  bool _allowUnmute = false;
  bool _breakoutActive = false;
  bool _hadBreakout = false;
  Map<String, String> _breakoutAssignments = const {};
  int _breakoutCount = 3;
  String? _livekitRoom;
  MeetingCaptionEngine? _captionEngine;
  var _captionSeq = 0;
  bool _translateOn = false;
  final _chatTranslations = <String, String>{};
  final _captionTranslations = <String, String>{};
  final _translatePending = <String>{};
  LiveCohost? _cohost;
  bool _chatOpen = false;
  bool _preJoinDone = false;
  bool _joiningFromPreJoin = false;
  bool _speakerView = true;
  String? _pinnedIdentity;
  bool _speakHintDismissed = false;
  bool _cohostPromptOpen = false;
  Timer? _cohostPoll;
  Future<void>? _lkConnectInFlight;
  bool _recording = false;
  bool _recordingBusy = false;
  String _virtualBgUrl = '';

  @override
  void initState() {
    super.initState();
    _preJoinDone = widget.skipPreJoin;
    _recording = widget.room.recording;
    _virtualBgUrl = widget.room.coverUrl;
    if (_preJoinDone) {
      _startWs();
      _loadCohost();
      if (widget.isHost) {
        _cohostPoll = Timer.periodic(const Duration(seconds: 2), (_) => _loadCohost());
        _connectLiveKit();
      } else {
        _tryConnectLiveKitAsGuest();
      }
    }
  }

  void _completePreJoin() {
    if (_joiningFromPreJoin) return;
    setState(() => _joiningFromPreJoin = true);
    _startWs();
    _loadCohost();
    setState(() {
      _preJoinDone = true;
      _joiningFromPreJoin = false;
    });
    if (widget.isHost) {
      _cohostPoll?.cancel();
      _cohostPoll = Timer.periodic(const Duration(seconds: 2), (_) => _loadCohost());
      _connectLiveKit();
      return;
    }
    // ponytail: 无等候室时 WS 可能只推 participants；1.5s 后仍未进等候室则直连 LiveKit
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted || _inLobby || _lkRoom != null) return;
      _connectLiveKit();
    });
  }

  void _tryConnectLiveKitAsGuest() {
    if (!mounted || widget.isHost || !_preJoinDone || _inLobby || _lkRoom != null) return;
    _connectLiveKit();
  }

  Future<void> _loadCohost() async {
    try {
      final c = await _api.getLiveCohost(widget.room.roomId);
      if (!mounted) return;
      _applyCohost(c);
    } catch (_) {}
  }

  void _applyCohost(LiveCohost c) {
    final wasPending = _cohost?.isPending == true;
    setState(() => _cohost = c);
    if (widget.isHost && c.isPending && !wasPending) {
      _showSpeakRequestPrompt(c);
    }
  }

  void _showSpeakRequestPrompt(LiveCohost c) {
    if (!mounted || _cohostPromptOpen) return;
    _cohostPromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _cohostPromptOpen = false;
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: kMeetingSurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.record_voice_over_outlined, color: kMeetingAccent, size: 44),
                const SizedBox(height: 12),
                Text('${c.userName} 申请发言', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('也可点右上角「成员」查看并批准', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(ctx); _rejectHand(); }, child: const Text('拒绝'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kMeetingAccent), onPressed: () { Navigator.pop(ctx); _acceptHand(); }, child: const Text('同意发言'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() { if (mounted) _cohostPromptOpen = false; });
    });
  }

  bool get _mayUnmute =>
      widget.isHost ||
      !_muteAllActive ||
      _allowUnmute ||
      (_cohost?.isActive == true && _cohost!.userId == widget.userId);

  void _startWs() {
    _liveWs?.dispose();
    _liveWs = LiveRoomWs(
      token: widget.token,
      roomId: widget.room.roomId,
      joinPasscode: widget.joinPasscode,
      onMessage: (m) {
        if (!mounted) return;
        setState(() => _chatMsgs.add(m));
        if (_translateOn) _queueChatTranslate(m);
      },
      onParticipants: (list) {
        if (!mounted) return;
        final admitted = list.any((p) => p.userId == widget.userId);
        setState(() {
          _participants = list;
          if (admitted) _inLobby = false;
        });
      },
      onLobbyWaiting: (msg) {
        if (!mounted || widget.isHost) return;
        setState(() {
          _inLobby = true;
          _lobbyMessage = msg;
          _connecting = false;
        });
      },
      onLobbyAdmitted: () {
        if (!mounted) return;
        setState(() => _inLobby = false);
        _connectLiveKit(deferAv: true);
      },
      onLobbyList: (list) {
        if (!mounted) return;
        setState(() => _lobby = list);
      },
      onRecording: (active) {
        if (!mounted) return;
        setState(() => _recording = active);
      },
      onRemoved: (reason, {replayPostId}) async {
        if (!mounted) return;
        await _disconnectLiveKit();
        await showMeetingEndedNotice(
          context,
          token: widget.token,
          userId: widget.userId,
          reason: reason,
          replayPostId: replayPostId,
        );
        if (mounted) Navigator.pop(context);
      },
      onMuteAll: (allowUnmute) {
        if (!mounted) return;
        setState(() {
          _muteAllActive = true;
          _allowUnmute = allowUnmute;
        });
        _forceMuteLocal();
      },
      onUnmuteAll: () {
        if (!mounted) return;
        setState(() => _muteAllActive = false);
      },
      onCaption: (c) {
        if (!mounted || c.speakerId == widget.userId) return;
        setState(() => _upsertCaption(c));
        if (_translateOn && c.isFinal) _queueCaptionTranslate(c);
      },
      onBreakoutStarted: (assignments, mainRoom) {
        if (!mounted) return;
        setState(() {
          _breakoutActive = true;
          _hadBreakout = true;
          _breakoutAssignments = assignments;
        });
        final mine = assignments[widget.userId];
        _reconnectLiveKit(mine ?? mainRoom);
      },
      onBreakoutAssign: (livekitRoom) {
        if (!mounted || livekitRoom.isEmpty) return;
        setState(() => _breakoutActive = true);
        _reconnectLiveKit(livekitRoom);
      },
      onBreakoutEnded: (mainRoom) {
        if (!mounted) return;
        setState(() {
          _breakoutActive = false;
          _breakoutAssignments = const {};
        });
        _reconnectLiveKit(mainRoom.isNotEmpty ? mainRoom : widget.room.roomId);
      },
      onCohost: (c) {
        if (!mounted) return;
        _applyCohost(c);
      },
      onCohostEnd: () {
        if (!mounted) return;
        setState(() => _cohost = const LiveCohost());
        if (_muteAllActive && _micOn) _forceMuteLocal();
      },
      onCohostInvite: (whip, c, {sfu = false}) {
        if (!mounted) return;
        setState(() => _cohost = c);
        if (sfu) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('主持人已允许你发言，可以开麦')));
        }
      },
    )..connect();
  }

  void _upsertCaption(LiveCaption c) {
    final i = _captionLines.indexWhere((x) => x.captionId == c.captionId);
    if (i >= 0) {
      _captionLines[i] = c;
    } else {
      _captionLines.add(c);
      while (_captionLines.length > 12) {
        _captionLines.removeAt(0);
      }
    }
  }


  CameraCaptureOptions _cameraCaptureOptions() => CameraCaptureOptions(
        processor: meetingVirtualBgProcessor(_virtualBgUrl),
      );

  Future<void> _showBackdropPicker() async {
    final picked = await showLiveBackdropItemShopSheet(
      context,
      api: _api,
      currentImageUrl: _virtualBgUrl,
      studio: true,
    );
    if (!mounted || picked == null) return;
    try {
      final updated = await _api.applyLiveRoomBackdrop(widget.room.roomId, picked.id);
      if (!mounted) return;
      setState(() => _virtualBgUrl = updated.coverUrl.isNotEmpty ? updated.coverUrl : picked.imageUrl);
      if (_camOn && !_screenSharing) await _restartCameraWithBackdrop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('虚拟背景已更新')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('设置失败: $e')));
    }
  }

  Future<void> _restartCameraWithBackdrop() async {
    final lp = _lkRoom?.localParticipant;
    if (lp == null) return;
    final pub = lp.getTrackPublicationBySource(TrackSource.camera);
    if (pub != null) await lp.removePublishedTrack(pub.sid);
    await lp.setCameraEnabled(true, cameraCaptureOptions: _cameraCaptureOptions());
    if (mounted) setState(() => _camOn = true);
  }

  Future<void> _connectLiveKit({String? roomName, bool deferAv = false}) async {
    final target = roomName ?? _livekitRoom ?? widget.room.roomId;
    if (_lkRoom != null && _livekitRoom == target) return;
    if (_lkConnectInFlight != null) {
      await _lkConnectInFlight;
      if (_lkRoom != null && _livekitRoom == target) return;
    }
    final task = _connectLiveKitImpl(target, deferAv: deferAv);
    _lkConnectInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_lkConnectInFlight, task)) _lkConnectInFlight = null;
    }
  }

  Future<void> _connectLiveKitImpl(String target, {bool deferAv = false}) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await _disconnectLiveKit();
      final cred = await _api.fetchLiveKitToken(widget.room.roomId, livekitRoom: target);
      if (cred.url.isEmpty || cred.token.isEmpty) {
        throw StateError('LiveKit 凭证无效');
      }
      final room = Room(roomOptions: RoomOptions(defaultCameraCaptureOptions: _cameraCaptureOptions()));
      // ponytail: 等候室批准后无用户手势，Safari 会拒绝 getUserMedia；先静音入会再手动开设备
      final enableMic = !deferAv && _micOn && !_muteAllActive;
      final enableCam = !deferAv && _camOn;
      await room
          .connect(
            cred.url,
            cred.token,
            fastConnectOptions: FastConnectOptions(
              microphone: TrackOption(enabled: enableMic),
              camera: TrackOption(enabled: enableCam),
            ),
          )
          .timeout(const Duration(seconds: 25));
      room.addListener(_onRoomUpdate);
      if (!mounted) return;
      setState(() {
        _lkRoom = room;
        _livekitRoom = cred.roomName;
        _connecting = false;
        _inLobby = false;
      });
      if (!deferAv) _syncCaptions();
      if (deferAv && (_camOn || _micOn)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已获准入会，请点「开视频」或「开麦」开启设备')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _fmtLiveKitError(e);
        _connecting = false;
      });
    }
  }

  Future<void> _reconnectLiveKit(String roomName) => _connectLiveKit(roomName: roomName);

  Future<void> _disconnectLiveKit() async {
    _captionEngine?.stop();
    _captionEngine = null;
    _lkRoom?.removeListener(_onRoomUpdate);
    await _lkRoom?.disconnect();
    _lkRoom = null;
  }

  void _onRoomUpdate() {
    if (mounted) setState(() {});
  }

  void _syncCaptions() {
    _captionEngine?.stop();
    if (!_micOn || _lkRoom == null) return;
    _captionEngine = MeetingCaptionEngine();
    final err = _captionEngine!.start(
      onResult: (text, isFinal, {error}) {
        if (error != null && error.isNotEmpty) return;
        final id = 'cap_${widget.userId}_${_captionSeq++}';
        _liveWs?.sendCaption(text: text, captionId: id, isFinal: isFinal);
        if (!mounted) return;
        setState(() => _upsertCaption(LiveCaption(
              captionId: id,
              speakerId: widget.userId,
              speakerName: '我',
              text: text,
              isFinal: isFinal,
            )));
        if (_translateOn && isFinal) {
          _queueCaptionTranslate(LiveCaption(captionId: id, speakerId: widget.userId, speakerName: '我', text: text, isFinal: true));
        }
      },
    );
    if (err != null && err.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('字幕: $err')));
    }
  }

  void _queueChatTranslate(LiveMessage msg) {
    if (msg.msgId.isEmpty || _chatTranslations.containsKey(msg.msgId) || _translatePending.contains(msg.msgId)) return;
    _translatePending.add(msg.msgId);
    translateMeetingLine(token: widget.token, text: msg.text).then((tr) {
      _translatePending.remove(msg.msgId);
      if (!mounted || tr == null || tr.isEmpty) return;
      setState(() => _chatTranslations[msg.msgId] = tr);
    }).catchError((_) {
      _translatePending.remove(msg.msgId);
    });
  }

  void _queueCaptionTranslate(LiveCaption c) {
    if (c.captionId.isEmpty || _captionTranslations.containsKey(c.captionId) || _translatePending.contains(c.captionId)) return;
    _translatePending.add(c.captionId);
    translateMeetingLine(token: widget.token, text: c.text).then((tr) {
      _translatePending.remove(c.captionId);
      if (!mounted || tr == null || tr.isEmpty) return;
      setState(() => _captionTranslations[c.captionId] = tr);
    }).catchError((_) {
      _translatePending.remove(c.captionId);
    });
  }

  Future<void> _shareInvite() async {
    await showMeetingInviteSheet(
      context,
      token: widget.token,
      userId: widget.userId,
      title: widget.room.title,
      roomId: widget.room.roomId,
      passcode: widget.joinPasscode.isNotEmpty
          ? widget.joinPasscode
          : (widget.room.joinPassword.isNotEmpty ? widget.room.joinPassword : null),
    );
  }

  void _copyMeetingId() {
    Clipboard.setData(ClipboardData(text: widget.room.roomId));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制会议号')));
  }

  void _copyInviteLink() {
    final link = meetingJoinLink(
      widget.room.roomId,
      passcode: widget.joinPasscode.isNotEmpty
          ? widget.joinPasscode
          : (widget.room.joinPassword.isNotEmpty ? widget.room.joinPassword : null),
    );
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制邀请链接')));
  }

  Future<void> _forceMuteLocal() async {
    if (_micOn) await _toggleMic(forceOff: true);
  }

  Future<void> _toggleMic({bool forceOff = false}) async {
    if (_muteAllActive && !_mayUnmute && !forceOff) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('主持人已全员静音，请举手申请发言')));
      return;
    }
    final lp = _lkRoom?.localParticipant;
    if (lp == null) return;
    final next = forceOff ? false : !_micOn;
    try {
      await lp.setMicrophoneEnabled(next);
      setState(() => _micOn = next);
      _syncCaptions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fmtLiveKitError(e))));
    }
  }

  Future<void> _toggleCam() async {
    final lp = _lkRoom?.localParticipant;
    if (lp == null) return;
    final next = !_camOn;
    try {
      await lp.setCameraEnabled(next, cameraCaptureOptions: _cameraCaptureOptions());
      setState(() => _camOn = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fmtLiveKitError(e))));
    }
  }

  Future<void> _toggleScreenShare() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('屏幕共享仅支持网页版')));
      return;
    }
    final lp = _lkRoom?.localParticipant;
    if (lp == null) return;
    final next = !_screenSharing;
    await lp.setScreenShareEnabled(next);
    setState(() => _screenSharing = next);
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    try {
      await _api.sendLiveMessage(widget.room.roomId, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleRecording() async {
    if (!widget.isHost || _recordingBusy) return;
    final next = !_recording;
    setState(() => _recordingBusy = true);
    try {
      final room = await _api.setMeetingRecording(widget.room.roomId, next);
      if (!mounted) return;
      setState(() => _recording = room.recording);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(room.recording ? '已开始录制会议' : '已停止录制')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('录制操作失败: $e')));
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  void _openMore() {
    showCircleRoomMoreSheet(
      context,
      meeting: true,
      actions: [
        if (!widget.isHost) ...[
          (icon: Icons.tag, label: '复制会议号', onTap: _copyMeetingId),
          (icon: Icons.link, label: '复制邀请链接', onTap: _copyInviteLink),
        ],
        if (widget.isHost && !_breakoutActive)
          (icon: Icons.grid_view_rounded, label: '开启分组讨论', onTap: _startBreakout),
        if (widget.isHost && _breakoutActive) ...[
          (icon: Icons.tune_rounded, label: '调整分组', onTap: _manageBreakout),
          (icon: Icons.call_merge_rounded, label: '结束分组', onTap: _endBreakout),
        ],
        if (widget.isHost && kIsWeb) (icon: Icons.wallpaper_outlined, label: '选虚拟背景', onTap: _showBackdropPicker),
        if (widget.isHost) (icon: Icons.share_outlined, label: '邀请参会者', onTap: _shareInvite),
        if (widget.isHost && widget.room.isLive)
          (icon: Icons.fiber_manual_record, label: _recording ? '停止录制' : '开始录制', onTap: _recordingBusy ? null : _toggleRecording),
      ],
    );
  }

  void _openParticipants() {
    showMeetingParticipantsSheet(
      context,
      participants: _participants,
      lobby: _lobby,
      isHost: widget.isHost,
      speakRequest: _cohost,
      muteAllActive: _muteAllActive,
      onAcceptHand: widget.isHost ? _acceptHand : null,
      onRejectHand: widget.isHost ? _rejectHand : null,
      onAdmitLobby: widget.isHost
          ? (uid) => _api.admitLobbyParticipant(widget.room.roomId, uid)
          : null,
      onRemoveParticipant: widget.isHost
          ? (uid) => _api.removeLiveParticipant(widget.room.roomId, uid)
          : null,
      onMuteAll: widget.isHost
          ? ({bool allowUnmute = false}) => _api.muteAllMeeting(widget.room.roomId, allowUnmute: allowUnmute)
          : null,
      onUnmuteAll: widget.isHost ? () => _api.unmuteAllMeeting(widget.room.roomId) : null,
    );
  }

  Future<void> _toggleHandRaise() async {
    if (widget.isHost) return;
    if (_cohost?.isActive == true && _cohost!.userId == widget.userId) {
      try {
        await _api.endLiveCohost(widget.room.roomId);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (_cohost?.isPending == true && _cohost!.userId == widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已举手，等待主持人批准')));
      return;
    }
    if (_cohost != null && !_cohost!.isIdle && _cohost!.userId != widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已有其他参会者举手')));
      return;
    }
    try {
      final c = await _api.requestLiveCohost(widget.room.roomId);
      if (!mounted) return;
      setState(() => _cohost = c);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已举手，等待主持人批准')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _acceptHand() async {
    try {
      final c = await _api.acceptLiveCohost(widget.room.roomId);
      if (!mounted) return;
      setState(() => _cohost = c);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已允许 ${c.userName} 发言')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rejectHand() async {
    try {
      await _api.rejectLiveCohost(widget.room.roomId);
      if (!mounted) return;
      setState(() => _cohost = const LiveCohost());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startBreakout() async {
    final plan = await showMeetingBreakoutPlanner(
      context: context,
      participants: _participants,
      hostId: widget.room.hostId,
    );
    if (plan == null) return;
    try {
      final assign = await _api.startMeetingBreakout(
        widget.room.roomId,
        count: plan.count,
        assignments: plan.assignments,
      );
      if (!mounted) return;
      setState(() {
        _breakoutActive = true;
        _hadBreakout = true;
        _breakoutCount = plan.count;
        _breakoutAssignments = assign;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开启分组讨论')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _manageBreakout() async {
    final plan = await showMeetingBreakoutPlanner(
      context: context,
      participants: _participants,
      hostId: widget.room.hostId,
      editing: true,
      initialCount: _breakoutCount,
      initialAssignments: breakoutAssignmentsToGroups(widget.room.roomId, _breakoutAssignments),
    );
    if (plan == null) return;
    try {
      for (final e in plan.assignments.entries) {
        final prev = breakoutAssignmentsToGroups(widget.room.roomId, _breakoutAssignments)[e.key];
        if (prev == e.value) continue;
        final lk = await _api.assignMeetingBreakout(widget.room.roomId, userId: e.key, group: e.value);
        if (!mounted) return;
        setState(() => _breakoutAssignments = {..._breakoutAssignments, e.key: lk});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分组已更新')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _endBreakout() async {
    try {
      await _api.endMeetingBreakout(widget.room.roomId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _offerMinutes(List<LiveMessage> chat, List<LiveCaption> caps, {String? replayPostId}) async {
    final lines = <({String speaker, String text})>[];
    for (final c in caps.where((x) => x.isFinal)) {
      lines.add((speaker: c.speakerName, text: c.text));
    }
    for (final m in chat) {
      lines.add((speaker: m.authorName, text: m.text));
    }
    if (lines.isEmpty || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('生成会议纪要？'),
        content: Text('已记录 ${lines.length} 条发言/聊天'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('跳过')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final minutes = await generateMeetingMinutes(token: widget.token, title: widget.room.title, lines: lines);
    if (minutes == null || minutes.isEmpty || !mounted) return;
    await SessionStore.saveMeetingMinutes(
      roomId: widget.room.roomId,
      title: widget.room.title,
      content: minutes,
      replayPostId: replayPostId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kMeetingSurface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('会议纪要', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white70),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: minutes));
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制')));
                  },
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            if (replayPostId != null && replayPostId.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('主会议录像已保存（仅指定成员可见）', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openMeetingReplay(context, token: widget.token, userId: widget.userId, postId: replayPostId!);
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('观看会议录像'),
                  style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
                ),
              ),
              if (widget.isHost)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showMeetingReplayViewersSheet(
                        context,
                        token: widget.token,
                        userId: widget.userId,
                        roomId: widget.room.roomId,
                      );
                    },
                    icon: const Icon(Icons.people_outline),
                    label: const Text('管理可见成员'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                  ),
                ),
            ],
            if (_hadBreakout)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('各讨论组录像将单独发布（标题含「讨论组 N」）', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ),
            Flexible(child: SingleChildScrollView(child: MarkdownBody(data: minutes))),
          ],
        ),
      ),
    );
  }

  Widget _recordingBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, size: 10, color: Colors.white),
          SizedBox(width: 4),
          Text('REC', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _leave() async {
    if (widget.isHost) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('结束会议？'),
          content: const Text('所有参会者将断开连接'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('结束')),
          ],
        ),
      );
      if (ok != true) return;
      String? replayPostId;
      try {
        final result = await _api.stopLiveRoom(widget.room.roomId);
        replayPostId = result.replayPostId;
      } catch (_) {}
      final chatSnap = List<LiveMessage>.from(_chatMsgs);
      final capSnap = _captionLines.where((c) => c.isFinal).toList();
      await _offerMinutes(chatSnap, capSnap, replayPostId: replayPostId);
    }
    await _disconnectLiveKit();
    _liveWs?.dispose();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _cohostPoll?.cancel();
    _chatCtrl.dispose();
    _disconnectLiveKit();
    _liveWs?.dispose();
    super.dispose();
  }

  List<Participant> get _tiles {
    final room = _lkRoom;
    if (room == null) return const [];
    final out = <Participant>[];
    if (room.localParticipant != null) out.add(room.localParticipant!);
    out.addAll(room.remoteParticipants.values);
    return out;
  }

  int get _pendingCount => _lobby.length + (_cohost?.isPending == true ? 1 : 0) + _participants.where((p) => p.handRaised).length;

  String get _roomSubtitle {
    if (_breakoutActive) return '分组讨论 · ${_tiles.length} 人在线';
    return '${widget.isHost ? "主持人" : "参会者"} · ${_tiles.length} 人在线';
  }

  List<Widget> _chatMessageTiles() {
    return [
      for (final m in _chatMsgs)
        Builder(
          builder: (_) {
            final tr = _chatTranslations[m.msgId];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                      children: [
                        TextSpan(text: '${m.authorName}  ', style: const TextStyle(color: kMeetingAccent, fontWeight: FontWeight.w600, fontSize: 12)),
                        TextSpan(text: m.text),
                      ],
                    ),
                  ),
                  if (tr != null && tr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(tr, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.42))),
                    ),
                ],
              ),
            );
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_preJoinDone) {
      return MeetingPreJoinScreen(
        title: widget.room.title,
        subtitle: widget.room.hostName.isNotEmpty ? '主持人：${widget.room.hostName}' : null,
        roomId: widget.room.roomId,
        inviteLink: meetingJoinLink(
          widget.room.roomId,
          passcode: widget.joinPasscode.isNotEmpty ? widget.joinPasscode : (widget.room.joinPassword.isNotEmpty ? widget.room.joinPassword : null),
        ),
        micOn: _micOn,
        camOn: _camOn,
        joining: _joiningFromPreJoin,
        onMicToggle: () => setState(() => _micOn = !_micOn),
        onCamToggle: () => setState(() => _camOn = !_camOn),
        onJoin: _completePreJoin,
        onCancel: () => Navigator.pop(context),
        hint: '加入后主持人可能要求你在等候室稍候',
      );
    }

    if (_inLobby) {
      return CircleRoomLobbyView(
        meeting: true,
        title: widget.room.title,
        message: _lobbyMessage,
        hostName: widget.room.hostName,
        roomId: widget.room.roomId,
        onLeave: _leave,
      );
    }

    return Scaffold(
      backgroundColor: kMeetingScaffold,
      extendBody: _isMobilePortrait(context),
      body: _connecting
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: kMeetingAccent),
                    const SizedBox(height: 20),
                    Text(
                      '正在加入会议',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.room.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white38),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 20),
                        FilledButton(onPressed: () => _connectLiveKit(), child: const Text('重新连接')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        _isMobilePortrait(context) ? 6 : 10,
                        MediaQuery.paddingOf(context).top + 52,
                        _isMobilePortrait(context) ? 6 : 10,
                        _chatOpen ? 0 : 88,
                      ),
                      child: _buildVideoArea(context),
                    ),
                    MeetingCaptionOverlay(lines: _captionLines, translations: _captionTranslations),
                    if (!widget.isHost && !_speakHintDismissed && _cohost?.userId != widget.userId)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 52,
                        left: 12,
                        right: 12,
                        child: Material(
                          color: kMeetingAccent.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => setState(() => _speakHintDismissed = true),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.front_hand_outlined, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      '想发言？点底部「举手」向主持人申请',
                                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                                    ),
                                  ),
                                  Icon(Icons.close, size: 18, color: Colors.white.withValues(alpha: 0.7)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: CircleRoomTopOverlay(
                        meeting: true,
                        title: widget.room.title,
                        subtitle: _roomSubtitle,
                        onBack: _leave,
                        trailing: [
                          if (_recording) _recordingBadge(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: '成员',
                            onPressed: _openParticipants,
                            icon: Badge(
                              isLabelVisible: widget.isHost && _pendingCount > 0,
                              label: Text('$_pendingCount'),
                              child: const Icon(Icons.people_outline, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_chatOpen)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 88,
                        height: MediaQuery.sizeOf(context).height * 0.38,
                        child: CircleRoomChatPanel(
                          meeting: true,
                          controller: _chatCtrl,
                          onSend: _sendChat,
                          messageTiles: _chatMessageTiles(),
                          onClose: () => setState(() => _chatOpen = false),
                          headerExtra: FilterChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('译', style: TextStyle(fontSize: 11)),
                            selected: _translateOn,
                            onSelected: (v) {
                              setState(() => _translateOn = v);
                              if (v) {
                                for (final m in _chatMsgs) {
                                  _queueChatTranslate(m);
                                }
                                for (final c in _captionLines.where((x) => x.isFinal)) {
                                  _queueCaptionTranslate(c);
                                }
                              }
                            },
                            selectedColor: kMeetingAccent.withValues(alpha: 0.35),
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(color: _translateOn ? Colors.white : Colors.white70),
                            side: BorderSide(color: kMeetingAccent.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),

                    if (widget.isHost && _cohost?.isPending == true)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 88,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: kMeetingAccent.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.front_hand, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${_cohost!.userName} 申请发言',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _rejectHand,
                                  style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
                                  child: const Text('拒绝'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: kMeetingAccent,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  onPressed: _acceptHand,
                                  child: const Text('同意'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: CircleRoomControlBar(
                        children: [
                          CircleRoomControlBtn(
                            icon: _micOn ? Icons.mic : Icons.mic_off,
                            label: _micOn ? '静音' : '开麦',
                            active: _micOn,
                            onTap: () => _toggleMic(),
                          ),
                          if (!widget.isHost)
                            CircleRoomControlBtn(
                              icon: _cohost?.isPending == true && _cohost!.userId == widget.userId
                                  ? Icons.hourglass_top
                                  : (_cohost?.isActive == true && _cohost!.userId == widget.userId ? Icons.front_hand : Icons.front_hand_outlined),
                              label: _cohost?.isActive == true && _cohost!.userId == widget.userId
                                  ? '放下'
                                  : (_cohost?.isPending == true && _cohost!.userId == widget.userId ? '等待' : '举手'),
                              active: _cohost?.isPending == true || (_cohost?.isActive == true && _cohost!.userId == widget.userId),
                              onTap: _toggleHandRaise,
                            ),
                          CircleRoomControlBtn(
                            icon: _camOn ? Icons.videocam : Icons.videocam_off,
                            label: _camOn ? '关视频' : '开视频',
                            active: _camOn,
                            onTap: _toggleCam,
                          ),
                          if (_tiles.length > 1)
                            CircleRoomControlBtn(
                              icon: _speakerView ? Icons.grid_view_rounded : Icons.person_pin_circle_outlined,
                              label: _speakerView ? '画廊' : '主讲',
                              active: _speakerView,
                              onTap: () => setState(() {
                                _speakerView = !_speakerView;
                                if (!_speakerView) _pinnedIdentity = null;
                              }),
                            ),
                          if (kIsWeb)
                            CircleRoomControlBtn(
                              icon: _screenSharing ? Icons.stop_screen_share : Icons.screen_share,
                              label: _screenSharing ? '停共享' : '共享',
                              active: _screenSharing,
                              onTap: _toggleScreenShare,
                            ),
                          CircleRoomControlBtn(
                            icon: _chatOpen ? Icons.chat : Icons.chat_outlined,
                            label: '聊天',
                            active: _chatOpen,
                            onTap: () => setState(() => _chatOpen = !_chatOpen),
                          ),
                          CircleRoomControlBtn(
                            icon: Icons.people_outline,
                            label: '成员',
                            onTap: _openParticipants,
                          ),
                          if (widget.isHost && widget.room.isLive)
                            CircleRoomControlBtn(
                              meeting: true,
                              icon: Icons.fiber_manual_record,
                              label: _recording ? '录制中' : '录制',
                              active: _recording,
                              onTap: _recordingBusy ? null : _toggleRecording,
                            ),
                          CircleRoomControlBtn(icon: Icons.more_horiz, label: '更多', onTap: _openMore),
                          CircleRoomControlBtn(
                            icon: widget.isHost ? Icons.call_end : Icons.logout,
                            label: widget.isHost ? '结束' : '离开',
                            danger: true,
                            onTap: _leave,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildVideoArea(BuildContext context) {
    if (_tiles.isEmpty) {
      return Center(child: Text('等待参会者加入…', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14)));
    }
    if (!_speakerView || _tiles.length <= 1) {
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _tiles.length <= 1 ? 1 : _tiles.length <= 4 ? 2 : 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 16 / 11,
        ),
        itemCount: _tiles.length,
        itemBuilder: (_, i) => _ParticipantTile(
          participant: _tiles[i],
          isLocal: _tiles[i] is LocalParticipant,
        ),
      );
    }

    var focusIdx = 0;
    if (_pinnedIdentity != null) {
      focusIdx = _tiles.indexWhere((p) => p.identity == _pinnedIdentity);
      if (focusIdx < 0) focusIdx = 0;
    } else {
      focusIdx = _tiles.indexWhere((p) => p.isSpeaking);
      if (focusIdx < 0) {
        final remoteIdx = _tiles.indexWhere((p) => p is RemoteParticipant);
        focusIdx = remoteIdx >= 0 ? remoteIdx : 0;
      }
    }
    final focus = _tiles[focusIdx];
    final others = [for (var i = 0; i < _tiles.length; i++) if (i != focusIdx) _tiles[i]];
    final mobile = MediaQuery.sizeOf(context).width < 900;

    Widget thumb(Participant p) {
      return GestureDetector(
        onTap: () => setState(() => _pinnedIdentity = p.identity),
        child: _ParticipantTile(participant: p, isLocal: p is LocalParticipant, compact: true),
      );
    }

    Widget mainTile(Participant p) {
      return GestureDetector(
        onTap: _pinnedIdentity != null ? () => setState(() => _pinnedIdentity = null) : null,
        child: _ParticipantTile(participant: p, isLocal: p is LocalParticipant),
      );
    }

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: mainTile(focus)),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(width: 120, child: thumb(others[i])),
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: mainTile(focus),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(width: 10),
          SizedBox(
            width: 200,
            child: ListView.separated(
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => AspectRatio(
                aspectRatio: 16 / 11,
                child: thumb(others[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool isLocal;
  final bool compact;

  const _ParticipantTile({required this.participant, required this.isLocal, this.compact = false});

  @override
  Widget build(BuildContext context) {
    VideoTrack? video;
    var sharing = false;
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo && pub.track != null && pub.subscribed && !pub.muted) {
        video = pub.track as VideoTrack?;
        sharing = true;
        break;
      }
    }
    if (video == null) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && pub.subscribed && !pub.muted) {
          video = pub.track as VideoTrack?;
          break;
        }
      }
    }
    var micMuted = true;
    for (final pub in participant.audioTrackPublications) {
      if (pub.track != null && pub.subscribed) {
        micMuted = pub.muted;
        break;
      }
    }
    var camOff = video == null;
    if (!camOff && !sharing) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.source == TrackSource.screenShareVideo) continue;
        if (pub.track != null && pub.subscribed && pub.muted) {
          camOff = true;
          break;
        }
      }
    }
    final name = participant.name.isNotEmpty ? participant.name : participant.identity;
    final displayName = sharing ? '$name · 共享' : (isLocal ? '$name（我）' : name);
    final speaking = participant.isSpeaking;
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 10 : 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF18182A),
          border: Border.all(
            color: sharing || speaking ? kMeetingAccent : Colors.white.withValues(alpha: 0.08),
            width: sharing || speaking ? 2 : 1,
          ),
          boxShadow: speaking ? [BoxShadow(color: kMeetingAccent.withValues(alpha: 0.35), blurRadius: 8)] : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              VideoTrackRenderer(video)
            else
              CircleRoomAvatarPlaceholder(name: name, meeting: true),
            Positioned(left: compact ? 4 : 8, bottom: compact ? 4 : 8, child: CircleRoomNameBadge(name: displayName, accent: sharing, icon: sharing ? Icons.screen_share : null)),
            if (camOff)
              Positioned(
                left: compact ? 4 : 8,
                top: compact ? 4 : 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.videocam_off, size: compact ? 12 : 14, color: Colors.white70),
                ),
              ),
            if (micMuted)
              Positioned(
                right: compact ? 4 : 8,
                top: compact ? 4 : 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.mic_off, size: compact ? 12 : 14, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
