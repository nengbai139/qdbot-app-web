import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/circle_api.dart';
import '../../util/meeting_translate.dart';
import '../../util/meeting_caption.dart';
import '../../util/meeting_minutes.dart';
import '../../session.dart';
import '../app_theme.dart';
import 'circle_models.dart';
import 'live_cover_presets.dart';
import 'meeting_deep_link.dart' show meetingInviteText, meetingJoinLink, normalizeLiveTitle, openMeetingReplay;
import 'meeting_invite_sheet.dart';
import 'live_pk_bar.dart';
import 'live_player.dart';
import 'live_publisher.dart';
import 'live_room_page.dart';
import 'live_room_ws.dart';
import 'live_whip_preview.dart';
import 'stream_latch.dart';
import 'widgets/circle_room_shell.dart';
import 'widgets/circle_ui.dart';
import 'widgets/meeting_participants_sheet.dart';
import 'widgets/meeting_caption_overlay.dart';
import 'widgets/live_gift_honor.dart';
import 'widgets/live_audio_unmute.dart';
import 'widgets/live_pk_pip.dart';
import 'widgets/live_backdrop.dart';
import 'widgets/live_host_prep_view.dart';
import 'widgets/live_backdrop_shop_sheet.dart';

bool _isMobilePortrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide < 600 && s.height >= s.width;
}

class LiveHostPage extends StatefulWidget {
  final String token;
  final String userId;
  final LiveRoom? initialRoom;
  final bool meetingMode;

  const LiveHostPage({
    super.key,
    required this.token,
    required this.userId,
    this.initialRoom,
    this.meetingMode = false,
  });

  @override
  State<LiveHostPage> createState() => _LiveHostPageState();
}

class _LiveHostPageState extends State<LiveHostPage> {
  late final CircleApi _api = CircleApi(widget.token);
  final _titleCtrl = TextEditingController();
  LiveRoom? _room;
  bool _busy = false;
  bool _stopping = false;
  bool _loading = true;
  bool? _pushActive;
  final _streamLatch = StreamLatch();
  bool _webPublishing = false;
  bool _screenSharing = false;
  String? _screenShareSpeaker;
  final _earningsNotifier = ValueNotifier<LiveGiftEarnings?>(null);
  LiveCohost? _cohost;
  LivePk? _pk;
  bool _pkPromptOpen = false;
  bool _cohostPromptOpen = false;
  bool _pkResultShown = false;
  Timer? _pushPoll;
  Timer? _earningsPoll;
  Timer? _cohostPoll;
  Timer? _pkPoll;
  LiveRoomWs? _liveWs;
  final _giftBannersNotifier = ValueNotifier<List<LiveGiftEvent>>([]);
  final _honorBurstNotifier = ValueNotifier<LiveGiftEvent?>(null);
  final _recentGiftsNotifier = ValueNotifier<List<LiveGiftEvent>>([]);
  bool _hostSettingsExpanded = false;
  String _draftCoverUrl = '';
  Uint8List? _localCoverBytes;
  int _viewerCount = 0;
  final _meetingMsgs = <LiveMessage>[];
  final _meetingMsgCtrl = TextEditingController();
  final _meetingScrollCtrl = ScrollController();
  String _meetingSince = '';
  bool _meetingChatOpen = false;
  List<LiveParticipant> _participants = const [];
  List<LiveParticipant> _lobby = const [];
  bool _muteAllActive = false;
  bool _captionsOn = false;
  final _captionLines = <LiveCaption>[];
  final _captionTranslations = <String, String>{};
  final _captionTranslatePending = <String>{};
  MeetingCaptionEngine? _captionEngine;
  var _captionSeq = 0;
  bool _meetingTranslateOn = false;
  final _meetingTranslations = <String, String>{};
  final _meetingTranslatePending = <String>{};
  bool _hostCamOn = true;
  bool _hostMicOn = true;
  bool _hostPreJoinDone = false;
  bool _hostPreJoinPending = false;

  bool get _showHostPreJoin {
    if (!kIsWeb || _hostPreJoinDone) return false;
    if (_hostPreJoinPending) return true;
    final room = _room;
    return room != null && room.isLive && room.whipPublishUrl.isNotEmpty;
  }

  String get _displayCoverUrl {
    if (_draftCoverUrl.isNotEmpty) return _draftCoverUrl;
    return _room?.coverUrl ?? '';
  }

  /// 虚拟背景图（已购背景墙 URL）；空则推原始摄像头
  String get _virtualBgUrl => _displayCoverUrl;

  bool get _asMeeting => widget.meetingMode;

  String get _cohostVerb => _asMeeting ? '发言' : '连麦';

  @override
  void initState() {
    super.initState();
    _hostPreJoinDone = !kIsWeb;
    final seed = widget.initialRoom;
    if (seed != null) {
      _room = seed;
      _titleCtrl.text = seed.title;
      _draftCoverUrl = seed.coverUrl;
      _loading = false;
      if ((widget.meetingMode || seed.isMeeting) && seed.isLive) _meetingChatOpen = false;
      _syncPushPoll(seed);
      if (_hostPreJoinDone) _scheduleMeetingAutoPublish();
    } else {
      if (_draftCoverUrl.isEmpty) _draftCoverUrl = liveCoverPresets.first.url;
      _loadMine();
    }
  }

  Future<void> _completeHostPreJoin() async {
    if (_busy) return;
    setState(() {
      _hostPreJoinDone = true;
      _hostPreJoinPending = false;
    });
    final room = _room;
    if (room != null && room.isLive) {
      _scheduleMeetingAutoPublish();
      return;
    }
    await _start(skipPreJoinCheck: true);
  }

