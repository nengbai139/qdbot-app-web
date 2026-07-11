import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/circle_api.dart';
import '../../util/meeting_translate.dart';
import '../../util/meeting_caption.dart';
import '../app_theme.dart';
import 'circle_models.dart';
import 'circle_navigation.dart';
import 'live_gift_sheet.dart';
import 'live_pk_bar.dart';
import 'live_publisher.dart';
import 'live_room_ws.dart';
import 'live_player.dart';
import 'meeting_deep_link.dart';
import 'meeting_sfu_page.dart';
import 'stream_latch.dart';
import 'widgets/circle_room_shell.dart';
import 'widgets/circle_ui.dart';
import 'widgets/meeting_participants_sheet.dart';
import 'widgets/meeting_caption_overlay.dart';
import 'widgets/live_gift_honor.dart';
import 'widgets/live_audio_unmute.dart';
import 'widgets/live_pk_pip.dart';
import 'widgets/live_backdrop.dart';
import 'live_web_audio.dart';

/// 手机竖屏（含浏览器打开 /app_web/ 的情况，不能只看 kIsWeb）
bool _isMobilePortrait(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide < 600 && s.height >= s.width;
}

double _liveVideoHeight(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width * 9 / 16;
}

class LiveRoomPage extends StatefulWidget {
  final String token;
  final String userId;
  final String roomId;
  final String joinPasscode;

