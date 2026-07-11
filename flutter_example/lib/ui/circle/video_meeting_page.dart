import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../api/circle_api.dart';
import '../../session.dart';
import 'circle_models.dart';
import 'circle_navigation.dart';
import 'meeting_sfu_page.dart';
import 'meeting_deep_link.dart';
import 'meeting_invite_sheet.dart';
import 'meeting_replay_viewers_sheet.dart';
import 'widgets/circle_room_shell.dart';
import 'widgets/circle_ui.dart';

/// 视频会议：统一 LiveKit SFU
class VideoMeetingPage extends StatefulWidget {
  final String token;
  final String userId;

  const VideoMeetingPage({super.key, required this.token, required this.userId});

  @override
  State<VideoMeetingPage> createState() => _VideoMeetingPageState();
}

class _VideoMeetingPageState extends State<VideoMeetingPage> {
  late final CircleApi _api = CircleApi(widget.token);
  final _joinCtrl = TextEditingController();
  bool _busy = false;
  List<LiveRoom> _liveRooms = [];
  List<Map<String, String>> _minutesHistory = const [];
  bool _roomsLoading = true;
  String? _pendingPasscode;
  bool _joinExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _loadMinutesHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) { _tryDeepLinkPrefill(); });
  }

  Future<void> _tryDeepLinkPrefill() async {
    final roomId = parseMeetingRoomFromUri(Uri.base);
    if (roomId == null || !mounted) return;
    _joinCtrl.text = roomId;
    _pendingPasscode = parseMeetingPasscodeFromUri(Uri.base);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已识别会议链接，正在加入…')),
    );
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || _busy) return;
    await _joinMeeting();
  }


  Future<void> _loadMinutesHistory() async {
    final items = await SessionStore.loadMeetingMinutes();
    if (!mounted) return;
    setState(() => _minutesHistory = items);
  }

  Future<void> _openMinutes(Map<String, String> item) async {
    final content = item['content'] ?? '';
    if (content.isEmpty) return;
    final roomId = item['roomId'] ?? '';
    final replayId = item['replayPostId'] ?? '';
    var isHost = false;
    if (roomId.isNotEmpty) {
      try {
        final room = await _api.getLiveRoom(roomId);
        isHost = room.hostId == widget.userId;
      } catch (_) {}
    }
    if (!mounted) return;
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
                  Expanded(child: Text(item['title'] ?? '会议纪要', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制')));
                    },
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              if (replayId.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('录像已保存（仅指定成员可见）', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      openMeetingReplay(context, token: widget.token, userId: widget.userId, postId: replayId);
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('观看会议录像'),
                    style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
                  ),
                ),
                if (isHost && roomId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        showMeetingReplayViewersSheet(
                          context,
                          token: widget.token,
                          userId: widget.userId,
                          roomId: roomId,
                        );
                      },
                      icon: const Icon(Icons.people_outline),
                      label: const Text('管理可见成员'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
              ],
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: MarkdownBody(
                    data: content,
                    styleSheet: MarkdownStyleSheet(p: const TextStyle(color: Colors.white, height: 1.45, fontSize: 14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReplay(String postId) async {
    openMeetingReplay(context, token: widget.token, userId: widget.userId, postId: postId);
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _api.listLiveRooms(status: 'live');
      if (!mounted) return;
      setState(() {
        _liveRooms = rooms.where((r) => r.meetingJoinable).toList();
        _roomsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _roomsLoading = false);
    }
  }

  Future<void> _pasteRoomId() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板为空')));
      return;
    }
    _joinCtrl.text = text;
  }

  @override
  void dispose() {
    _joinCtrl.dispose();
    super.dispose();
  }

  Future<void> _shareInvite(LiveRoom room) async {
    await showMeetingInviteSheet(
      context,
      token: widget.token,
      userId: widget.userId,
      title: room.title,
      roomId: room.roomId,
      passcode: room.joinPassword.isNotEmpty ? room.joinPassword : null,
    );
  }

  Future<void> _startMeeting() async {
    final prompt = await _promptMeetingTitle();
    if (prompt == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final room = await _api.createLiveRoom(prompt.title, roomType: LiveRoom.roomTypeMeeting, joinPassword: prompt.password);
      final live = await _api.startLiveRoom(room.roomId);
      if (!mounted) return;
      if (!live.isSfu) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议服务未就绪，请稍后重试')),
        );
        return;
      }
      if (!mounted) return;
      await showMeetingInviteSheet(
        context,
        token: widget.token,
        userId: widget.userId,
        title: live.title,
        roomId: live.roomId,
        passcode: live.joinPassword.isNotEmpty ? live.joinPassword : null,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingSfuPage(token: widget.token, userId: widget.userId, room: live, isHost: true, skipPreJoin: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String title, String? password})?> _promptMeetingTitle() async {
    final titleCtrl = TextEditingController(text: '我的会议');
    final pwdCtrl = TextEditingController();
    var usePwd = false;
    final result = await showDialog<({String title, String? password})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('会议主题', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '输入会议名称',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('入会密码', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: usePwd,
                onChanged: (v) => setLocal(() => usePwd = v),
              ),
              if (usePwd)
                TextField(
                  controller: pwdCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                  decoration: InputDecoration(
                    hintText: '4-12 位数字密码',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final t = titleCtrl.text.trim();
                if (t.isEmpty) return;
                final pwd = usePwd ? pwdCtrl.text.trim() : null;
                if (usePwd && (pwd == null || pwd.length < 4)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('密码至少 4 位数字')));
                  return;
                }
                Navigator.pop(ctx, (title: normalizeMeetingTitle(t), password: pwd));
              },
              child: const Text('发起'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    pwdCtrl.dispose();
    return result;
  }

  Future<String?> _promptJoinPasscode() async {
    final ctrl = TextEditingController(text: _pendingPasscode ?? '');
    _pendingPasscode = null;
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
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('加入')),
        ],
      ),
    );
    ctrl.dispose();
    return pwd;
  }

  Future<void> _joinMeeting() async {
    final roomId = _joinCtrl.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入会议号')));
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await _api.getLiveRoom(roomId);
      var passcode = '';
      if (room.hasJoinPassword && room.hostId != widget.userId) {
        final pwd = await _promptJoinPasscode();
        if (!mounted) return;
        if (pwd == null || pwd.isEmpty) return;
        passcode = pwd;
        await _api.joinCheckLiveRoom(roomId, passcode: passcode);
      }
      if (!mounted) return;
      if (!room.meetingJoinable && room.isMeeting) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会议服务未就绪，请稍后重试')),
        );
        return;
      }
      if (!room.isMeeting) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该房间不是视频会议')),
        );
        return;
      }
      await openMeetingRoom(
        context,
        token: widget.token,
        userId: widget.userId,
        room: room,
        joinPasscode: passcode,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.contains('wrong passcode') ? '入会密码错误' : '会议不存在或已结束：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMeetingScaffold,
      appBar: circleSubAppBar(
        context,
        title: '视频会议',
        meetingMode: true,
        backgroundColor: kMeetingScaffold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy ? null : () { _loadRooms(); _loadMinutesHistory(); },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kMeetingAccent,
        backgroundColor: kMeetingSurface,
        onRefresh: () async {
          await _loadRooms();
          await _loadMinutesHistory();
        },
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SizedBox(height: 8),
          Text('随时随地，高效开会', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14)),
          const SizedBox(height: 20),
          CircleRoomEntryButton(
            icon: Icons.videocam_rounded,
            label: '发起会议',
            subtitle: '立即创建并进入会议室',
            primary: true,
            loading: _busy,
            onTap: _startMeeting,
          ),
          const SizedBox(height: 12),
          CircleRoomEntryButton(
            icon: Icons.login_rounded,
            label: '加入会议',
            subtitle: '输入会议号或点击链接入会',
            onTap: () => setState(() => _joinExpanded = !_joinExpanded),
          ),
          if (_joinExpanded) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _joinCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1.2),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.text,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_-]'))],
              decoration: InputDecoration(
                hintText: '会议号',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                suffixIcon: IconButton(
                  tooltip: '粘贴',
                  icon: const Icon(Icons.content_paste_rounded, color: Colors.white54),
                  onPressed: _busy ? null : _pasteRoomId,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _joinMeeting,
                style: FilledButton.styleFrom(
                  backgroundColor: kMeetingAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('加入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          if (_liveRooms.isNotEmpty) ...[
            const SizedBox(height: 32),
            _sectionTitle('进行中的会议'),
            const SizedBox(height: 10),
            ..._liveRooms.take(6).map(_liveRoomTile),
          ],
          if (_minutesHistory.isNotEmpty) ...[
            const SizedBox(height: 28),
            _sectionTitle('最近纪要 / 录像'),
            const SizedBox(height: 10),
            ..._minutesHistory.take(5).map(_minutesTile),
          ],
          if (_roomsLoading && _liveRooms.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
            ),
        ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14, fontWeight: FontWeight.w600));
  }

  Widget _liveRoomTile(LiveRoom r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy
              ? null
              : () => openMeetingRoom(context, token: widget.token, userId: widget.userId, room: r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: kMeetingAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.meeting_room_outlined, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title.isNotEmpty ? r.title : '会议', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('${r.hostName} · ${r.roomId}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '分享',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.share_outlined, color: Colors.white54, size: 20),
                  onPressed: _busy ? null : () => _shareInvite(r),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _minutesTile(Map<String, String> m) {
    final replayId = m['replayPostId'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openMinutes(m),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  replayId.isNotEmpty ? Icons.play_circle_outline : Icons.article_outlined,
                  color: kMeetingAccent,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['title'] ?? '会议纪要', style: const TextStyle(color: Colors.white, fontSize: 14)),
                      if ((m['savedAt'] ?? '').isNotEmpty)
                        Text(m['savedAt']!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                if (replayId.isNotEmpty)
                  IconButton(
                    tooltip: '观看录像',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow_rounded, color: kMeetingAccent),
                    onPressed: () => _openReplay(replayId),
                  ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