  void _scheduleMeetingAutoPublish() {
    if (!_asMeeting || !_hostPreJoinDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final room = _room;
      if (room == null || !room.isLive) return;
      if (kIsWeb && room.whipPublishUrl.isNotEmpty && !_webPublishing && !LiveWebPublisher.publishing) {
        if (!_hostCamOn) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('摄像头已关闭，可在底部栏开启视频')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在开启会议摄像头，请允许浏览器权限')),
        );
        await _toggleWebPublish(room);
      } else if (!kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请在本页点「推流」开启摄像头，或使用 OBS')),
        );
      }
    });
  }

  @override
  void dispose() {
    _pushPoll?.cancel();
    _earningsPoll?.cancel();
    _cohostPoll?.cancel();
    _pkPoll?.cancel();
    if (kIsWeb) LiveWebPublisher.stop();
    _liveWs?.dispose();
    _giftBannersNotifier.dispose();
    _honorBurstNotifier.dispose();
    _recentGiftsNotifier.dispose();
    _earningsNotifier.dispose();
    _titleCtrl.dispose();
    _meetingMsgCtrl.dispose();
    _captionEngine?.stop();
    _meetingScrollCtrl.dispose();
    super.dispose();
  }

  void _syncPushPoll(LiveRoom? room) {
    _pushPoll?.cancel();
    _earningsPoll?.cancel();
    _cohostPoll?.cancel();
    _pkPoll?.cancel();
    _pushPoll = null;
    _earningsPoll = null;
    _cohostPoll = null;
    _pkPoll = null;
    if (room == null || !room.isLive) {
      _stopHostWs();
      if (_pushActive != null) {
        _pushActive = null;
        _streamLatch.reset();
      }
      return;
    }
    _startHostWs(room);
    _checkPushActive(room.roomId);
    if (!_asMeeting) _loadEarnings();
    _loadCohost();
    if (_asMeeting) _fetchMeetingMsgs(room.roomId);
    if (!_asMeeting) {
      _loadPk();
      _pkPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loadPk());
    }
    if (!_asMeeting) {
      _earningsPoll = Timer.periodic(const Duration(seconds: 15), (_) => _loadEarnings());
    }
    _cohostPoll = Timer.periodic(const Duration(seconds: 2), (_) => _loadCohost());
    _pushPoll = Timer.periodic(
      Duration(seconds: _webPublishing ? 1 : 2),
      (_) => _checkPushActive(room.roomId),
    );
  }

  Future<void> _loadEarnings() async {
    final room = _room;
    if (room == null || !room.isLive) return;
    try {
      final e = await _api.myLiveGiftEarnings(roomId: room.roomId);
      if (!mounted) return;
      _earningsNotifier.value = e;
    } catch (_) {}
  }

  void _pushGiftBanner(LiveGiftEvent g) {
    final banners = List<LiveGiftEvent>.from(_giftBannersNotifier.value);
    banners.insert(0, g);
    while (banners.length > 3) {
      banners.removeLast();
    }
    _giftBannersNotifier.value = banners;
    maybeTriggerGiftHonorBurst(gift: g, burstNotifier: _honorBurstNotifier);

    final recent = List<LiveGiftEvent>.from(_recentGiftsNotifier.value);
    recent.insert(0, g);
    while (recent.length > 12) {
      recent.removeLast();
    }
    _recentGiftsNotifier.value = recent;

    _loadEarnings();
    Future.delayed(const Duration(seconds: 5), () {
      final next = List<LiveGiftEvent>.from(_giftBannersNotifier.value);
      next.removeWhere(
        (x) => x.senderName == g.senderName && x.giftName == g.giftName && x.amount == g.amount && x.emoji == g.emoji,
      );
      _giftBannersNotifier.value = next;
    });
  }

  void _startHostWs(LiveRoom room) {
    _liveWs?.dispose();
    _liveWs = LiveRoomWs(
      token: widget.token,
      roomId: room.roomId,
      onMessage: (msg) {
        if (!mounted || !_asMeeting) return;
        _appendMeetingMsg(msg);
      },
      onViewerCount: (n) {
        if (!mounted) return;
        setState(() => _viewerCount = n);
      },
      onParticipants: (list) {
        if (!mounted) return;
        setState(() => _participants = list);
      },
      onLobbyList: (list) {
        if (!mounted) return;
        setState(() => _lobby = list);
      },
      onMuteAll: (_) {
        if (!mounted) return;
        setState(() {
          _muteAllActive = true;
          _cohost = const LiveCohost();
        });
      },
      onUnmuteAll: () {
        if (!mounted) return;
        setState(() => _muteAllActive = false);
      },
      onCaption: (c) {
        if (!mounted || c.speakerId == widget.userId) return;
        setState(() => _upsertCaption(c));
        if (_meetingTranslateOn && c.isFinal) _queueCaptionTranslate(c);
      },
      onScreenShare: (speakerId, speakerName, active) {
        if (!mounted) return;
        setState(() {
          _screenShareSpeaker = active && speakerName.isNotEmpty ? speakerName : null;
        });
      },
      onGift: (g) {
        if (!mounted) return;
        _pushGiftBanner(g);
      },
      onCohost: (c) {
        if (!mounted) return;
        setState(() => _cohost = c);
      },
      onCohostEnd: () {
        if (!mounted) return;
        setState(() => _cohost = const LiveCohost());
      },
      onPkInvite: (pk) {
        if (!mounted) return;
        setState(() => _pk = pk);
        _showPkInvitePrompt(pk);
      },
      onPkStart: (pk) {
        if (!mounted) return;
        _pkResultShown = false;
        setState(() => _pk = pk);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PK 开始 · vs ${pk.opName}'), duration: const Duration(seconds: 3)),
          );
        });
      },
      onPkScore: (pk) {
        if (!mounted) return;
        setState(() => _pk = pk);
      },
      onPkEnd: (pk) {
        if (!mounted) return;
        final prev = _pk;
        setState(() => _pk = null);
        if (!_pkResultShown && prev != null && prev.isActive) {
          _pkResultShown = true;
          _showPkResult(prev);
        }
      },
    )..connect();
    if (!_asMeeting) _loadRecentGifts(room);
  }

  void _stopHostWs() {
    _liveWs?.dispose();
    _liveWs = null;
    if (_viewerCount != 0) _viewerCount = 0;
  }

  String _hostLiveSubtitle(LiveRoom? room) {
    if (room?.isLive != true) return '主播控制台';
    final base = _asMeeting ? '主持中' : '直播中';
    if (_viewerCount > 0) return '$base · $_viewerCount 人在线';
    return base;
  }

  Widget _viewerCountChip({bool compact = false}) {
    if (_viewerCount <= 0) return const SizedBox.shrink();
    final fg = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
    return Padding(
      padding: EdgeInsets.only(right: compact ? 4 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: compact ? 14 : 16, color: fg),
          const SizedBox(width: 3),
          Text('$_viewerCount', style: TextStyle(fontSize: compact ? 12 : 13, color: fg)),
        ],
      ),
    );
  }


  void _appendMeetingMsg(LiveMessage msg) {
    if (_meetingMsgs.any((m) => m.msgId == msg.msgId)) return;
    setState(() {
      _meetingMsgs.add(msg);
      _meetingSince = msg.createdAt;
    });
    if (_asMeeting && _meetingTranslateOn) _queueMeetingTranslate(msg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_meetingScrollCtrl.hasClients) {
        _meetingScrollCtrl.animateTo(
          _meetingScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _queueMeetingTranslate(LiveMessage msg) {
    if (msg.msgId.isEmpty || _meetingTranslations.containsKey(msg.msgId) || _meetingTranslatePending.contains(msg.msgId)) {
      return;
    }
    _meetingTranslatePending.add(msg.msgId);
    translateMeetingLine(token: widget.token, text: msg.text).then((tr) {
      _meetingTranslatePending.remove(msg.msgId);
      if (!mounted || tr == null || tr.isEmpty) return;
      setState(() => _meetingTranslations[msg.msgId] = tr);
    }).catchError((_) {
      _meetingTranslatePending.remove(msg.msgId);
    });
  }


  void _upsertCaption(LiveCaption c) {
    final idx = _captionLines.indexWhere((x) => x.speakerId == c.speakerId && !x.isFinal);
    if (!c.isFinal) {
      if (idx >= 0) {
        _captionLines[idx] = c;
      } else {
        _captionLines.add(c);
      }
      return;
    }
    _captionLines.removeWhere((x) => x.speakerId == c.speakerId && !x.isFinal);
    _captionLines.add(c);
    while (_captionLines.length > 8) {
      _captionLines.removeAt(0);
    }
  }

  void _queueCaptionTranslate(LiveCaption c) {
    if (c.captionId.isEmpty || _captionTranslations.containsKey(c.captionId) || _captionTranslatePending.contains(c.captionId)) {
      return;
    }
    _captionTranslatePending.add(c.captionId);
    translateMeetingLine(token: widget.token, text: c.text).then((tr) {
      _captionTranslatePending.remove(c.captionId);
      if (!mounted || tr == null || tr.isEmpty) return;
      setState(() => _captionTranslations[c.captionId] = tr);
    }).catchError((_) {
      _captionTranslatePending.remove(c.captionId);
    });
  }

  void _onHostSttResult(String text, bool isFinal, {String? error}) {
    if (!mounted) return;
    if (error == 'mic_denied') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音识别需要麦克风权限')),
      );
      setState(() => _captionsOn = false);
      _syncHostCaptions();
      return;
    }
    final name = _room?.hostName.isNotEmpty == true ? _room!.hostName : '主持人';
    if (!isFinal) {
      setState(() => _upsertCaption(LiveCaption(
        captionId: 'draft-${widget.userId}',
        speakerId: widget.userId,
        speakerName: name,
        text: text,
        isFinal: false,
      )));
      return;
    }
    _captionSeq++;
    final cap = LiveCaption(
      captionId: 'cap$_captionSeq',
      speakerId: widget.userId,
      speakerName: name,
      text: text,
      isFinal: true,
    );
    _liveWs?.sendCaption(text: text, captionId: cap.captionId, isFinal: true);
    setState(() => _upsertCaption(cap));
    if (_meetingTranslateOn) _queueCaptionTranslate(cap);
  }


  void _syncScreenShareState() {
    if (!kIsWeb) return;
    final ss = (_webPublishing || LiveWebPublisher.publishing) && LiveWebPublisher.screenSharing;
    if (ss != _screenSharing && mounted) setState(() => _screenSharing = ss);
  }

  Future<void> _toggleScreenShare(LiveRoom room) async {
    if (!kIsWeb || room.whipPublishUrl.isEmpty) return;
    if (!_webPublishing && !LiveWebPublisher.publishing) {
      await _toggleWebPublish(room);
      if (!_webPublishing && !LiveWebPublisher.publishing) return;
    }
    setState(() => _busy = true);
    final err = _screenSharing
        ? await LiveWebPublisher.switchToCamera()
        : await LiveWebPublisher.switchToScreen();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _screenSharing = !_screenSharing;
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final nowSharing = !_screenSharing;
    _liveWs?.sendScreenShare(active: nowSharing);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowSharing ? '正在共享屏幕' : '已切回摄像头'),
        duration: const Duration(seconds: 2),
      ),
    );
    _syncHostCaptions();
  }

  void _syncHostCaptions() {
    if (!_asMeeting || _room?.isLive != true || !_captionsOn) {
      _captionEngine?.stop();
      _captionEngine = null;
      return;
    }
    final publishing = kIsWeb && (_webPublishing || LiveWebPublisher.publishing);
    if (!publishing) {
      _captionEngine?.stop();
      _captionEngine = null;
      return;
    }
    _captionEngine ??= MeetingCaptionEngine();
    if (_captionEngine!.running) return;
    final err = _captionEngine!.start(onResult: _onHostSttResult);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('字幕: $err')));
      setState(() => _captionsOn = false);
    }
  }

  void _toggleCaptions() {
    setState(() => _captionsOn = !_captionsOn);
    _syncHostCaptions();
    if (mounted && _captionsOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('实时字幕已开启（需开摄像头/麦克风）'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _openParticipantsSheet() {
    final room = _room;
    showMeetingParticipantsSheet(
      context,
      participants: _participants,
      lobby: _lobby,
      isHost: true,
      muteAllActive: _muteAllActive,
      onAcceptHand: _acceptCohost,
      onRejectHand: _rejectCohost,
      onMuteAll: room == null ? null : _muteAllMeeting,
      onUnmuteAll: room == null ? null : _unmuteAllMeeting,
      onAdmitLobby: room == null
          ? null
          : (userId) async {
              try {
                await _api.admitLobbyParticipant(room.roomId, userId);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
      onRemoveParticipant: room == null
          ? null
          : (userId) async {
              try {
                await _api.removeLiveParticipant(room.roomId, userId);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
    );
  }

  Future<void> _muteAllMeeting({bool allowUnmute = false}) async {
    final room = _room;
    if (room == null || !room.isLive) return;
    try {
      await _api.muteAllMeeting(room.roomId, allowUnmute: allowUnmute);
      if (!mounted) return;
      setState(() {
        _muteAllActive = true;
        _cohost = const LiveCohost();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(allowUnmute ? '已全员静音，参会者可自行开麦' : '已全员静音'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _unmuteAllMeeting() async {
    final room = _room;
    if (room == null || !room.isLive) return;
    try {
      await _api.unmuteAllMeeting(room.roomId);
      if (!mounted) return;
      setState(() => _muteAllActive = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已允许参会者发言'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showMuteAllDialog() async {
    var allowUnmute = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('全员静音'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('将结束当前发言并禁止参会者开麦，直到你允许发言。'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许参会者自行开麦'),
                value: allowUnmute,
                onChanged: (v) => setDlg(() => allowUnmute = v == true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('静音')),
          ],
        ),
      ),
    );
    if (ok == true) await _muteAllMeeting(allowUnmute: allowUnmute);
  }

  Future<void> _fetchMeetingMsgs(String roomId) async {
    try {
      final items = await _api.listLiveMessages(roomId, since: _meetingSince);
      if (!mounted || items.isEmpty) return;
      for (final msg in items) {
        _appendMeetingMsg(msg);
      }
    } catch (_) {}
  }

  void _sendMeetingChat() {
    final text = _meetingMsgCtrl.text.trim();
    final room = _room;
    if (text.isEmpty || room == null || !room.isLive) return;
    _meetingMsgCtrl.clear();
    final ws = _liveWs;
    if (ws != null && ws.isConnected) {
      ws.sendChat(text);
      return;
    }
    _api.sendLiveMessage(room.roomId, text).then((msg) {
      if (mounted) _appendMeetingMsg(msg);
    }).catchError((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    });
  }

  Widget _buildMeetingChatPanel() {
    return Container(
      decoration: BoxDecoration(
        color: kMeetingChatBg,
        border: Border(top: BorderSide(color: kMeetingAccent.withValues(alpha: 0.35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
            child: Row(
              children: [
                Text('会议聊天', style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('字幕', style: TextStyle(fontSize: 11)),
                  selected: _captionsOn,
                  onSelected: (v) {
                    setState(() => _captionsOn = v);
                    _syncHostCaptions();
                  },
                  selectedColor: kMeetingAccent.withValues(alpha: 0.35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: _captionsOn ? Colors.white : Colors.white70),
                  side: BorderSide(color: kMeetingAccent.withValues(alpha: 0.4)),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('译', style: TextStyle(fontSize: 11)),
                  selected: _meetingTranslateOn,
                  onSelected: (v) {
                    setState(() => _meetingTranslateOn = v);
                    if (v) {
                      for (final m in _meetingMsgs) {
                        _queueMeetingTranslate(m);
                      }
                      for (final c in _captionLines.where((x) => x.isFinal)) {
                        _queueCaptionTranslate(c);
                      }
                    }
                  },
                  selectedColor: kMeetingAccent.withValues(alpha: 0.35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: _meetingTranslateOn ? Colors.white : Colors.white70),
                  side: BorderSide(color: kMeetingAccent.withValues(alpha: 0.4)),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                  onPressed: () => setState(() => _meetingChatOpen = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _meetingMsgs.isEmpty
                ? Center(child: Text('暂无消息', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)))
                : ListView.builder(
                    controller: _meetingScrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    itemCount: _meetingMsgs.length,
                    itemBuilder: (_, i) {
                      final m = _meetingMsgs[i];
                      final tr = _meetingTranslations[m.msgId];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white70),
                                children: [
                                  TextSpan(text: '${m.authorName}: ', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
                                  TextSpan(text: m.text),
                                ],
                              ),
                            ),
                            if (tr != null && tr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, left: 2),
                                child: Text('译: $tr', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45), height: 1.3)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _meetingMsgCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '发送消息…',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onSubmitted: (_) => _sendMeetingChat(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: AppTheme.brandBlue,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: _sendMeetingChat,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadRecentGifts(LiveRoom room) async {
    try {
      final items = await _api.listRoomGifts(room.roomId, limit: 8);
      if (!mounted) return;
      _recentGiftsNotifier.value = items;
    } catch (_) {}
  }

  Future<void> _loadCohost() async {
    final room = _room;
    if (room == null || !room.isLive) return;
    try {
      final c = await _api.getLiveCohost(room.roomId);
      if (!mounted) return;
      final wasPending = _cohost?.isPending == true;
      setState(() => _cohost = c);
      if (_asMeeting && c.isPending && !wasPending) {
        _showMeetingSpeakPrompt(c);
      }
    } catch (_) {}
  }

  void _showMeetingSpeakPrompt(LiveCohost c) {
    if (!mounted || _cohostPromptOpen || _busy) return;
    _cohostPromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _cohostPromptOpen = false;
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.record_voice_over_outlined, color: AppTheme.brandBlue, size: 44),
                const SizedBox(height: 12),
                Text('${c.userName} 申请发言', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(ctx); _rejectCohost(); }, child: const Text('拒绝'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: () { Navigator.pop(ctx); _acceptCohost(); }, child: const Text('同意发言'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() { if (mounted) _cohostPromptOpen = false; });
    });
  }

  Future<void> _loadPk() async {
    final room = _room;
    if (room == null || !room.isLive) return;
    try {
      final pk = await _api.getLivePk(room.roomId);
      if (!mounted) return;
      final next = pk != null && (pk.isActive || pk.isPending) ? pk : null;
      setState(() => _pk = next);
      if (next != null && next.isPending && next.roomB == room.roomId) {
        _showPkInvitePrompt(next);
      }
    } catch (_) {}
  }

  void _showPkResult(LivePk pk) {
    if (!mounted) return;
    final msg = pk.isTie
        ? 'PK 平局 · ${pk.myScore.toInt()} : ${pk.opScore.toInt()} QD'
        : pk.iWon
            ? '🎉 你方胜出！${pk.myScore.toInt()} : ${pk.opScore.toInt()}'
            : '对方胜出 · ${pk.myScore.toInt()} : ${pk.opScore.toInt()}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  void _showPkInvitePrompt(LivePk pk) {
    final room = _room;
    if (!mounted || room == null || _pkPromptOpen || _busy) return;
    if (!pk.isPending || pk.roomB != room.roomId) return;
    _pkPromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pkPromptOpen = false;
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_martial_arts, color: Color(0xFFE5484D), size: 48),
                const SizedBox(height: 12),
                Text('${pk.opName} 邀请 PK', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  '时长 ${pk.durationMin} 分钟 · 观众送礼 QD 计入比分',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _acceptPk();
                              },
                        child: const Text('接受'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : () { Navigator.pop(ctx); _rejectPk(); }, child: const Text('拒绝')),
              ],
            ),
          ),
        ),
      ).whenComplete(() {
        if (mounted) _pkPromptOpen = false;
      });
    });
  }

  Future<void> _invitePk(LiveRoom room) async {
    List<LiveRoom> targets = [];
    try {
      targets = (await _api.listLiveRooms()).where((r) => r.roomId != room.roomId).toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无其他正在直播的房间')));
      return;
    }
    var selected = targets.first.roomId;
    final minutesCtrl = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('发起 PK'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selected,
                decoration: const InputDecoration(labelText: '选择对手直播间'),
                items: targets
                    .map((r) => DropdownMenuItem(value: r.roomId, child: Text('${r.hostName} · ${r.title}', overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDlg(() => selected = v);
                },
              ),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时长（分钟，1-30）'),
              ),
              const SizedBox(height: 8),
              const Text('PK 期间观众送礼 QD 计入比分', style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('邀请')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      minutesCtrl.dispose();
      return;
    }
    final mins = (int.tryParse(minutesCtrl.text.trim()) ?? 5).clamp(1, 30);
    minutesCtrl.dispose();
    setState(() => _busy = true);
    try {
      final pk = await _api.inviteLivePk(room.roomId, selected, minutes: mins.clamp(1, 30));
      if (!mounted) return;
      setState(() => _pk = pk);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已向 ${pk.opName} 发起 PK')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptPk() async {
    final room = _room;
    if (room == null) return;
    setState(() => _busy = true);
    try {
      final pk = await _api.acceptLivePk(room.roomId);
      if (!mounted) return;
      setState(() => _pk = pk);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PK 开始 · vs ${pk.opName}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectPk() async {
    final room = _room;
    if (room == null) return;
    try {
      await _api.rejectLivePk(room.roomId);
      if (!mounted) return;
      setState(() => _pk = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _endPk() async {
    final room = _room;
    if (room == null) return;
    try {
      await _api.endLivePk(room.roomId);
      if (!mounted) return;
      setState(() => _pk = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PK 已结束')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _acceptCohost() async {
    final room = _room;
    if (room == null) return;
    try {
      final c = await _api.acceptLiveCohost(room.roomId);
      if (!mounted) return;
      setState(() => _cohost = c);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已同意 ${c.userName} $_cohostVerb')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rejectCohost() async {
    final room = _room;
    if (room == null) return;
    try {
      await _api.rejectLiveCohost(room.roomId);
      if (!mounted) return;
      setState(() => _cohost = const LiveCohost());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _endCohost() async {
    final room = _room;
    if (room == null) return;
    try {
      await _api.endLiveCohost(room.roomId);
      if (!mounted) return;
      setState(() => _cohost = const LiveCohost());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _checkPushActive(String roomId) async {
    try {
      final active = await _api.liveStreamActive(roomId);
      if (!mounted) return;
      // 网页推流时主播看本地预览，不用 HLS 状态拆掉画面
      if (_webPublishing) {
        if (active) _streamLatch.update(true);
        _syncScreenShareState();
        return;
      }
      final show = _streamLatch.update(active);
      if (_pushActive != show) setState(() => _pushActive = show);
      _syncScreenShareState();
    } catch (_) {}
  }

  Future<void> _loadMine() async {
    try {
      final room = await _api.myLiveRoom();
      if (!mounted) return;
      setState(() {
        _room = room;
        _loading = false;
        if (room != null) {
          _titleCtrl.text = room.title;
          _draftCoverUrl = room.coverUrl;
        }
      });
      _syncPushPoll(room);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _recordingBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 6),
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

  Future<void> _shareMeeting(LiveRoom room) async {
    await showMeetingInviteSheet(
      context,
      token: widget.token,
      userId: widget.userId,
      title: room.title,
      roomId: room.roomId,
      passcode: room.joinPassword.isNotEmpty ? room.joinPassword : null,
    );
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制$label')));
  }

  Future<void> _showCoverPicker({LiveRoom? room, bool studio = false}) async {
    final picked = await showLiveBackdropItemShopSheet(
      context,
      api: _api,
      currentImageUrl: _displayCoverUrl,
      studio: studio,
    );
    if (!mounted || picked == null) return;
    await _applyBackdrop(picked, room: room, studio: studio);
  }

  Future<void> _applyBackdrop(LiveBackdropItem backdrop, {LiveRoom? room, bool studio = false}) async {
    setState(() {
      _draftCoverUrl = backdrop.imageUrl;
      _localCoverBytes = null;
      _busy = true;
    });
    try {
      if (room != null) {
        final updated = await _api.applyLiveRoomBackdrop(room.roomId, backdrop.id);
        if (!mounted) return;
        setState(() {
          _room = updated;
          _draftCoverUrl = updated.coverUrl.isNotEmpty ? updated.coverUrl : backdrop.imageUrl;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(studio ? '背景墙已替换' : '背景墙已设置')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('设置失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _coverPreview({required String coverUrl, Widget? child, bool dimmed = true}) {
    final local = _localCoverBytes;
    if (local != null && local.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(local, fit: BoxFit.cover, gaplessPlayback: true),
          if (dimmed)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.45)],
                ),
              ),
            ),
          if (child != null) Center(child: child),
        ],
      );
    }
    return LiveBackdrop(coverUrl: coverUrl, child: child, dimmed: dimmed);
  }

  Widget _coverSettingTile({LiveRoom? room}) {
    final cover = _displayCoverUrl;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 72,
            height: 40,
            child: _coverPreview(coverUrl: cover, dimmed: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room != null && room.isLive ? '演播室背景墙' : '直播背景', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                cover.isEmpty ? '等待推流时观众看到的背景' : '已设置 · 无推流时显示',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        TextButton(onPressed: _busy ? null : () => _showCoverPicker(room: room), child: const Text('更换')),
      ],
    );
  }

  Future<void> _start({bool skipPreJoinCheck = false}) async {
    if (!skipPreJoinCheck && kIsWeb && !_hostPreJoinDone) {
      final title = _titleCtrl.text.trim();
      if (_room == null && title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入直播标题')));
        return;
      }
      setState(() => _hostPreJoinPending = true);
      return;
    }
    var room = _room;
    if (room == null) {
      final title = _titleCtrl.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入直播标题')));
        return;
      }
      setState(() => _busy = true);
      try {
        room = await _api.createLiveRoom(normalizeLiveTitle(title), roomType: LiveRoom.roomTypeLive, coverUrl: _displayCoverUrl.isNotEmpty ? _displayCoverUrl : liveCoverPresets.first.url);
      } catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
        return;
      }
    }
    if (room.isLive) {
      setState(() => _room = room);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已在直播中，请用 OBS 推流')));
      return;
    }
    setState(() => _busy = true);
    try {
      final live = await _api.startLiveRoom(room.roomId);
      if (!mounted) return;
      setState(() {
        _room = live;
        _busy = false;
      });
      _syncPushPoll(live);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kIsWeb ? '已开播，可点「推流」或使用 OBS' : '已开播，请用 OBS 推流后观众即可观看')),
      );
      if (kIsWeb && live.whipPublishUrl.isNotEmpty && _hostCamOn && !_asMeeting) {
        await _toggleWebPublish(live);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('开播失败: $e')));
    }
  }


  Future<void> _offerMeetingMinutes({
    required String roomId,
    required String title,
    required List<LiveMessage> chat,
    required List<LiveCaption> captions,
    String? replayPostId,
  }) async {
    final lines = <({String speaker, String text})>[];
    for (final c in captions.where((x) => x.isFinal)) {
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
        content: Text('已记录 ${lines.length} 条发言/聊天，可用 AI 生成纪要。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('跳过')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('正在生成会议纪要…')),
          ],
        ),
      ),
    );
    String? minutes;
    Object? err;
    try {
      minutes = await generateMeetingMinutes(token: widget.token, title: title, lines: lines);
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (minutes == null || minutes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err != null ? '$err' : '未能生成纪要')),
      );
      return;
    }
    await SessionStore.saveMeetingMinutes(roomId: roomId, title: title, content: minutes, replayPostId: replayPostId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kMeetingSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.summarize_outlined, color: kMeetingAccent),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('会议纪要', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: '分享',
                    icon: const Icon(Icons.share_outlined, color: Colors.white70),
                    onPressed: () => SharePlus.instance.share(ShareParams(text: minutes!)),
                  ),
                  IconButton(
                    tooltip: '复制',
                    icon: const Icon(Icons.copy, color: Colors.white70),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: minutes!));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制纪要')));
                    },
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              if (replayPostId != null && replayPostId.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('主会议录像已保存（仅参会成员可见）', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
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
              ],
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: MarkdownBody(
                    data: minutes!,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: Colors.white, height: 1.45, fontSize: 14),
                      h1: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      h2: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                      h3: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      listBullet: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _stop() async {
    if (_room == null || _stopping) return;
    _stopping = true;
    final ending = _room!;
    final wasMeeting = _asMeeting;
    final chatSnap = List<LiveMessage>.from(_meetingMsgs);
    final capSnap = _captionLines.where((c) => c.isFinal).toList();
    setState(() => _busy = true);
    if (kIsWeb) LiveWebPublisher.stop();
    setState(() {
      _webPublishing = false;
      _screenSharing = false;
    });
    try {
      final result = await _api.stopLiveRoom(ending.roomId);
      if (!mounted) return;
      if (result.replayPostId != null) {
        final replayId = result.replayPostId!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasMeeting ? '会议已结束，录像已保存（仅参会成员可见）' : '直播已结束，回放已发布到视频圈'),
            action: wasMeeting
                ? SnackBarAction(
                    label: '观看',
                    onPressed: () => openMeetingReplay(context, token: widget.token, userId: widget.userId, postId: replayId),
                  )
                : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasMeeting
                  ? '会议已结束（录像生成中，请稍后在视频圈查看）'
                  : '直播已结束（回放生成中，请稍后在视频圈查看）',
            ),
          ),
        );
      }
      setState(() {
        _room = null;
        _busy = false;
        _titleCtrl.clear();
      });
      if (wasMeeting) {
        await _offerMeetingMinutes(roomId: ending.roomId, title: ending.title, chat: chatSnap, captions: capSnap, replayPostId: result.replayPostId);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stopping = false;
      });
      final msg = e.toString();
      final hint = msg.contains('not host or invalid state')
          ? '直播可能已结束，请返回列表刷新'
          : '停播失败: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hint)));
    }
  }

  Future<void> _toggleWebPublish(LiveRoom room) async {
    if (!kIsWeb || room.whipPublishUrl.isEmpty) return;
    if (_webPublishing || LiveWebPublisher.publishing) {
      LiveWebPublisher.stop();
      if (!mounted) return;
      setState(() {
        _webPublishing = false;
        _screenSharing = false;
      });
      _syncHostCaptions();
      return;
    }
    setState(() {
      _busy = true;
      _webPublishing = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final err = await LiveWebPublisher.start(room.whipPublishUrl, audio: _hostMicOn, video: _hostCamOn, backdropUrl: _virtualBgUrl);
    LiveWebPublisher.attachPreview();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    LiveWebPublisher.attachPreview();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) _webPublishing = false;
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_asMeeting ? '摄像头开启失败: $err' : '网页推流失败: $err'),
          action: _asMeeting
              ? SnackBarAction(label: '重试', onPressed: () => _toggleWebPublish(room))
              : null,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_asMeeting ? '摄像头已开启，参会者即将看到画面' : '网页推流已开启，等待几秒出画面'),
        ),
      );
      _checkPushActive(room.roomId);
      _syncHostCaptions();
      _pushPoll?.cancel();
      _pushPoll = Timer.periodic(const Duration(seconds: 1), (_) => _checkPushActive(room.roomId));
    }
  }

  void _openViewer() {
    final room = _room;
    if (room == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRoomPage(token: widget.token, userId: widget.userId, roomId: room.roomId),
      ),
    );
  }

  Future<void> _sendRedPacket(LiveRoom room) async {
    final amountCtrl = TextEditingController(text: '10');
    final countCtrl = TextEditingController(text: '5');
    final titleCtrl = TextEditingController(text: '恭喜发财');
    double balance = 0;
    try {
      balance = await _api.getQdBalance();
    } catch (_) {}
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发福袋'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('钱包余额 ${balance.toStringAsFixed(0)} QD', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '祝福语'),
            ),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '总金额（QD币）'),
            ),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '份数'),
            ),
            const SizedBox(height: 8),
            Text(
              '从 QD币钱包扣款 · 观众抢到入账 · 5 分钟未领完退回',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('发放')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final count = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (amount <= 0 || count <= 0) return;
    setState(() => _busy = true);
    try {
      await _api.createLiveRedPacket(
        room.roomId,
        totalAmount: amount,
        totalCount: count,
        title: titleCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('红包已发出（${amount.toInt()} QD）')));
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      if (msg.contains('402') || msg.contains('不足') || msg.contains('insufficient')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('QD币不足，请先去「我的 → QD币钱包」充值')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      amountCtrl.dispose();
      countCtrl.dispose();
      titleCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _urlRow(String label, String url) {
    return CircleCopyTile(
      label: label,
      value: url,
      onCopy: url.isEmpty ? null : () => _copy(label, url),
    );
  }

  Widget _meetingCameraBanner(LiveRoom room) {
    if (!_asMeeting || !room.isLive || _pushActive == true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: const Color(0xFFE5484D).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.videocam_off_outlined, color: Color(0xFFE5484D), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kIsWeb ? '摄像头未开启，参会者暂看不到你' : '请点「开摄像头」或使用 OBS',
                  style: const TextStyle(fontSize: 13, color: Color(0xFFE5484D)),
                ),
              ),
              if (kIsWeb && room.whipPublishUrl.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : () => _toggleWebPublish(room),
                  child: Text(_webPublishing ? '开启中…' : '开启'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meetingIdBanner(LiveRoom room) {
    if (!_asMeeting) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _copy('会议邀请链接', meetingJoinLink(room.roomId, passcode: room.joinPassword.isNotEmpty ? room.joinPassword : null)),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.meeting_room_outlined, color: Color(0xFF6366F1), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('会议号（分享给参会者）', style: TextStyle(fontSize: 12, color: Color(0xFF6366F1))),
                      const SizedBox(height: 2),
                      Text(room.roomId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (room.hasJoinPassword) ...[
                        const SizedBox(height: 4),
                        Text('入会密码：${room.joinPassword}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '分享会议',
                  icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF6366F1)),
                  onPressed: () => _shareMeeting(room),
                ),
                const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF6366F1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _primaryAction(LiveRoom? room) {
    if (_busy) {
      return const FilledButton(
        onPressed: null,
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (room == null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _start,
        icon: const Icon(Icons.sensors),
        label: const Text('创建并开播'),
      );
    }
    if (room.isLive) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D), minimumSize: const Size.fromHeight(48)),
        onPressed: _stop,
        icon: const Icon(Icons.stop_rounded),
        label: const Text('结束直播'),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: _start,
      icon: const Icon(Icons.sensors),
      label: const Text('开始直播'),
    );
  }

  Widget _hostPreviewFrame(LiveRoom room) {
    final mobilePortrait = _isMobilePortrait(context);
    final pkActive = !_asMeeting && _pk?.isActive == true && _pk!.opPlayUrl.isNotEmpty;
    final pkSplit = pkActive && !mobilePortrait;
    return Stack(
      fit: StackFit.expand,
      children: [
        _HostPreviewPane(
          key: ValueKey('host-preview-${room.roomId}-${_displayCoverUrl.hashCode}'),
          room: room,
          pushActive: _pushActive,
          webPublishing: _webPublishing,
          pk: _pk,
          pkSplitLayout: pkSplit,
          cohost: _cohost,
          coverUrl: _displayCoverUrl,
          streamReconnecting: _streamLatch.reconnecting,
          localCoverBytes: _localCoverBytes,
        ),
        if (!_asMeeting && _pk?.isActive == true)
          Positioned(left: 8, right: 8, top: 8, child: LivePkBar(pk: _pk!)),
        if (pkActive && mobilePortrait && _pk != null)
          Positioned(
            right: 12,
            bottom: (_cohost?.isActive == true && _cohost!.pushActive) ? 82 : 12,
            width: 112,
            height: 63,
            child: LivePkOpponentPiP(pk: _pk!),
          ),
        if (!_asMeeting) _HostGiftOverlay(notifier: _giftBannersNotifier),
        if (!_asMeeting)
          ValueListenableBuilder<LiveGiftEvent?>(
            valueListenable: _honorBurstNotifier,
            builder: (_, gift, __) => LiveGiftHonorBurst(key: ValueKey('host-burst-${gift?.amount}-${gift?.senderName}'), gift: gift),
          ),
        if (_asMeeting && _captionsOn)
          MeetingCaptionOverlay(lines: _captionLines, translations: _captionTranslations),
        if (_asMeeting && _screenShareSpeaker != null)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kMeetingAccent.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.screen_share, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text('$_screenShareSpeaker 正在共享屏幕', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
        const LiveAudioUnmuteOverlay(),
      ],
    );
  }


  Widget _buildMobileLiveAlerts(LiveRoom room) {
    final items = <Widget>[];
    if (_pk?.isPending == true && _pk!.roomB == room.roomId && !_asMeeting) {
      items.add(
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE5484D).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: Text('${_pk!.opName} 邀请 PK', style: const TextStyle(fontSize: 12))),
              TextButton(onPressed: _busy ? null : _rejectPk, child: const Text('拒绝')),
              FilledButton(onPressed: _busy ? null : _acceptPk, child: const Text('接受')),
            ],
          ),
        ),
      );
    }
    if (_cohost?.isPending == true) {
      items.add(
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (_asMeeting ? kMeetingAccent : AppTheme.brandBlue).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(child: Text('${_cohost!.userName} 申请$_cohostVerb', style: const TextStyle(fontSize: 12))),
              TextButton(onPressed: _rejectCohost, child: const Text('拒绝')),
              FilledButton(onPressed: _acceptCohost, child: const Text('同意')),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(children: items);
  }

  Widget _buildHostSettingsPanel(LiveRoom room) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _meetingIdBanner(room),
        _meetingCameraBanner(room),
        _coverSettingTile(room: room),
        const SizedBox(height: 12),
        if (!_asMeeting)
          ValueListenableBuilder<LiveGiftEarnings?>(
          valueListenable: _earningsNotifier,
          builder: (_, e, __) {
            if (e == null || (e.giftCount <= 0 && e.totalAmount <= 0)) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE5484D).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '本场礼物 ${e.totalAmount.toStringAsFixed(0)} QD · ${e.giftCount} 次',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            );
          },
        ),
        if (!_asMeeting)
          ValueListenableBuilder<List<LiveGiftEvent>>(
          valueListenable: _recentGiftsNotifier,
          builder: (_, recent, __) {
            if (recent.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('最近打赏', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...recent.take(6).map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: LiveGiftBanner(gift: g, compact: true),
                      ),
                    ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
        if (_pushActive == false && !_webPublishing)
          CircleStatusBanner(
            kind: CircleBannerKind.warning,
            text: kIsWeb
                ? '尚未检测到推流。可点「推流」用摄像头，或在电脑 OBS 推流。'
                : '画面需电脑 OBS 推流，下方复制服务器与密钥。',
          )
        else if (_pushActive == true)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: CircleStatusBanner(kind: CircleBannerKind.success, text: '推流已连接，观众可以观看'),
          ),
        circleSectionTitle(context, kIsWeb ? 'OBS 推流（可选）' : 'OBS 推流设置'),
        Text('OBS Studio → 设置 → 推流 → 服务选「自定义」', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        _urlRow('服务器', room.rtmpServer),
        _urlRow('串流密钥', room.streamKey),
        _urlRow('HLS 播放地址', room.playUrl),
      ],
    );
  }


  void _openLiveStreamSettings(LiveRoom room) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kLiveSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Text('推流与背景墙', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _coverSettingTile(room: room),
            const SizedBox(height: 12),
            if (_pushActive == false && !_webPublishing)
              CircleStatusBanner(
                kind: CircleBannerKind.warning,
                text: kIsWeb ? '可点底部「推流」开启摄像头，或使用 OBS。' : '画面需 OBS 推流，复制下方服务器与密钥。',
              )
            else if (_pushActive == true)
              const CircleStatusBanner(kind: CircleBannerKind.success, text: '推流已连接，观众可以观看'),
            const SizedBox(height: 16),
            Text('OBS Studio → 设置 → 推流 → 自定义', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            _urlRow('服务器', room.rtmpServer),
            _urlRow('串流密钥', room.streamKey),
            _urlRow('HLS 播放', room.playUrl),
          ],
        ),
      ),
    );
  }

  void _openHostMoreSheet(LiveRoom room) {
    final actions = <({IconData icon, String label, VoidCallback? onTap})>[
      (icon: Icons.visibility_outlined, label: _asMeeting ? '参会者视角' : '观众视角', onTap: _openViewer),
      if (!_asMeeting) (icon: Icons.wallpaper_outlined, label: '更换背景墙', onTap: _busy ? null : () => _showCoverPicker(room: room, studio: true)),
      if (!_asMeeting) (icon: Icons.tune, label: '推流设置', onTap: () => _openLiveStreamSettings(room)),
      if (_asMeeting) (icon: Icons.share_outlined, label: '邀请参会者', onTap: () => _shareMeeting(room)),
      if (_asMeeting) (icon: Icons.tune, label: '会议设置', onTap: () => setState(() => _hostSettingsExpanded = !_hostSettingsExpanded)),
      if (!_asMeeting) (icon: Icons.redeem_outlined, label: '发福袋', onTap: _busy ? null : () => _sendRedPacket(room)),
      if (!_asMeeting && _pk == null) (icon: Icons.sports_martial_arts_outlined, label: '发起 PK', onTap: _busy ? null : () => _invitePk(room)),
      if (!_asMeeting && _pk?.isActive == true) (icon: Icons.flag_outlined, label: '结束 PK', onTap: _endPk),
      if (_cohost?.isActive == true) (icon: Icons.call_end, label: '结束$_cohostVerb', onTap: _endCohost),
    ];
    showCircleRoomMoreSheet(context, meeting: _asMeeting, actions: actions);
  }

  Widget _buildHostMobileControlBar(LiveRoom room) {
    return CircleRoomControlBar(
      children: [
        if (_asMeeting)
          CircleRoomControlBtn(
            meeting: true,
            icon: Icons.people_outline,
            label: '成员',
            onTap: _openParticipantsSheet,
          ),
        if (_asMeeting)
          CircleRoomControlBtn(
            meeting: true,
            icon: _muteAllActive ? Icons.mic : Icons.mic_off,
            label: _muteAllActive ? '允许发言' : '全员静音',
            active: _muteAllActive,
            onTap: _muteAllActive ? _unmuteAllMeeting : _showMuteAllDialog,
          ),
        if (!_asMeeting && room.isLive)
          CircleRoomControlBtn(
            meeting: false,
            icon: Icons.redeem_outlined,
            label: '福袋',
            onTap: _busy ? null : () => _sendRedPacket(room),
          ),
        if (!_asMeeting && room.isLive && _pk == null)
          CircleRoomControlBtn(
            meeting: false,
            icon: Icons.sports_martial_arts_outlined,
            label: 'PK',
            onTap: _busy ? null : () => _invitePk(room),
          ),
        if (!_asMeeting && room.isLive)
          CircleRoomControlBtn(
            meeting: false,
            icon: Icons.wallpaper_outlined,
            label: '装修',
            onTap: _busy ? null : () => _showCoverPicker(room: room, studio: true),
          ),
        CircleRoomControlBtn(
          meeting: _asMeeting,
          icon: _webPublishing ? Icons.videocam_off : Icons.videocam,
          label: _asMeeting ? (_webPublishing ? '关视频' : '开视频') : (_webPublishing ? '停推流' : '推流'),
          active: _webPublishing,
          enabled: kIsWeb && room.whipPublishUrl.isNotEmpty && !_busy,
          onTap: _busy ? null : () => _toggleWebPublish(room),
        ),
        if (_asMeeting && kIsWeb && (_webPublishing || LiveWebPublisher.publishing))
          CircleRoomControlBtn(
            meeting: true,
            icon: _screenSharing ? Icons.stop_screen_share : Icons.screen_share,
            label: _screenSharing ? '停共享' : '共享',
            active: _screenSharing,
            onTap: _busy ? null : () => _toggleScreenShare(room),
          ),
        if (_asMeeting)
          CircleRoomControlBtn(
            meeting: true,
            icon: _meetingChatOpen ? Icons.chat : Icons.chat_outlined,
            label: '聊天',
            active: _meetingChatOpen,
            onTap: () => setState(() => _meetingChatOpen = !_meetingChatOpen),
          ),
        if (_asMeeting)
          CircleRoomControlBtn(
            meeting: true,
            icon: Icons.closed_caption_outlined,
            label: '字幕',
            active: _captionsOn,
            onTap: _toggleCaptions,
          ),
        CircleRoomControlBtn(
          meeting: _asMeeting,
          icon: Icons.more_horiz,
          label: '更多',
          onTap: () => _openHostMoreSheet(room),
        ),
      ],
    );
  }

  Widget _buildMobileLiveBody(LiveRoom room) {
    final subtitle = _asMeeting
        ? '会议号 ${room.roomId}${_viewerCount > 0 ? ' · $_viewerCount 人' : ''}'
        : (_viewerCount > 0 ? '$_viewerCount 人在看' : (_pushActive == true || _webPublishing ? '推流中' : '等待推流'));
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top + 52),
            if (_asMeeting) _meetingCameraBanner(room),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DecoratedBox(
                  decoration: circleRoomVideoFrameDecoration(_asMeeting),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(color: Colors.black, child: _hostPreviewFrame(room)),
                  ),
                ),
              ),
            ),
            _buildMobileLiveAlerts(room),
            if (_asMeeting && _meetingChatOpen)
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.28, child: _buildMeetingChatPanel()),
            if (_hostSettingsExpanded)
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.32, child: _buildHostSettingsPanel(room)),
            _buildHostMobileControlBar(room),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CircleRoomTopOverlay(
            meeting: _asMeeting,
            title: room.title,
            subtitle: subtitle,
            onBack: () => Navigator.of(context).pop(),
            trailing: [
              if (_asMeeting && room.isLive && (_pushActive == true || _webPublishing)) _recordingBadge(),
              if (!_asMeeting && room.isLive) _viewerCountChip(compact: true),
              if (!_asMeeting && room.isLive)
                TextButton(
                  onPressed: _busy ? null : _stop,
                  child: const Text('结束', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_showHostPreJoin) {
      final room = _room;
      final draftTitle = _titleCtrl.text.trim();
      final title = room?.title ?? (draftTitle.isNotEmpty ? draftTitle : (_asMeeting ? '我的会议' : '直播'));
      return MeetingPreJoinScreen(
        meeting: _asMeeting,
        title: title,
        subtitle: room != null && room.isLive && room.hostName.isNotEmpty ? '主持人：${room.hostName}' : null,
        roomId: room?.roomId,
        inviteLink: room != null
            ? meetingJoinLink(room.roomId, passcode: room.joinPassword.isNotEmpty ? room.joinPassword : null)
            : null,
        joinLabel: room?.isLive == true
            ? (_asMeeting ? '进入会议' : '开始推流')
            : (_asMeeting ? '开始会议' : '开始直播'),
        hint: _asMeeting ? '进入后将向参会者开启画面' : '确认设备后开始向观众推流',
        micOn: _hostMicOn,
        camOn: _hostCamOn,
        joining: _busy,
        onMicToggle: () => setState(() => _hostMicOn = !_hostMicOn),
        onCamToggle: () => setState(() => _hostCamOn = !_hostCamOn),
        onJoin: _completeHostPreJoin,
        onCancel: () {
          if (_hostPreJoinPending && _room == null) {
            setState(() => _hostPreJoinPending = false);
          } else {
            Navigator.pop(context);
          }
        },
      );
    }
    final room = _room;
    if (!_asMeeting && (room == null || !room.isLive)) {
      return LiveHostPrepView(
        titleController: _titleCtrl,
        coverUrl: _displayCoverUrl,
        localCoverBytes: _localCoverBytes,
        busy: _busy,
        resuming: room != null,
        onPickCover: () => _showCoverPicker(room: room),
        onStart: _start,
        onClose: () => Navigator.pop(context),
        onObsHelp: () => showLiveObsHelpSheet(context),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final liveStudio = !_asMeeting && room?.isLive == true;
    final meetingStudio = _asMeeting && room?.isLive == true && _isMobilePortrait(context);
    final useStudio = liveStudio || meetingStudio;
    return Scaffold(
      backgroundColor: useStudio ? (_asMeeting ? kMeetingScaffold : Colors.black) : null,
      extendBody: useStudio,
      appBar: useStudio
          ? null
          : circleSubAppBar(
              context,
              title: _asMeeting ? '视频会议' : '我要开播',
              subtitle: _hostLiveSubtitle(room),
              meetingMode: _asMeeting,
              backgroundColor: _asMeeting ? kMeetingSurface : (useStudio ? kLiveSurface : null),
              foregroundColor: (_asMeeting || useStudio) ? Colors.white : null,
              actions: [
                if (_asMeeting && room != null && room.isLive)
                  IconButton(
                    tooltip: '参会成员',
                    icon: Badge(
                      isLabelVisible: _lobby.isNotEmpty || _participants.any((p) => p.handRaised),
                      label: _lobby.isNotEmpty ? Text('${_lobby.length}') : null,
                      child: const Icon(Icons.groups_outlined),
                    ),
                    onPressed: _openParticipantsSheet,
                  ),
                if (room != null && room.isLive) _viewerCountChip(),
                if (room != null && room.isLive && !useStudio)
                  TextButton(onPressed: _openViewer, child: const Text('观众视角')),
                const SizedBox(width: 4),
              ],
            ),
      body: useStudio
          ? _buildMobileLiveBody(room!)
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          if (room == null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      labelText: '直播标题',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _coverSettingTile(),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _coverPreview(
                        coverUrl: _displayCoverUrl,
                        child: Text(
                          '开播前预览背景',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '填写标题后在 App 点「创建并开播」；推流画面需在电脑上使用 OBS Studio。',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ] else ...[
            circleRoomTitleHeader(
              meeting: _asMeeting,
              title: room.title,
              subtitle: _asMeeting
                  ? '主持中 · 会议号 ${room.roomId}'
                  : (room.isLive ? '直播中 · 互动打赏' : '已创建，待开播'),
            ),
            if (room.isLive && _viewerCount > 0) ...[
              const SizedBox(height: 4),
              Text('$_viewerCount 人在线', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
            if (_asMeeting && room.isLive) ...[
              const SizedBox(height: 12),
              SizedBox(height: 220, child: _buildMeetingChatPanel()),
            ],
            const SizedBox(height: 6),
            Text(
              room.isLive ? (_asMeeting ? '会议进行中' : '等待或已接收 OBS 推流') : '已创建，点击开始直播',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (!room.isLive) ...[
              const SizedBox(height: 12),
              _coverSettingTile(room: room),
            ],
            if (!_asMeeting && room.isLive)
              ValueListenableBuilder<LiveGiftEarnings?>(
                valueListenable: _earningsNotifier,
                builder: (_, e, __) {
                  if (e == null || (e.giftCount <= 0 && e.totalAmount <= 0)) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5484D).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.monetization_on_outlined, color: Color(0xFFE5484D), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '本场礼物 ${e.totalAmount.toStringAsFixed(0)} QD · ${e.giftCount} 次',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (!_asMeeting && room.isLive) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _sendRedPacket(room),
                icon: const Icon(Icons.redeem_outlined),
                label: const Text('发福袋红包'),
              ),
            ],
            if (!_asMeeting && room.isLive && _pk == null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _invitePk(room),
                icon: const Icon(Icons.sports_martial_arts_outlined),
                label: const Text('发起 PK 对战'),
              ),
            ],
            if (!_asMeeting && room.isLive && _pk?.isPending == true && _pk!.roomB == room.roomId) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sports_martial_arts, color: Color(0xFFE5484D)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_pk!.opName} 邀请 PK（${_pk!.durationMin} 分钟）', style: const TextStyle(fontSize: 13))),
                    TextButton(onPressed: _busy ? null : _rejectPk, child: const Text('拒绝')),
                    FilledButton(onPressed: _busy ? null : _acceptPk, child: const Text('接受')),
                  ],
                ),
              ),
            ],
            if (!_asMeeting && room.isLive && _pk?.isPending == true && _pk!.inviterRoom == room.roomId && _pk!.roomB != room.roomId) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top),
                    const SizedBox(width: 10),
                    Expanded(child: Text('等待 ${_pk!.opName} 接受 PK…', style: const TextStyle(fontSize: 13))),
                    TextButton(onPressed: _rejectPk, child: const Text('取消')),
                  ],
                ),
              ),
            ],
            if (!_asMeeting && room.isLive && _pk?.isActive == true) ...[
              const SizedBox(height: 10),
              LivePkBar(pk: _pk!),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _endPk,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('结束 PK'),
                ),
              ),
            ],
            if (room.isLive && _cohost?.isPending == true) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.brandBlue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic_none_outlined, color: AppTheme.brandBlue),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_cohost!.userName} 申请$_cohostVerb', style: const TextStyle(fontSize: 13))),
                    TextButton(onPressed: _rejectCohost, child: const Text('拒绝')),
                    FilledButton(onPressed: _acceptCohost, child: const Text('同意')),
                  ],
                ),
              ),
            ],
            if (room.isLive && _cohost?.isActive == true) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _endCohost,
                  icon: const Icon(Icons.call_end, size: 18),
                  label: Text('结束 ${_cohost!.userName} $_cohostVerb'),
                ),
              ),
            ],
            if (room.isLive) ...[
              const SizedBox(height: 12),
              _coverSettingTile(room: room),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _hostPreviewFrame(room),
                ),
              ),
              if (_pushActive == true && room.playUrl.isNotEmpty && !_webPublishing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('推流成功，画面已连接', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
            ],
            if (kIsWeb && room.isLive && room.whipPublishUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              circleSectionTitle(context, '网页推流（无需 OBS）'),
              Text(
                '使用本机摄像头/麦克风，点一次即可推流。首次会请求浏览器权限。',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _toggleWebPublish(room),
                icon: Icon(_webPublishing ? Icons.videocam_off : Icons.videocam),
                label: Text(_webPublishing ? '停止网页推流' : '网页一键推流'),
              ),
            ],
            const SizedBox(height: 20),
            if (room.isLive && _pushActive == false && !_webPublishing)
              CircleStatusBanner(
                kind: CircleBannerKind.warning,
                text: kIsWeb
                    ? '尚未检测到推流。可点「网页一键推流」，或在电脑 OBS 中推流。'
                    : '网页/App 只能「开播」标记房间；画面要靠电脑上的 OBS Studio 推流。\n'
                        '1. 在 Windows/Mac 安装并打开 OBS Studio（obsproject.com）\n'
                        '2. OBS → 设置 → 推流 → 服务选「自定义」\n'
                        '3. 复制下方「服务器」「串流密钥」填入 OBS\n'
                        '4. 点 OBS 窗口右下角「开始推流」（不是本页按钮）\n'
                        '5. 连不上时：阿里云安全组放行 TCP 1935',
              )
            else if (room.isLive && _pushActive == true)
              const CircleStatusBanner(kind: CircleBannerKind.success, text: '推流已连接，观众可以观看'),
            if (room.isLive && _pushActive != null) const SizedBox(height: 16),
            circleSectionTitle(context, kIsWeb ? 'OBS 推流（可选）' : 'OBS 推流设置（电脑软件，非本页按钮）'),
            Text('在 OBS Studio：设置 → 推流 → 服务选「自定义」', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            _urlRow('服务器', room.rtmpServer),
            _urlRow('串流密钥', room.streamKey),
            _urlRow('HLS 播放地址', room.playUrl),
          ],
        ],
      ),
      bottomNavigationBar: useStudio
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _primaryAction(room) ?? const SizedBox.shrink(),
              ),
            ),
    );
  }
}