  const LiveRoomPage({super.key, required this.token, required this.userId, required this.roomId, this.joinPasscode = ''});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  late final CircleApi _api = CircleApi(widget.token);
  LiveRoom? _room;
  final _messages = <LiveMessage>[];
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _poll;
  Timer? _roomPoll;
  Timer? _streamPoll;
  LiveRoomWs? _liveWs;
  int _viewerCount = 0;
  bool _wsConnected = false;
  String _since = '';
  String? _error;
  bool _loading = true;
  bool? _pushActive;
  String? _streamPlayUrl;
  final _streamLatch = StreamLatch();
  final _hearts = <_FloatingHeart>[];
  final _giftBannersNotifier = ValueNotifier<List<LiveGiftEvent>>([]);
  final _honorBurstNotifier = ValueNotifier<LiveGiftEvent?>(null);
  List<LiveGiftRank> _giftRank = [];
  LiveRedPacket? _activeRedPacket;
  bool _grabbing = false;
  LiveCohost? _cohost;
  Timer? _cohostPoll;
  LivePk? _pk;
  Timer? _pkPoll;
  bool _pkResultShown = false;
  bool _cohostPublishing = false;
  bool _screenSharing = false;
  String? _screenShareSpeaker;
  String? _pendingCohostWhip;
  bool _cohostPromptOpen = false;
  Timer? _rankPoll;
  Timer? _likeThrottle;
  bool _chatExpanded = false;
  bool _speakHintDismissed = false;
  List<LiveParticipant> _participants = const [];
  bool _inLobby = false;
  String _lobbyMessage = '等待主持人准许入会';
  bool _muteAllActive = false;
  bool _allowUnmute = false;
  bool _captionsOn = true;
  final _captionLines = <LiveCaption>[];
  final _captionTranslations = <String, String>{};
  final _captionTranslatePending = <String>{};
  MeetingCaptionEngine? _captionEngine;
  var _captionSeq = 0;
  bool _meetingTranslateOn = false;
  final _meetingTranslations = <String, String>{};
  final _meetingTranslatePending = <String>{};
  String? _cohostPreJoinWhip;
  bool _cohostCamOn = true;
  bool _cohostMicOn = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final room = await _api.getLiveRoom(widget.roomId);
      if (!mounted) return;
      if (room.isMeeting) {
        if (!room.isSfu) {
          setState(() {
            _error = '会议服务未就绪，请让主持人重新发起';
            _loading = false;
          });
          return;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingSfuPage(
              token: widget.token,
              userId: widget.userId,
              room: room,
              isHost: room.hostId == widget.userId,
              joinPasscode: widget.joinPasscode,
            ),
          ),
        );
        return;
      }
      setState(() {
        _room = room;
        _loading = false;
        if (room.isMeeting) _chatExpanded = false;
      });
      await _fetchMessages();
      _startLiveWs();
      // ponytail: WS 断线时 REST 兜底拉弹幕
      _poll = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_wsConnected) _fetchMessages();
      });
      _roomPoll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshRoom());
      if (room.isLive) {
        await _checkStreamActive();
        _streamPoll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStreamActive());
        await _loadCohost();
        _cohostPoll = Timer.periodic(const Duration(seconds: 3), (_) => _loadCohost());
        if (!room.isMeeting) {
          await _loadGiftRank();
          _rankPoll = Timer.periodic(const Duration(seconds: 20), (_) => _loadGiftRank());
          await _loadActiveRedPacket();
          await _loadPk();
          _pkPoll = Timer.periodic(const Duration(seconds: 8), (_) => _loadPk());
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _startLiveWs() {
    _liveWs?.dispose();
    _liveWs = LiveRoomWs(
      token: widget.token,
      roomId: widget.roomId,
      joinPasscode: widget.joinPasscode,
      onMessage: (msg) {
        if (!mounted) return;
        _appendMessage(msg);
      },
      onViewerCount: (n) {
        if (!mounted) return;
        setState(() => _viewerCount = n);
      },
      onParticipants: (list) {
        if (!mounted) return;
        setState(() {
          _participants = list;
          if (list.isNotEmpty) _inLobby = false;
        });
      },
      onLobbyWaiting: (msg) {
        if (!mounted) return;
        setState(() {
          _inLobby = true;
          _lobbyMessage = msg;
        });
      },
      onLobbyAdmitted: () {
        if (!mounted) return;
        setState(() => _inLobby = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主持人已准许入会'), duration: Duration(seconds: 2)),
        );
        if (_room?.isLive == true) _checkStreamActive();
      },
      onRemoved: (reason, {replayPostId}) async {
        if (!mounted) return;
        if (_cohostPublishing && kIsWeb) LiveWebPublisher.stop();
        final isMeeting = _room?.isMeeting == true;
        await showMeetingEndedNotice(
          context,
          token: widget.token,
          userId: widget.userId,
          reason: reason,
          replayPostId: replayPostId,
          title: isMeeting ? '会议已结束' : '直播已结束',
          replayMessage: isMeeting ? '主持人已结束会议，录像已保存（仅参会成员可在视频圈查看）。' : '主播已结束直播，录像已发布到视频圈。',
        );
        if (mounted) Navigator.of(context).pop();
      },
      onMuteAll: (allowUnmute) {
        if (!mounted) return;
        if (_cohostPublishing && kIsWeb) LiveWebPublisher.stop();
        setState(() {
          _muteAllActive = true;
          _allowUnmute = allowUnmute;
          _cohostPublishing = false;
          _pendingCohostWhip = null;
          _cohost = const LiveCohost();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allowUnmute ? '主持人已全员静音，可自行开麦' : '主持人已全员静音'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      onUnmuteAll: () {
        if (!mounted) return;
        setState(() {
          _muteAllActive = false;
          _allowUnmute = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主持人已允许参会者发言'), duration: Duration(seconds: 2)),
        );
      },
      onCaption: (c) {
        if (!mounted) return;
        setState(() => _upsertCaption(c));
        if (_meetingTranslateOn && c.isFinal) _queueCaptionTranslate(c);
      },
      onScreenShare: (speakerId, speakerName, active) {
        if (!mounted) return;
        setState(() {
          _screenShareSpeaker = active && speakerName.isNotEmpty ? speakerName : null;
        });
      },
      onLikeBurst: (_, __) { if (_room?.isMeeting != true) _burstHeart(); },
      onGift: (g) {
        if (!mounted || _room?.isMeeting == true) return;
        final banners = List<LiveGiftEvent>.from(_giftBannersNotifier.value);
        banners.insert(0, g);
        while (banners.length > 3) banners.removeLast();
        _giftBannersNotifier.value = banners;
        maybeTriggerGiftHonorBurst(gift: g, burstNotifier: _honorBurstNotifier);
        _loadGiftRank();
        if (_pk?.isActive == true) _loadPk();
        Future.delayed(const Duration(seconds: 4), () {
          final next = List<LiveGiftEvent>.from(_giftBannersNotifier.value);
          next.removeWhere(
            (x) => x.senderName == g.senderName && x.giftName == g.giftName && x.amount == g.amount && x.emoji == g.emoji,
          );
          _giftBannersNotifier.value = next;
        });
      },
      onRedPacket: (p) {
        if (!mounted || _room?.isMeeting == true) return;
        setState(() => _activeRedPacket = p);
      },
      onRedPacketGrab: (_, packet) {
        if (!mounted || _room?.isMeeting == true) return;
        setState(() {
          if (packet == null || !packet.isActive) {
            _activeRedPacket = null;
          } else {
            _activeRedPacket = packet;
          }
        });
      },
      onCohost: (c) {
        if (!mounted) return;
        setState(() => _cohost = c);
      },
      onCohostEnd: () {
        if (!mounted) return;
        if (_cohostPublishing && kIsWeb) LiveWebPublisher.stop();
        setState(() {
          _cohost = const LiveCohost();
          _cohostPublishing = false;
          _pendingCohostWhip = null;
        });
      },
      onCohostInvite: (whip, c, {sfu = false}) {
        if (!mounted) return;
        setState(() {
          _cohost = c;
          _pendingCohostWhip = sfu ? null : whip;
        });
        if (!sfu && whip.isNotEmpty) _showCohostInvite(whip);
      },
      onPushStatus: (active) {
        if (!mounted || _room == null || !_room!.isLive) return;
        final show = _streamLatch.update(active);
        setState(() => _pushActive = show);
      },
      onPkInvite: (pk) {
        if (!mounted || _room?.isMeeting == true) return;
        setState(() => _pk = pk);
      },
      onPkStart: (pk) {
        if (!mounted || _room?.isMeeting == true) return;
        _pkResultShown = false;
        setState(() => _pk = pk);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PK 开始 · ${pk.myName} vs ${pk.opName}'), duration: const Duration(seconds: 3)),
          );
        });
      },
      onPkScore: (pk) {
        if (!mounted || _room?.isMeeting == true) return;
        setState(() => _pk = pk);
      },
      onPkEnd: (pk) {
        if (!mounted || _room?.isMeeting == true) return;
        final prev = _pk;
        setState(() => _pk = null);
        if (!_pkResultShown && prev != null && prev.isActive) {
          _pkResultShown = true;
          _showPkResult(prev);
        }
      },
      onConnectionChange: (c) {
        if (!mounted) return;
        setState(() => _wsConnected = c);
      },
    )..connect();
  }

  Future<void> _loadGiftRank() async {
    if (_room == null || !_room!.isLive) return;
    try {
      final items = await _api.listLiveGiftRank(widget.roomId, limit: 5);
      if (!mounted) return;
      setState(() => _giftRank = items);
    } catch (_) {}
  }

  Future<void> _loadActiveRedPacket() async {
    if (_room == null || !_room!.isLive) return;
    try {
      final p = await _api.activeLiveRedPacket(widget.roomId);
      if (!mounted) return;
      setState(() => _activeRedPacket = p?.isActive == true ? p : null);
    } catch (_) {}
  }

  Future<void> _loadPk() async {
    if (_room == null || !_room!.isLive) return;
    try {
      final pk = await _api.getLivePk(widget.roomId);
      if (!mounted) return;
      setState(() => _pk = pk != null && (pk.isActive || pk.isPending) ? pk : null);
    } catch (_) {}
  }

  void _showPkResult(LivePk pk) {
    if (!mounted) return;
    final msg = pk.isTie
        ? 'PK 平局 · ${pk.myScore.toInt()} : ${pk.opScore.toInt()} QD'
        : pk.iWon
            ? '🎉 ${pk.myName} 胜出！${pk.myScore.toInt()} : ${pk.opScore.toInt()}'
            : '${pk.opName} 胜出 · ${pk.myScore.toInt()} : ${pk.opScore.toInt()}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  Future<void> _loadCohost() async {
    if (_room == null || !_room!.isLive) return;
    try {
      final c = await _api.getLiveCohost(widget.roomId);
      if (!mounted) return;
      setState(() => _cohost = c);
      if (c.isActive && c.userId == widget.userId && _pendingCohostWhip == null && !_cohostPublishing) {
        final whip = await _api.getLiveCohostWhip(widget.roomId);
        if (mounted && whip.isNotEmpty) {
          setState(() => _pendingCohostWhip = whip);
          _showCohostInvite(whip);
        }
      }
    } catch (_) {}
  }

  Future<void> _requestCohost() async {
    if (_room == null || !_room!.isLive) return;
    if (_room!.isMeeting && _muteAllActive && !_allowUnmute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('主持人已全员静音，暂不可申请发言')),
      );
      return;
    }
    try {
      final c = await _api.requestLiveCohost(widget.roomId);
      if (!mounted) return;
      setState(() => _cohost = c);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_room!.isMeeting ? '已申请发言，等待主持人同意' : '已申请连麦，等待主播同意')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _showCohostInvite(String whip) {
    if (!mounted || _cohostPublishing || _cohostPromptOpen) return;
    _cohostPromptOpen = true;
    final isMeeting = _room != null && _room!.isMeeting;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _cohostPromptOpen = false;
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
                const Icon(Icons.mic_none_rounded, color: AppTheme.brandBlue, size: 48),
                const SizedBox(height: 12),
                Text(
                  isMeeting ? '主持人已同意发言' : '主播已同意连麦',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? (isMeeting ? '开启摄像头和麦克风，参与讨论' : '开启摄像头和麦克风，与主播同框互动')
                      : (isMeeting ? '请在网页版打开会议发言' : '请在网页版打开直播间连麦'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('稍后'),
                      ),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _cohostPreJoinWhip = whip);
                          },
                          child: const Text('开麦'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() {
        if (mounted) _cohostPromptOpen = false;
      });
    });
  }

  Future<void> _startCohostPublish(String whip) async {
    if (!kIsWeb) return;
    final err = await LiveWebPublisher.start(whip, audio: _cohostMicOn, video: _cohostCamOn, backdropUrl: _room?.coverUrl ?? '');
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连麦推流失败: $err')));
      return;
    }
    setState(() {
      _cohostPublishing = true;
      _pendingCohostWhip = null;
    });
    _syncRoomCaptions();
  }

  Future<void> _endCohost() async {
    if (_cohostPublishing && kIsWeb) LiveWebPublisher.stop();
    try {
      await _api.endLiveCohost(widget.roomId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cohostPublishing = false;
      _screenSharing = false;
      _pendingCohostWhip = null;
      _cohost = const LiveCohost();
    });
    _syncRoomCaptions();
  }

  Future<void> _grabRedPacket() async {
    final p = _activeRedPacket;
    if (p == null || _grabbing) return;
    setState(() => _grabbing = true);
    try {
      final g = await _api.grabLiveRedPacket(widget.roomId, p.packetId);
      if (!mounted) return;
      setState(() {
        _grabbing = false;
        if (g.remainCount != null && g.remainCount! <= 0) _activeRedPacket = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF1E1E1E),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧧', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  const Text('恭喜抢到', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('${g.amount.toStringAsFixed(2)} QD', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好')),
                ],
              ),
            ),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _grabbing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _appendMessage(LiveMessage msg) {
    if (_messages.any((m) => m.msgId == msg.msgId)) return;
    setState(() {
      _messages.add(msg);
      _since = msg.createdAt;
    });
    if (_room?.isMeeting == true && _meetingTranslateOn) _queueMeetingTranslate(msg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
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

  void _onRoomSttResult(String text, bool isFinal, {String? error}) {
    if (!mounted) return;
    if (error == 'mic_denied') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音识别需要麦克风权限')),
      );
      _syncRoomCaptions(forceOff: true);
      return;
    }
    final name = _participants.firstWhere(
      (p) => p.userId == widget.userId,
      orElse: () => LiveParticipant(userId: widget.userId, userName: '我'),
    ).userName;
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
    final ss = _cohostPublishing && LiveWebPublisher.screenSharing;
    if (ss != _screenSharing && mounted) setState(() => _screenSharing = ss);
  }

  Future<void> _toggleScreenShare() async {
    if (!kIsWeb || !_cohostPublishing) return;
    final err = _screenSharing
        ? await LiveWebPublisher.switchToCamera()
        : await LiveWebPublisher.switchToScreen();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final nowSharing = !_screenSharing;
    setState(() => _screenSharing = nowSharing);
    _liveWs?.sendScreenShare(active: nowSharing);
    _syncRoomCaptions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowSharing ? '正在共享屏幕' : '已切回摄像头'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _syncRoomCaptions({bool forceOff = false}) {
    final room = _room;
    if (forceOff) {
      setState(() => _captionsOn = false);
    }
    if (room?.isMeeting != true || room?.isLive != true || _inLobby || !_captionsOn || !_cohostPublishing) {
      _captionEngine?.stop();
      _captionEngine = null;
      return;
    }
    if (!kIsWeb) return;
    _captionEngine ??= MeetingCaptionEngine();
    if (_captionEngine!.running) return;
    final err = _captionEngine!.start(onResult: _onRoomSttResult);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('字幕: $err')));
    }
  }

  void _openParticipantsSheet() {
    final room = _room;
    if (room == null || !room.isMeeting) return;
    showMeetingParticipantsSheet(
      context,
      participants: _participants,
      isHost: room.hostId == widget.userId,
    );
  }

  void _burstHeart() {
    final id = DateTime.now().millisecondsSinceEpoch;
    setState(() => _hearts.add(_FloatingHeart(id: id)));
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _hearts.removeWhere((h) => h.id == id));
    });
  }

  Future<void> _refreshRoom() async {
    try {
      final room = await _api.getLiveRoom(widget.roomId);
      if (!mounted) return;
      final wasLive = _room?.isLive ?? false;
      setState(() => _room = room);
      if (room.isLive && !wasLive) {
        _streamPoll?.cancel();
        _checkStreamActive();
        _streamPoll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStreamActive());
      } else if (!room.isLive) {
        _streamPoll?.cancel();
        _streamPoll = null;
        if (_pushActive != null) {
          _pushActive = null;
          _streamLatch.reset();
        }
      }
    } catch (_) {}
  }

  Future<void> _checkStreamActive() async {
    if (_room == null || !_room!.isLive) return;
    try {
      final status = await _api.liveStreamStatus(widget.roomId);
      if (!mounted) return;
      if (status.playUrl.isNotEmpty) _streamPlayUrl = status.playUrl;
      final showPlayer = _streamLatch.update(status.pushActive);
      setState(() => _pushActive = showPlayer);
      _syncScreenShareState();
    } catch (_) {}
  }

  String _effectivePlayUrl(LiveRoom room) {
    final u = (_streamPlayUrl ?? room.playUrl).trim();
    return u;
  }

  Future<void> _fetchMessages() async {
    try {
      final items = await _api.listLiveMessages(widget.roomId, since: _since);
      if (!mounted || items.isEmpty) return;
      for (final msg in items) {
        _appendMessage(msg);
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _room == null || !_room!.isLive) return;
    _msgCtrl.clear();
    final ws = _liveWs;
    if (ws != null && ws.isConnected) {
      ws.sendChat(text);
      return;
    }
    try {
      final msg = await _api.sendLiveMessage(widget.roomId, text);
      if (!mounted) return;
      _appendMessage(msg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  Future<void> _sendLike() async {
    if (_room == null || !_room!.isLive) return;
    _burstHeart();
    if (_likeThrottle?.isActive ?? false) return;
    _likeThrottle = Timer(const Duration(seconds: 2), () {});
    final ws = _liveWs;
    if (ws != null && ws.isConnected) {
      ws.sendLike();
      return;
    }
    try {
      await _api.sendLiveMessage(widget.roomId, '❤️');
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _roomPoll?.cancel();
    _streamPoll?.cancel();
    _rankPoll?.cancel();
    _cohostPoll?.cancel();
    _pkPoll?.cancel();
    _likeThrottle?.cancel();
    if (_cohostPublishing && kIsWeb) LiveWebPublisher.stop();
    _liveWs?.dispose();
    _giftBannersNotifier.dispose();
    _honorBurstNotifier.dispose();
    _msgCtrl.dispose();
    _captionEngine?.stop();
    _scrollCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
      );
    }
    if (_error != null || _room == null) {
      return Scaffold(
        appBar: circleSubAppBar(context, title: '直播间', meetingMode: false),
        body: Center(
          child: CircleEmptyBox(
            icon: Icons.error_outline,
            title: '无法进入',
            subtitle: _error ?? 'unknown',
          ),
        ),
      );
    }
    final room = _room!;
    final isHost = room.hostId == widget.userId;
    final cohost = _cohost;
    final showCohostPiP = room.isLive &&
        cohost != null &&
        cohost.isActive &&
        (cohost.pushActive || (_cohostPublishing && cohost.userId == widget.userId));
    final pkActive = !room.isMeeting && room.isLive && _pk?.isActive == true && _pk!.opPlayUrl.isNotEmpty;
    final mobilePortrait = _isMobilePortrait(context);
    final meeting = room.isMeeting;
    if (_cohostPreJoinWhip != null && kIsWeb) {
      return MeetingPreJoinScreen(
        meeting: room.isMeeting,
        title: room.title,
        subtitle: '主持人已同意你发言',
        joinLabel: room.isMeeting ? '开始发言' : '开始连麦',
        hint: '确认设备后开启麦克风与摄像头',
        micOn: _cohostMicOn,
        camOn: _cohostCamOn,
        onMicToggle: () => setState(() => _cohostMicOn = !_cohostMicOn),
        onCamToggle: () => setState(() => _cohostCamOn = !_cohostCamOn),
        onJoin: () {
          final whip = _cohostPreJoinWhip!;
          setState(() => _cohostPreJoinWhip = null);
          _startCohostPublish(whip);
        },
        onCancel: () => setState(() => _cohostPreJoinWhip = null),
      );
    }
    if (meeting && _inLobby) {
      return CircleRoomLobbyView(
        meeting: true,
        title: room.title,
        message: _lobbyMessage,
        hostName: room.hostName,
        roomId: room.roomId,
        onLeave: () => Navigator.of(context).pop(),
      );
    }
    final useImmersive = room.isLive && (mobilePortrait || meeting);
    return Scaffold(
      backgroundColor: circleRoomScaffoldBg(meeting),
      extendBody: useImmersive,
      appBar: useImmersive
          ? null
          : AppBar(
              elevation: 0,
              backgroundColor: circleRoomAppBarBg(meeting),
              foregroundColor: Colors.white,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: circleModeStrip(meeting: meeting),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: circleRoomTitleHeader(
                      meeting: meeting,
                      title: room.title,
                      subtitle: meeting ? '主持人 · ${room.hostName}' : room.hostName,
                      onSubtitleTap: room.hostId.isEmpty
                          ? null
                          : () => openUserCircleFromLiveHost(
                                context,
                                token: widget.token,
                                viewerId: widget.userId,
                                room: room,
                              ),
                    ),
                  ),
                  if (room.isLive) ...[
                    const SizedBox(width: 8),
                    if (meeting) _recordingBadge(),
                    if (meeting)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '成员',
                        icon: Badge(
                          isLabelVisible: _participants.any((p) => p.handRaised),
                          smallSize: 8,
                          child: Icon(Icons.groups_outlined, size: 20, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        onPressed: _openParticipantsSheet,
                      ),
                    if (_viewerCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(width: 3),
                            Text('$_viewerCount', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                    meeting ? circleMeetingBadge(compact: true) : circleLiveBadge(compact: true),
                  ],
                ],
              ),
            ),
      body: useImmersive
          ? _buildImmersiveMobileBody(room, isHost, cohost, showCohostPiP, pkActive)
          : (mobilePortrait
              ? _buildMobileBody(room, isHost, cohost, showCohostPiP, pkActive)
              : _buildDesktopBody(room, isHost, cohost, showCohostPiP, pkActive)),
    );
  }

  Widget _buildDesktopBody(LiveRoom room, bool isHost, LiveCohost? cohost, bool showCohostPiP, bool pkActive) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: DecoratedBox(
            decoration: circleRoomVideoFrameDecoration(room.isMeeting),
            child: SizedBox(
              height: _liveVideoHeight(context),
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildVideoStack(room, isHost, cohost, showCohostPiP, pkActive, showHints: true),
              ),
            ),
          ),
        ),
        Expanded(child: _buildChatPanel(room, collapsible: false)),
        if (room.isLive) _buildInputBar(room, isHost, showChatToggle: false),
      ],
    );
  }


  void _onMeetingMicTap(LiveRoom room) {
    if (room.isMeeting && _muteAllActive && !_allowUnmute) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('主持人已全员静音，请举手申请发言')));
      return;
    }
    final c = _cohost;
    if (c != null && c.isActive && c.userId == widget.userId) {
      if (_cohostPublishing) {
        _endCohost();
      } else if (_pendingCohostWhip != null) {
        _startCohostPublish(_pendingCohostWhip!);
      }
      return;
    }
    if (c != null && (c.isPending || c.isActive)) return;
    _requestCohost();
  }

  List<Widget> _immersiveChatTiles(LiveRoom room) {
    return [
      for (final m in _messages)
        _DanmakuLine(
          message: m,
          translation: room.isMeeting ? _meetingTranslations[m.msgId] : null,
          onAuthorTap: () => openUserCircleFromLiveMessage(
            context,
            token: widget.token,
            viewerId: widget.userId,
            message: m,
          ),
        ),
    ];
  }

  Widget? _immersiveChatHeader(LiveRoom room) {
    if (!room.isMeeting) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          visualDensity: VisualDensity.compact,
          label: const Text('字幕', style: TextStyle(fontSize: 11)),
          selected: _captionsOn,
          onSelected: (v) {
            setState(() => _captionsOn = v);
            _syncRoomCaptions();
          },
          selectedColor: kMeetingAccent.withValues(alpha: 0.35),
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(color: _captionsOn ? Colors.white : Colors.white70),
          side: BorderSide(color: kMeetingAccent.withValues(alpha: 0.4)),
        ),
        const SizedBox(width: 6),
        FilterChip(
          visualDensity: VisualDensity.compact,
          label: const Text('译', style: TextStyle(fontSize: 11)),
          selected: _meetingTranslateOn,
          onSelected: (v) {
            setState(() => _meetingTranslateOn = v);
            if (v) {
              for (final m in _messages) {
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
      ],
    );
  }

  Widget _buildImmersiveControlBar(LiveRoom room, bool isHost) {
    final meeting = room.isMeeting;
    final cohostPending = _cohost?.isPending == true && _cohost!.userId == widget.userId;
    final cohostActive = _cohost?.isActive == true && _cohost!.userId == widget.userId;
    return CircleRoomControlBar(
      children: [
        CircleRoomControlBtn(
          meeting: meeting,
          icon: _chatExpanded ? Icons.chat : Icons.chat_outlined,
          label: '聊天',
          active: _chatExpanded,
          onTap: () => setState(() => _chatExpanded = !_chatExpanded),
        ),
        if (!isHost && meeting)
          CircleRoomControlBtn(
            meeting: meeting,
            icon: _cohostPublishing
                ? Icons.mic_off
                : (cohostPending ? Icons.hourglass_top : (cohostActive ? Icons.mic : Icons.front_hand_outlined)),
            label: _cohostPublishing
                ? '静音'
                : (cohostPending ? '等待' : (cohostActive ? '发言' : '举手')),
            active: _cohostPublishing || cohostPending || cohostActive,
            onTap: () => _onMeetingMicTap(room),
          ),
        if (!isHost && meeting && _cohostPublishing && kIsWeb)
          CircleRoomControlBtn(
            meeting: meeting,
            icon: _screenSharing ? Icons.stop_screen_share : Icons.screen_share,
            label: _screenSharing ? '停共享' : '共享',
            active: _screenSharing,
            onTap: _toggleScreenShare,
          ),
        if (!meeting)
          CircleRoomControlBtn(
            meeting: false,
            icon: Icons.favorite_border,
            label: '点赞',
            onTap: _sendLike,
          ),
        if (!meeting)
          CircleRoomControlBtn(
            meeting: false,
            icon: Icons.card_giftcard_outlined,
            label: '礼物',
            onTap: () => LiveGiftSheet.show(context, token: widget.token, userId: widget.userId, roomId: widget.roomId),
          ),
        if (meeting && !isHost)
          CircleRoomControlBtn(
            meeting: meeting,
            icon: Icons.people_outline,
            label: '成员',
            onTap: _openParticipantsSheet,
          ),
        CircleRoomControlBtn(
          meeting: meeting,
          icon: Icons.logout,
          label: '离开',
          danger: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildImmersiveMobileBody(LiveRoom room, bool isHost, LiveCohost? cohost, bool showCohostPiP, bool pkActive) {
    final meeting = room.isMeeting;
    final subtitle = meeting
        ? '主持人 · ${room.hostName}${_viewerCount > 0 ? ' · $_viewerCount 人' : ''}'
        : '${room.hostName}${_viewerCount > 0 ? ' · $_viewerCount 人在看' : ''}';
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoStack(room, isHost, cohost, showCohostPiP, pkActive, showHints: !_chatExpanded),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CircleRoomTopOverlay(
            meeting: meeting,
            title: room.title,
            subtitle: subtitle,
            onBack: () => Navigator.of(context).pop(),
            trailing: [
              if (meeting && room.isLive) _recordingBadge(),
              if (meeting && room.hostId == widget.userId)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '成员',
                  onPressed: _openParticipantsSheet,
                  icon: Badge(
                    isLabelVisible: _participants.any((p) => p.handRaised),
                    smallSize: 8,
                    child: const Icon(Icons.people_outline, color: Colors.white, size: 22),
                  ),
                ),
            ],
          ),
        ),
        if (_chatExpanded)
          Positioned(
            left: 0,
            right: 0,
            bottom: 88,
            height: MediaQuery.sizeOf(context).height * 0.36,
            child: CircleRoomChatPanel(
              meeting: meeting,
              controller: _msgCtrl,
              onSend: _send,
              messageTiles: _immersiveChatTiles(room),
              headerExtra: _immersiveChatHeader(room),
              onClose: () => setState(() => _chatExpanded = false),
              emptyHint: meeting ? '暂无聊天消息' : '还没有弹幕，发一条吧',
            ),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildImmersiveControlBar(room, isHost)),
      ],
    );
  }

  Widget _buildMobileBody(LiveRoom room, bool isHost, LiveCohost? cohost, bool showCohostPiP, bool pkActive) {
    return Column(
      children: [
        Expanded(child: _buildVideoStack(room, isHost, cohost, showCohostPiP, pkActive, showHints: _chatExpanded)),
        if (_chatExpanded)
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.34,
            child: _buildChatPanel(room, collapsible: true),
          ),
        if (room.isLive) _buildInputBar(room, isHost, showChatToggle: true),
      ],
    );
  }

  Widget _meetingSpeakHint(LiveRoom room, bool isHost) {
    if (isHost || !room.isMeeting || _speakHintDismissed) return const SizedBox.shrink();
    final c = _cohost;
    if (c != null && (c.isPending || c.isActive) && c.userId == widget.userId) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 48,
      left: 12,
      right: 12,
      child: Material(
        color: kMeetingAccent.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        child: InkWell(
          onTap: () => setState(() => _speakHintDismissed = true),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.mic_none_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '想发言？点底部麦克风向主持人申请',
                    style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                  ),
                ),
                Icon(Icons.close, color: Colors.white.withValues(alpha: 0.7), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 观众端：确认有推流后再挂 HLS，避免 404 时视频层一直转圈
  bool _showLivePlayer(LiveRoom room) {
    if (!room.isLive || _effectivePlayUrl(room).isEmpty) return false;
    return _pushActive == true || _streamLatch.displayed;
  }

  Widget _connectingOverlay(LiveRoom room) {
    if (!room.isLive || _showLivePlayer(room)) return const SizedBox.shrink();
    final isMeeting = room.isMeeting;
    final waitingText = isMeeting
        ? '主持人正在开启摄像头…\n请稍候，画面将自动出现'
        : '主播暂未推流\n稍后会自动连接';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: isMeeting ? kMeetingAccent : kLiveAccent),
          ),
          const SizedBox(height: 14),
          Text(
            _pushActive == false ? waitingText : '正在连接直播画面…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.45, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStack(LiveRoom room, bool isHost, LiveCohost? cohost, bool showCohostPiP, bool pkActive, {required bool showHints}) {
    final showPlayer = _showLivePlayer(room);
    final playUrl = _effectivePlayUrl(room);
    final mobilePortrait = _isMobilePortrait(context);
    final pkSplit = pkActive && !mobilePortrait;
    return GestureDetector(
      onDoubleTap: room.isMeeting ? null : _sendLike,
      onTap: () {
        if (kIsWeb) LiveWebAudio.unmuteAll();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveBackdrop(coverUrl: room.coverUrl, child: _connectingOverlay(room)),
          _meetingSpeakHint(room, isHost),
          _ViewerVideoPane(
            key: ValueKey('viewer-video-${room.roomId}'),
            playUrl: playUrl,
            showPlayer: showPlayer,
            pkSplitLayout: pkSplit,
            pkActive: pkActive,
            pk: _pk,
            streamReconnecting: _streamLatch.reconnecting,
          ),
          if (!room.isMeeting) ..._hearts.map((h) => _HeartBurst(key: ValueKey(h.id))),
          if (!room.isMeeting) _ViewerGiftOverlay(notifier: _giftBannersNotifier),
          if (!room.isMeeting)
            ValueListenableBuilder<LiveGiftEvent?>(
              valueListenable: _honorBurstNotifier,
              builder: (_, gift, __) => LiveGiftHonorBurst(key: ValueKey('burst-${gift?.amount}-${gift?.senderName}'), gift: gift),
            ),
          if (room.isMeeting && _captionsOn)
            MeetingCaptionOverlay(lines: _captionLines, translations: _captionTranslations),
          if (room.isMeeting && _screenShareSpeaker != null)
            Positioned(
              top: 56,
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
          if (_pendingCohostWhip != null && !_cohostPublishing && _cohost?.userId == widget.userId)
            Positioned(
              top: 52,
              left: 12,
              right: 12,
              child: Material(
                color: AppTheme.brandBlue,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                child: InkWell(
                  onTap: () => _showCohostInvite(_pendingCohostWhip!),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            room.isMeeting ? '主持人请你发言，点此开麦' : '主播等你连麦，点此开麦',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (!room.isMeeting && room.isLive && _pk?.isActive == true)
            Positioned(left: 8, right: 8, top: 8, child: LivePkBar(pk: _pk!)),
          if (!room.isMeeting && room.isLive && _activeRedPacket != null)
            Positioned(
              right: 12,
              top: 12,
              child: _RedPacketBubble(packet: _activeRedPacket!, busy: _grabbing, onTap: _grabRedPacket),
            ),
          if (pkActive && mobilePortrait && _pk != null)
            Positioned(
              right: 12,
              bottom: showCohostPiP ? 82 : 12,
              width: 112,
              height: 63,
              child: LivePkOpponentPiP(pk: _pk!),
            ),
          if (showCohostPiP)
            Positioned(
              left: 12,
              bottom: 12,
              width: 112,
              height: 63,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cohostPublishing && cohost!.userId == widget.userId)
                      ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic, color: Colors.greenAccent.shade200, size: 28),
                              const SizedBox(height: 4),
                              Text(room.isMeeting ? '发言中' : '连麦中', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      )
                    else if (cohost!.pushActive && cohost.playUrl.isNotEmpty)
                      LivePlayer(key: ValueKey('cohost-${cohost.playUrl}'), url: cohost.playUrl),
                    Container(
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        cohost.userName,
                        style: const TextStyle(color: Colors.white, fontSize: 10, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (room.isLive && showHints && !room.isMeeting)
            Positioned(
              right: 10,
              bottom: 10,
              child: Text(
                '双击点赞',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatPanel(LiveRoom room, {required bool collapsible}) {
    final meeting = room.isMeeting;
    final accent = circleRoomAccent(meeting);
    return Container(
      decoration: BoxDecoration(
        color: meeting ? kMeetingChatBg : kLiveChatBg,
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsible)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  Text(meeting ? '会议聊天' : '弹幕', style: TextStyle(color: accent.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
                  if (meeting) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('字幕', style: TextStyle(fontSize: 11)),
                      selected: _captionsOn,
                      onSelected: (v) {
                        setState(() => _captionsOn = v);
                        _syncRoomCaptions();
                      },
                      selectedColor: kMeetingAccent.withValues(alpha: 0.35),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(color: _captionsOn ? Colors.white : Colors.white70),
                      side: BorderSide(color: kMeetingAccent.withValues(alpha: 0.4)),
                    ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('译', style: TextStyle(fontSize: 11)),
                      selected: _meetingTranslateOn,
                      onSelected: (v) {
                        setState(() => _meetingTranslateOn = v);
                        if (v) {
                          for (final m in _messages) {
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
                  ],
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                    tooltip: '收起',
                    onPressed: () => setState(() => _chatExpanded = false),
                  ),
                ],
              ),
            ),
          if (!room.isMeeting && room.isLive && _giftRank.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本场贡献榜', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _giftRank.map((r) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${r.rank}. ${r.senderName} ${r.totalAmount.toStringAsFixed(0)} QD',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Text('还没有弹幕，发一条吧', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _DanmakuLine(
                      message: _messages[i],
                      translation: meeting ? _meetingTranslations[_messages[i].msgId] : null,
                      onAuthorTap: () => openUserCircleFromLiveMessage(
                        context,
                        token: widget.token,
                        viewerId: widget.userId,
                        message: _messages[i],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(LiveRoom room, bool isHost, {required bool showChatToggle}) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          child: Row(
            children: [
              if (showChatToggle) ...[
                Material(
                  color: _chatExpanded
                      ? circleRoomAccent(room.isMeeting).withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () => setState(() => _chatExpanded = !_chatExpanded),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Badge(
                        isLabelVisible: !_chatExpanded && _messages.isNotEmpty,
                        label: Text('${_messages.length.clamp(0, 99)}'),
                        child: Icon(
                          _chatExpanded ? Icons.chat_bubble : Icons.chat_bubble_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: room.isMeeting ? '发送聊天消息…' : '说点什么…',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onTap: () {
                    if (showChatToggle && !_chatExpanded) setState(() => _chatExpanded = true);
                  },
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 4),
              if (!isHost && room.isMeeting && _cohostPublishing && kIsWeb)
                Material(
                  color: kMeetingAccent.withValues(alpha: _screenSharing ? 0.45 : 0.22),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: _toggleScreenShare,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _screenSharing ? Icons.stop_screen_share : Icons.screen_share,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              if (!isHost && room.isMeeting && _cohostPublishing && kIsWeb) const SizedBox(width: 4),
              if (!isHost)
                Material(
                  color: room.isMeeting
                      ? kMeetingAccent.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () {
                      if (room.isMeeting && _muteAllActive && !_allowUnmute) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('主持人已全员静音')),
                        );
                        return;
                      }
                      final c = _cohost;
                      if (c != null && c.isActive && c.userId == widget.userId) {
                        if (_cohostPublishing) {
                          _endCohost();
                        } else if (_pendingCohostWhip != null) {
                          _startCohostPublish(_pendingCohostWhip!);
                        }
                        return;
                      }
                      if (c != null && (c.isPending || c.isActive)) return;
                      _requestCohost();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _cohostPublishing
                            ? Icons.mic_off
                            : (_cohost?.isPending == true && _cohost?.userId == widget.userId
                                ? Icons.hourglass_top
                                : Icons.mic_none_outlined),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              if (!isHost) const SizedBox(width: 4),
              if (!room.isMeeting)
                Material(
                  color: const Color(0xFFE5484D).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () => LiveGiftSheet.show(context, token: widget.token, userId: widget.userId, roomId: widget.roomId),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.card_giftcard_outlined, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              if (!room.isMeeting) const SizedBox(width: 4),
              Material(
                color: room.isMeeting ? kMeetingAccent : kLiveAccent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _send,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingHeart {
  final int id;
  const _FloatingHeart({required this.id});
}

class _HeartBurst extends StatefulWidget {
  const _HeartBurst({super.key});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Positioned(
          right: 24 + (t * 18),
          bottom: 40 + (t * 120),
          child: Opacity(
            opacity: 1 - t,
            child: Transform.scale(
              scale: 0.8 + t * 0.6,
              child: const Icon(Icons.favorite, color: Color(0xFFE5484D), size: 28),
            ),
          ),
        );
      },
    );
  }
}

class _RedPacketBubble extends StatelessWidget {
  final LiveRedPacket packet;
  final bool busy;
  final VoidCallback onTap;

  const _RedPacketBubble({required this.packet, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE5484D),
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(busy ? '…' : '🧧', style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 2),
              Text(
                packet.title,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                '剩 ${packet.remainCount} 个',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PkSide extends StatelessWidget {
  const _PkSide({required this.name, required this.url, required this.show});

  final String name;
  final String url;
  final bool show;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (show && url.isNotEmpty)
          LivePlayer(key: ValueKey('pk-$url'), url: url)
        else
          ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Text(
                show ? '缓冲中…' : '等待推流…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
              ),
            ),
          ),
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class _DanmakuLine extends StatelessWidget {
  final LiveMessage message;
  final String? translation;
  final VoidCallback? onAuthorTap;

  const _DanmakuLine({required this.message, this.translation, this.onAuthorTap});

  @override
  Widget build(BuildContext context) {
    final isGift = liveMessageIsGift(message.text);
    final author = message.authorName.trim().isNotEmpty ? message.authorName : '观众';
    if (isGift) {
      final honor = giftHonorFor(giftAmountFromMessage(message.text));
      final accent = honor.gradient.last;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: honor.gradient.map((c) => c.withValues(alpha: 0.22)).toList(),
            ),
            borderRadius: BorderRadius.circular(10),
            border: honor.borderWidth > 0
                ? Border.all(color: honor.border.withValues(alpha: 0.5), width: honor.borderWidth)
                : Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: honor.level.index >= GiftHonorLevel.star.index
                ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 8)]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🎁 ', style: TextStyle(fontSize: honor.level.index >= GiftHonorLevel.epic.index ? 16 : 14)),
              if (honor.level.index >= GiftHonorLevel.sweet.index) ...[
                GiftHonorBadge(label: honor.badge, level: honor.level),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white),
                    children: [
                      TextSpan(
                        text: '$author ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: honor.level == GiftHonorLevel.legend ? const Color(0xFFFFD700) : const Color(0xFFFFB4A2),
                        ),
                      ),
                      TextSpan(
                        text: message.text,
                        style: honor.level.index >= GiftHonorLevel.epic.index
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final tr = translation?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onAuthorTap,
                child: Text(
                  '${message.authorName} ',
                  style: TextStyle(
                    color: AppTheme.brandBlue.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
          if (tr != null && tr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text('译: $tr', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45), height: 1.3)),
            ),
        ],
      ),
    );
  }
}

class _ViewerGiftOverlay extends StatelessWidget {
  final ValueNotifier<List<LiveGiftEvent>> notifier;
  const _ViewerGiftOverlay({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LiveGiftEvent>>(
      valueListenable: notifier,
      builder: (_, banners, __) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: 10,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: banners
                .map(
                  (g) => LiveGiftHonorBanner(
                        key: ValueKey('viewer-gift-${g.senderName}-${g.giftName}-${g.amount}-${g.emoji}'),
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

/// ponytail: 与弹幕/打赏状态隔离，避免 setState 拆掉 HLS 播放器
class _ViewerVideoPane extends StatefulWidget {
  final String playUrl;
  final bool showPlayer;
  final bool pkActive;
  final bool pkSplitLayout;
  final LivePk? pk;
  final bool streamReconnecting;

  const _ViewerVideoPane({
    super.key,
    required this.playUrl,
    required this.showPlayer,
    required this.pkActive,
    required this.pkSplitLayout,
    required this.pk,
    required this.streamReconnecting,
  });

  @override
  State<_ViewerVideoPane> createState() => _ViewerVideoPaneState();
}

class _ViewerVideoPaneState extends State<_ViewerVideoPane> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.showPlayer || widget.playUrl.isEmpty) return const SizedBox.shrink();

    if (widget.pkActive && widget.pkSplitLayout && widget.pk != null && widget.pk!.opPlayUrl.isNotEmpty) {
      final pk = widget.pk!;
      return Row(
        children: [
          Expanded(child: _PkSide(name: pk.myName, url: widget.playUrl, show: true)),
          Container(width: 2, color: Colors.white24),
          Expanded(child: _PkSide(name: pk.opName, url: pk.opPlayUrl, show: true)),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        LivePlayer(key: ValueKey('viewer-main-${widget.playUrl}'), url: widget.playUrl),
        if (widget.streamReconnecting)
          ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Text(
                '画面缓冲中…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