/// 打赏飘条：独立监听，不触发预览区重建
class _HostGiftOverlay extends StatelessWidget {
  final ValueNotifier<List<LiveGiftEvent>> notifier;
  const _HostGiftOverlay({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LiveGiftEvent>>(
      valueListenable: notifier,
      builder: (_, banners, __) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: 10,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: banners
                .map(
                  (g) => LiveGiftBanner(
                    key: ValueKey('host-gift-${g.senderName}-${g.giftName}-${g.amount}-${g.emoji}'),
                    gift: g,
                    compact: true,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

/// ponytail: 与打赏/收益状态隔离，避免 setState 拆掉 HLS / 摄像头预览
class _HostPreviewPane extends StatefulWidget {
  final LiveRoom room;
  final bool? pushActive;
  final bool webPublishing;
  final LivePk? pk;
  final bool pkSplitLayout;
  final LiveCohost? cohost;
  final String coverUrl;
  final bool streamReconnecting;
  final Uint8List? localCoverBytes;

  const _HostPreviewPane({
    super.key,
    required this.room,
    required this.pushActive,
    required this.webPublishing,
    required this.pk,
    required this.pkSplitLayout,
    required this.cohost,
    required this.coverUrl,
    required this.streamReconnecting,
    this.localCoverBytes,
  });

  @override
  State<_HostPreviewPane> createState() => _HostPreviewPaneState();
}

class _HostPreviewPaneState extends State<_HostPreviewPane> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _statusText() {
    if (widget.webPublishing) return null;
    if (widget.pushActive == false) return '等待推流…\n点下方「推流」开启摄像头';
    if (widget.pushActive != true) return '检测推流状态…';
    return null;
  }

  Widget _coverLayer({required String coverUrl, Widget? child, bool dimmed = true}) {
    final local = widget.localCoverBytes;
    if (local != null && local.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(local, fit: BoxFit.cover, gaplessPlayback: true),
          if (dimmed)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.45)],
                ),
              ),
            ),
          if (child != null) Center(child: child),
        ],
      );
    }
    return LiveBackdrop(coverUrl: coverUrl, child: child, dimmed: dimmed);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.webPublishing) {
      return const LiveWhipPreview(key: ValueKey('host-whip-preview'));
    }
    final room = widget.room;
    final status = _statusText();
    final pk = widget.pk;
    final cohost = widget.cohost;
    return Stack(
      fit: StackFit.expand,
      children: [
        _coverLayer(
          coverUrl: widget.coverUrl,
          child: status != null
              ? Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.4, fontSize: 13),
                )
              : null,
        ),
        if (pk?.isActive == true && pk!.opPlayUrl.isNotEmpty && widget.pkSplitLayout)
          Row(
            children: [
              Expanded(
                child: widget.pushActive == true && room.playUrl.isNotEmpty
                    ? LivePlayer(key: ValueKey('host-main-${room.playUrl}'), url: room.playUrl)
                    : const SizedBox.shrink(),
              ),
              Container(width: 2, color: Colors.white38),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LivePlayer(key: ValueKey('pk-op-${pk.opPlayUrl}'), url: pk.opPlayUrl),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Text(
                        pk.opName,
                        style: const TextStyle(color: Colors.white, fontSize: 9, shadows: [Shadow(color: Colors.black, blurRadius: 3)]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          if (widget.pushActive == true && room.playUrl.isNotEmpty)
            LivePlayer(key: ValueKey('host-main-${room.playUrl}'), url: room.playUrl),
          if (widget.streamReconnecting)
            ColoredBox(
              color: Colors.black38,
              child: Center(
                child: Text('画面缓冲中…', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
              ),
            ),
        ],
        if (cohost?.isActive == true && cohost!.pushActive && cohost.playUrl.isNotEmpty)
          Positioned(
            left: 8,
            bottom: 8,
            width: 100,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LivePlayer(key: ValueKey('host-cohost-${cohost.playUrl}'), url: cohost.playUrl),
                  Container(
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(3),
                    child: Text(
                      cohost.userName,
                      style: const TextStyle(color: Colors.white, fontSize: 9, shadows: [Shadow(color: Colors.black, blurRadius: 3)]),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
