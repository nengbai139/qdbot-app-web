import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../api/im_api.dart';
import '../session.dart';
import 'chat_page.dart';
import 'contacts_page.dart';
import 'group_chat_page.dart';
import 'user_pick_sheet.dart';
import 'chat_helpers.dart';
import 'premium/user_code_display.dart';
import 'premium/user_profile_sheet.dart';
import '../util/tab_data_cache.dart';
import '../util/web_notify.dart';

class IMChatsTab extends StatefulWidget {
  final String token;
  final String userId;
  final String userCode;
  final Stream<Map<String, dynamic>>? msgStream;
  final VoidCallback? onUnreadChanged;
  final bool Function()? isTabActive;

  const IMChatsTab({
    super.key,
    required this.token,
    required this.userId,
    this.userCode = '',
    this.msgStream,
    this.onUnreadChanged,
    this.isTabActive,
  });

  @override
  State<IMChatsTab> createState() => IMChatsTabState();
}

class IMChatsTabState extends State<IMChatsTab> with AutomaticKeepAliveClientMixin {
  List<dynamic> _sessions = [];
  List<dynamic> _groups = [];
  bool _loading = true;
  bool _groupsExpanded = true;
  bool _singlesExpanded = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<dynamic> _remoteUsers = [];
  bool _remoteSearchLoading = false;
  Timer? _searchDebounce;
  Timer? _wsReloadDebounce;
  DateTime? _lastFetch;
  bool _refreshing = false;
  StreamSubscription? _wsSub;
  Set<String> _pinned = {};
  Set<String> _muted = {};
  Set<String> _hidden = {};
  bool _showHidden = false;
  bool _mentionGroupsOnly = false;
  bool _mentionSinglesOnly = false;
  bool _noticeGroupsOnly = false;
  Set<String> _myMentionNames = {};
  Set<String> _newNoticeGroups = {};
  late final ImApi _im = ImApi(widget.token);

  String _groupPinKey(String groupId) => 'g:$groupId';
  String _singlePinKey(String peerId) => 's:$peerId';
  String _normalizePinKey(String key) {
    if (key.startsWith('g:') || key.startsWith('s:')) return key;
    return 's:$key';
  }
  bool _isPinned(String key) => _pinned.contains(key);
  bool _isMuted(String key) => _muted.contains(key);
  bool _isHidden(String key) => _hidden.contains(key);

  bool _singleHasMentionUnread(dynamic s) {
    if (sessionUnread(s) <= 0) return false;
    return lastMsgMentionsMe((s['lastMsg'] ?? '').toString(), _myMentionNames);
  }

  int _singleMentionRank(dynamic s) => _singleHasMentionUnread(s) ? 0 : 1;

  int _groupMentionRank(dynamic g) {
    final unread = sessionUnread(g, group: true);
    if (unread <= 0) return 1;
    final last = (g['lastMsg'] ?? '').toString();
    return lastMsgMentionsMe(last, _myMentionNames) ? 0 : 1;
  }

  bool _groupHasMentionUnread(dynamic g) => _groupMentionRank(g) == 0;

  Future<void> _loadMentionNames() async {
    final email = await SessionStore.loadLastEmail();
    final names = {
      widget.userId,
      if (widget.userCode.isNotEmpty) widget.userCode,
      if (email != null && email.isNotEmpty) email,
      if (email != null && email.contains('@')) email.split('@').first,
    }.where((n) => n.isNotEmpty).toSet();
    if (mounted) setState(() => _myMentionNames = names);
  }

  int _pinRank(String key) => _isPinned(key) ? 0 : 1;

  int get _mentionGroupUnreadCount => _groups.where(_groupHasMentionUnread).fold<int>(0, (s, g) => s + sessionUnread(g, group: true));

  int get _mentionSingleUnreadCount => _sessions.where(_singleHasMentionUnread).length;

  int get _newNoticeCount => _newNoticeGroups.length;

  Future<void> _refreshNoticeFlags() async {
    final next = <String>{};
    for (final g in _groups) {
      final gid = (g['groupId'] ?? '').toString();
      final notice = (g['notice'] ?? '').toString();
      if (gid.isEmpty || notice.isEmpty) continue;
      final seen = await SessionStore.loadGroupNoticeSeen(gid);
      if (seen != notice.hashCode.toString()) next.add(gid);
    }
    if (mounted) setState(() => _newNoticeGroups = next);
  }

  Map<String, String>? _lookupNotifyTarget(Map<String, dynamic> msg) {
    final gid = (msg['groupId'] ?? msg['ext']?['groupId'] ?? '').toString();
    if (gid.isNotEmpty) {
      for (final g in _groups) {
        if ((g['groupId'] ?? '').toString() == gid) {
          final name = (g['groupName'] ?? g['name'] ?? '群聊').toString();
          return {'groupId': gid, 'groupName': name, 'title': name};
        }
      }
      return {'groupId': gid, 'groupName': '群聊', 'title': '群聊'};
    }
    final from = (msg['fromUserId'] ?? msg['ext']?['fromUserId'] ?? '').toString();
    if (from.isEmpty) return null;
    for (final s in _sessions) {
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      if (peerId == from) {
        final peerName = (s['peerName'] ?? peerId).toString();
        return {'peerId': from, 'peerName': peerName, 'title': peerName};
      }
    }
    return {'peerId': from, 'title': from};
  }

  Future<void> _loadPinned() async {
    final keys = await SessionStore.loadPinnedSessions();
    if (mounted) setState(() => _pinned = keys.map(_normalizePinKey).toSet());
  }

  Future<void> _loadMuted() async {
    final keys = await SessionStore.loadMutedSessions();
    if (mounted) setState(() => _muted = keys.map(_normalizePinKey).toSet());
  }

  Future<void> _loadHidden() async {
    final keys = await SessionStore.loadHiddenSessions();
    if (mounted) setState(() => _hidden = keys);
  }

  Future<void> _setHidden(String key, bool hidden, {required String title, String? sessionId, bool snack = true}) async {
    final next = Set<String>.from(_hidden);
    if (hidden) {
      next.add(key);
    } else {
      next.remove(key);
    }
    setState(() => _hidden = next);
    await SessionStore.saveHiddenSessions(next);
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        await _im.setSessionHidden(sessionId, hidden);
      } catch (_) {}
    }
    if (snack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(hidden ? '已隐藏「$title」' : '已恢复显示'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _toggleHide(String key, {required String title, String? sessionId}) async {
    await _setHidden(key, !_isHidden(key), title: title, sessionId: sessionId);
  }

  Future<void> _markSessionRead(String msgId) async {
    if (msgId.isEmpty) return;
    try {
      await _im.markRead(msgId);
      if (mounted) {
        _loadAll();
        widget.onUnreadChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已标为已读'), duration: Duration(seconds: 1)),
        );
      }
    } catch (_) {}
  }

  int get _totalUnread {
    var n = 0;
    for (final s in _sessions) {
      n += sessionUnread(s);
    }
    for (final g in _groups) {
      n += sessionUnread(g, group: true);
    }
    return n;
  }

  Future<void> _markAllRead() async {
    if (_totalUnread <= 0) return;
    final ids = <String>[];
    for (final s in _sessions) {
      if (sessionUnread(s) <= 0) continue;
      final id = (s['lastMsgId'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }
    for (final g in _groups) {
      if (sessionUnread(g, group: true) <= 0) continue;
      final id = (g['lastMsgId'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return;
    for (final id in ids.take(50)) {
      try {
        await _im.markRead(id);
      } catch (_) {}
    }
    if (!mounted) return;
    await _loadAll();
    widget.onUnreadChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已全部标为已读'), duration: Duration(seconds: 1)),
    );
  }

  /// Web 通知点击后打开对应会话
  void openFromNotify(Map<String, String> data) {
    final gid = data['groupId'] ?? '';
    final gname = data['groupName'] ?? '群聊';
    final peerId = data['peerId'] ?? '';
    if (gid.isNotEmpty) {
      dynamic group;
      for (final g in _groups) {
        if ((g['groupId'] ?? '').toString() == gid) {
          group = g;
          break;
        }
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            token: widget.token,
            groupId: gid,
            groupName: (group?['groupName'] ?? group?['name'] ?? gname).toString(),
            userId: widget.userId,
            msgStream: widget.msgStream,
            initialMembers: (group?['members'] as List<dynamic>?) ?? [],
          ),
        ),
      ).then((_) {
        if (mounted) _loadAll();
      });
      return;
    }
    if (peerId.isEmpty) return;
    dynamic session;
    for (final s in _sessions) {
      final pid = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      if (pid == peerId) {
        session = s;
        break;
      }
    }
    final peerName = (session?['peerName'] ?? peerId).toString();
    _openChatPage(peerId, session: session, peerName: peerName);
  }

  Future<void> openFromUserCode(String code) async {
    try {
      final resp = await authApi.userByCode(code);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('未找到展示码 $code')));
        return;
      }
      final u = jsonDecode(resp.body) as Map<String, dynamic>;
      final peerId = (u['userId'] ?? '').toString();
      if (peerId.isEmpty) return;
      if (peerId == widget.userId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这是你自己的展示码')));
        return;
      }
      final peerName = (u['displayName'] ?? u['nickname'] ?? u['userCode'] ?? peerId).toString();
      await _openChatPage(
        peerId,
        peerName: peerName,
        peerUserCode: (u['userCode'] ?? code).toString(),
        peerLevelName: (u['levelName'] ?? '').toString(),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败: $e')));
    }
  }

  Future<void> _openChatPage(
    String peerId, {
    dynamic session,
    String? peerName,
    String? peerUserCode,
    String? peerLevelName,
  }) async {
    final name = peerName ?? (session?['peerName'] ?? peerId).toString();
    final code = peerUserCode ?? (session?['peerUserCode'] ?? '').toString();
    final level = peerLevelName ?? (session?['peerLevelName'] ?? '').toString();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          token: widget.token,
          userId: widget.userId,
          userCode: widget.userCode,
          peerId: peerId,
          peerName: name,
          peerUserCode: code,
          peerLevelName: level,
          msgStream: widget.msgStream,
        ),
      ),
    );
    if (mounted) _loadAll();
  }

  Widget _wrapSessionDismissible({
    required String dismissKey,
    required String pinKey,
    required String title,
    required Widget child,
    int unread = 0,
    String? lastMsgId,
    String? sessionId,
  }) {
    if (_searchQuery.trim().isNotEmpty) return child;
    final restoring = _showHidden;
    if (restoring) {
      return Dismissible(
        key: ValueKey(dismissKey),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.green.shade500,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.visibility_outlined, color: Colors.white),
        ),
        onDismissed: (_) => _setHidden(pinKey, false, title: title, sessionId: sessionId, snack: true),
        child: child,
      );
    }
    final msgId = lastMsgId?.trim() ?? '';
    final canMarkRead = unread > 0 && msgId.isNotEmpty;
    return Dismissible(
      key: ValueKey(dismissKey),
      direction: canMarkRead ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: canMarkRead
          ? Container(
              color: Colors.blue.shade500,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(Icons.done_all, color: Colors.white),
            )
          : null,
      secondaryBackground: Container(
        color: Colors.grey.shade600,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.visibility_off_outlined, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd && canMarkRead) {
          await _markSessionRead(msgId);
          return false;
        }
        return true;
      },
      onDismissed: (_) => _setHidden(pinKey, true, title: title, sessionId: sessionId, snack: true),
      child: child,
    );
  }

  Future<void> _restoreAllHidden() async {
    if (_hidden.isEmpty) return;
    final n = _hidden.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部恢复'),
        content: Text('恢复全部 $n 个隐藏会话？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final keys = _hidden.toList();
    for (final key in keys) {
      final sid = _sessionIdForPinKey(key);
      if (sid != null && sid.isNotEmpty) {
        try {
          await _im.setSessionHidden(sid, false);
        } catch (_) {}
      }
    }
    setState(() => _hidden = {});
    await SessionStore.saveHiddenSessions({});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢复 $n 个会话'), duration: const Duration(seconds: 1)),
      );
    }
  }

  void _mergeSessionFlagsFromApi(List<dynamic> rawSessions) {
    // ponytail: server is source of truth on each refresh; fixes cross-device pin/mute/hidden drift
    final pinned = <String>{};
    final muted = <String>{};
    final hidden = <String>{};
    for (final s in rawSessions) {
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      final gid = (s['peerGroupId'] ?? '').toString();
      if (peerId.isNotEmpty && gid.isEmpty) {
        final key = _singlePinKey(peerId);
        if (s['pinned'] == true) pinned.add(key);
        if (s['muted'] == true) muted.add(key);
        if (s['hidden'] == true) hidden.add(key);
      }
      if (gid.isNotEmpty) {
        final key = _groupPinKey(gid);
        if (s['pinned'] == true) pinned.add(key);
        if (s['muted'] == true) muted.add(key);
        if (s['hidden'] == true) hidden.add(key);
      }
    }
    _pinned = pinned;
    _muted = muted;
    _hidden = hidden;
  }

  String _sessionIdForGroup(String groupId) => '${widget.userId}:$groupId';

  String? _sessionIdForPinKey(String pinKey) {
    if (pinKey.startsWith('g:')) return _sessionIdForGroup(pinKey.substring(2));
    final peerId = pinKey.startsWith('s:') ? pinKey.substring(2) : pinKey;
    for (final s in _sessions) {
      final pid = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      if (pid == peerId) {
        final sid = (s['sessionId'] ?? '').toString();
        return sid.isEmpty ? null : sid;
      }
    }
    return null;
  }

  Future<void> _togglePin(String key, {String? sessionId}) async {
    final sid = sessionId ?? _sessionIdForPinKey(key);
    if (sid == null || sid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法同步置顶状态'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    final wasPinned = _pinned.contains(key);
    setState(() {
      final next = Set<String>.from(_pinned);
      if (wasPinned) {
        next.remove(key);
      } else {
        next.add(key);
      }
      _pinned = next;
    });
    try {
      final resp = await _im.togglePinSession(sid);
      if (resp.statusCode != 200) throw Exception(resp.body);
      final pinned = jsonDecode(resp.body)['pinned'] == true;
      setState(() {
        final next = Set<String>.from(_pinned);
        if (pinned) {
          next.add(key);
        } else {
          next.remove(key);
        }
        _pinned = next;
      });
      await SessionStore.savePinnedSessions(_pinned);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(pinned ? '已置顶' : '已取消置顶'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      setState(() {
        final next = Set<String>.from(_pinned);
        if (wasPinned) {
          next.add(key);
        } else {
          next.remove(key);
        }
        _pinned = next;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('置顶失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _toggleMute(String key, {String? sessionId}) async {
    final sid = sessionId ?? _sessionIdForPinKey(key);
    if (sid == null || sid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法同步免打扰状态'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    final wasMuted = _muted.contains(key);
    setState(() {
      final next = Set<String>.from(_muted);
      if (wasMuted) {
        next.remove(key);
      } else {
        next.add(key);
      }
      _muted = next;
    });
    try {
      final resp = await _im.toggleMuteSession(sid);
      if (resp.statusCode != 200) throw Exception(resp.body);
      final muted = jsonDecode(resp.body)['muted'] == true;
      setState(() {
        final next = Set<String>.from(_muted);
        if (muted) {
          next.add(key);
        } else {
          next.remove(key);
        }
        _muted = next;
      });
      await SessionStore.saveMutedSessions(_muted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(muted ? '已开启免打扰' : '已关闭免打扰'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      setState(() {
        final next = Set<String>.from(_muted);
        if (wasMuted) {
          next.add(key);
        } else {
          next.remove(key);
        }
        _muted = next;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('免打扰设置失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _showSessionActions({
    required String pinKey,
    required String title,
    String? sessionId,
    int unread = 0,
    String? lastMsgId,
  }) {
    final pinned = _isPinned(pinKey);
    final muted = _isMuted(pinKey);
    final hidden = _isHidden(pinKey);
    final msgId = lastMsgId?.trim() ?? '';
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (!_showHidden && unread > 0 && msgId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('标为已读'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _markSessionRead(msgId);
                },
              ),
            if (!_showHidden) ...[
              ListTile(
                leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(pinned ? '取消置顶' : '置顶'),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(pinKey, sessionId: sessionId);
                },
              ),
              ListTile(
                leading: Icon(muted ? Icons.notifications : Icons.notifications_off_outlined),
                title: Text(muted ? '关闭免打扰' : '免打扰'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleMute(pinKey, sessionId: sessionId);
                },
              ),
            ],
            ListTile(
              leading: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              title: Text(hidden ? '恢复显示' : '隐藏会话'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleHide(pinKey, title: title, sessionId: sessionId);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  void refreshIfStale({Duration maxAge = const Duration(seconds: 30)}) {
    final now = DateTime.now();
    if (_lastFetch != null && now.difference(_lastFetch!) < maxAge) return;
    _loadAll(silent: _sessions.isNotEmpty || _groups.isNotEmpty);
  }

  void _debouncedWsReload() {
    if (widget.isTabActive != null && !widget.isTabActive!()) return;
    _wsReloadDebounce?.cancel();
    _wsReloadDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _loadAll(silent: _sessions.isNotEmpty || _groups.isNotEmpty);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _loadMuted();
    _loadHidden();
    _loadMentionNames();
    _loadPrefs();
    _boot();
    setupImNotifyLookup(_lookupNotifyTarget);
    _wsSub = widget.msgStream?.listen((m) {
      if ((m['type'] ?? '').toString() != 'im' || !mounted) return;
      _debouncedWsReload();
    });
  }

  @override
  void dispose() {
    setupImNotifyLookup(null);
    _wsReloadDebounce?.cancel();
    _wsSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    setState(() => _searchQuery = v);
    _scheduleRemoteSearch(v);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _remoteUsers = [];
      _remoteSearchLoading = false;
    });
  }

  void _scheduleRemoteSearch(String text) {
    _searchDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (_remoteUsers.isNotEmpty || _remoteSearchLoading) {
        setState(() {
          _remoteUsers = [];
          _remoteSearchLoading = false;
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _remoteSearchLoading = true);
      try {
        final resp = await _im.searchUsers(q);
        if (!mounted) return;
        if (_searchQuery.trim() != q) {
          setState(() => _remoteSearchLoading = false);
          return;
        }
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          setState(() {
            _remoteUsers = (data['users'] as List<dynamic>? ?? [])
                .where((u) => (u['userId'] ?? '').toString() != widget.userId)
                .where((u) => userRecordMatchesQuery(u, q))
                .toList();
            _remoteSearchLoading = false;
          });
        } else {
          setState(() => _remoteSearchLoading = false);
        }
      } catch (_) {
        if (mounted) setState(() => _remoteSearchLoading = false);
      }
    });
  }

  Set<String> get _remoteMatchedUserIds => _remoteUsers
      .map((u) => (u['userId'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();

  bool _singleMatchesSearch(dynamic s) {
    if (sessionMatchesQuery(s, _searchQuery)) return true;
    if (!_isSearching) return false;
    final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
    return _remoteMatchedUserIds.contains(peerId);
  }

  List<dynamic> get _remoteOnlyUsers {
    if (!_isSearching) return [];
    final inSessions = _sessions
        .map((s) => (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
    return _remoteUsers.where((u) => !inSessions.contains((u['userId'] ?? '').toString())).toList();
  }

  Future<void> _loadPrefs() async {
    final g = await SessionStore.loadImGroupsExpanded();
    final s = await SessionStore.loadImSinglesExpanded();
    if (mounted) setState(() {
      _groupsExpanded = g;
      _singlesExpanded = s;
    });
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  List<dynamic> get _filteredGroups {
    final list = _groups.where((g) {
      final key = _groupPinKey((g['groupId'] ?? '').toString());
      if (!_isSearching && _isHidden(key) != _showHidden) return false;
      if (!_isSearching && _mentionGroupsOnly && !_groupHasMentionUnread(g)) return false;
      if (!_isSearching && _noticeGroupsOnly && !_newNoticeGroups.contains((g['groupId'] ?? '').toString())) return false;
      return sessionMatchesQuery(g, _searchQuery, group: true);
    }).toList();
    list.sort((a, b) => compareImSessions(
          a,
          b,
          group: true,
          pinRank: _pinRank,
          pinKeyOf: (g) => _groupPinKey((g['groupId'] ?? '').toString()),
          mentionRank: _groupMentionRank,
        ));
    return list;
  }

  List<dynamic> get _filteredSessions {
    final list = _sessions.where((s) {
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      final key = _singlePinKey(peerId);
      if (!_isSearching && _isHidden(key) != _showHidden) return false;
      if (!_isSearching && _mentionSinglesOnly && !_singleHasMentionUnread(s)) return false;
      return _singleMatchesSearch(s);
    }).toList();
    list.sort((a, b) => compareImSessions(
          a,
          b,
          group: false,
          pinRank: _pinRank,
          pinKeyOf: (s) => _singlePinKey((s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString()),
          mentionRank: _singleMentionRank,
        ));
    return list;
  }

  Future<void> _boot() async {
    if (!TabDataCache.hasSessions) await TabDataCache.restore(widget.token);
    if (!mounted) return;
    if (TabDataCache.hasSessions) {
      setState(() {
        _groups = List<dynamic>.from(TabDataCache.groups ?? []);
        _sessions = List<dynamic>.from(TabDataCache.sessions!);
        _loading = false;
      });
      _lastFetch = DateTime.now();
      _loadAll(silent: true);
    } else {
      _loadAll();
    }
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && _sessions.isEmpty && _groups.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      await _loadGroups();
      await _loadSessions();
      await _refreshNoticeFlags();
      _lastFetch = DateTime.now();
    } finally {
      _refreshing = false;
    }
    // ponytail: 由 HomePage 防抖拉 unread，避免 WS 每条消息 sessions+groups+unread 三连
  }

  Future<void> _loadGroups() async {
    try {
      final resp = await _im.groups();
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() => _groups = data['groups'] ?? []);
        TabDataCache.putGroups(_groups);
      }
    } catch (e) {
      debugPrint('_loadGroups error: $e');
    }
  }

  void _mergeGroupMetaFromSessions(List<dynamic> rawSessions) {
    final byGroup = <String, dynamic>{};
    for (final s in rawSessions) {
      final gid = (s['peerGroupId'] ?? '').toString();
      if (gid.isNotEmpty) byGroup[gid] = s;
    }
    _groups = _groups.map((g) {
      final gid = (g['groupId'] ?? '').toString();
      final sess = byGroup[gid];
      if (sess == null) return g;
      final m = Map<String, dynamic>.from(g as Map);
      final u = sessionUnread(sess);
      if (u > 0) m['unreadCount'] = u;
      final mid = (sess['lastMsgId'] ?? '').toString();
      if (mid.isNotEmpty) m['lastMsgId'] = mid;
      final lm = (sess['lastMsg'] ?? '').toString();
      if (lm.isNotEmpty) m['lastMsg'] = lm;
      final lt = sess['lastMsgTime'];
      if (lt != null) m['lastMsgTime'] = lt;
      return m;
    }).toList();
  }

  Future<void> _loadSessions() async {
    try {
      final resp = await _im.sessions();
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final groupIds = _groups.map((g) => (g['groupId'] ?? '').toString()).toSet();
        final rawSessions = data['sessions'] as List<dynamic>? ?? [];
        setState(() {
          _mergeGroupMetaFromSessions(rawSessions);
          _sessions = rawSessions.where((s) {
            final sType = s['type']?.toString() ?? '';
            final sPeerGroupId = s['peerGroupId']?.toString() ?? '';
            if (sType == 'group') return false;
            if (sPeerGroupId.isNotEmpty && groupIds.contains(sPeerGroupId)) return false;
            return true;
          }).toList();
          _mergeSessionFlagsFromApi(rawSessions);
          _loading = false;
        });
        TabDataCache.putSessions(_sessions);
        SessionStore.savePinnedSessions(_pinned);
        SessionStore.saveMutedSessions(_muted);
        SessionStore.saveHiddenSessions(_hidden);
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('_loadSessions error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int _unreadSum(List<dynamic> items, {bool group = false}) =>
      items.fold<int>(0, (sum, item) => sum + sessionUnread(item, group: group));

  Widget _sectionHeader({
    required String title,
    required int count,
    required int unread,
    required bool expanded,
    required VoidCallback? onToggle,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
          child: Row(
            children: [
              if (onToggle != null)
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right, size: 22, color: Colors.grey.shade700),
                )
              else
                const SizedBox(width: 22),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _countChip('$count'),
              if (unread > 0) ...[
                const SizedBox(width: 6),
                _countChip('$unread 未读', highlight: true),
              ],
              const Spacer(),
              if (onToggle != null)
                Text(expanded ? '收起' : '展开', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String text, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? Colors.red.shade50 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: highlight ? Colors.red.shade700 : Colors.grey.shade700, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _sessionTrailing({required int unread, required String? timeIso}) {
    final time = formatSessionTime(timeIso);
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          if (unread > 0) ...[
            if (time.isNotEmpty) const SizedBox(height: 6),
            Badge(label: Text(unread > 99 ? '99+' : '$unread')),
          ],
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      !_showHidden && (_mentionGroupsOnly || _mentionSinglesOnly || _noticeGroupsOnly);

  String get _filterSummary {
    final parts = <String>[];
    if (_mentionGroupsOnly) parts.add('@我的群 ${_filteredGroups.length}');
    if (_mentionSinglesOnly) parts.add('@我的单聊 ${_filteredSessions.length}');
    if (_noticeGroupsOnly) parts.add('新公告');
    return parts.join(' · ');
  }

  void _clearFilters() => setState(() {
        _mentionGroupsOnly = false;
        _mentionSinglesOnly = false;
        _noticeGroupsOnly = false;
      });

  Future<void> _showFilterSheet() async {
    var mentionGroups = _mentionGroupsOnly;
    var mentionSingles = _mentionSinglesOnly;
    var notice = _noticeGroupsOnly;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('筛选会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  title: const Text('群聊 · 仅 @我的未读'),
                  subtitle: Text(_mentionGroupUnreadCount > 0 ? '当前有 $_mentionGroupUnreadCount 个群未读@我' : '暂无@我的未读群'),
                  value: mentionGroups,
                  onChanged: (v) => setSheet(() => mentionGroups = v),
                ),
                SwitchListTile(
                  title: const Text('单聊 · 仅 @我的未读'),
                  subtitle: Text(_mentionSingleUnreadCount > 0 ? '当前有 $_mentionSingleUnreadCount 个单聊未读@我' : '暂无@我的未读单聊'),
                  value: mentionSingles,
                  onChanged: (v) => setSheet(() => mentionSingles = v),
                ),
                SwitchListTile(
                  title: const Text('群聊 · 仅有新公告'),
                  subtitle: Text(_newNoticeCount > 0 ? '当前有 $_newNoticeCount 个群有新公告' : '暂无新公告'),
                  value: notice,
                  onChanged: (v) => setSheet(() => notice = v),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '手势：右滑标为已读 · 左滑隐藏会话',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _mentionGroupsOnly = mentionGroups;
                          _mentionSinglesOnly = mentionSingles;
                          _noticeGroupsOnly = notice;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(String value) async {
    switch (value) {
      case 'contacts':
        _openContacts(context);
      case 'hidden':
        setState(() => _showHidden = !_showHidden);
      case 'refresh':
        await _loadAll();
      case 'read_all':
        await _markAllRead();
      case 'new':
        if (mounted) _showNewChatMenu();
    }
  }

  Widget _groupTile(dynamic g) {
    final unread = sessionUnread(g, group: true);
    final groupId = (g['groupId'] ?? '').toString();
    final pinKey = _groupPinKey(groupId);
    final pinned = _isPinned(pinKey);
    final muted = _isMuted(pinKey);
    final name = g['groupName'] ?? g['name'] ?? '群聊';
    final lastMsgId = (g['lastMsgId'] ?? '').toString();
    final time = (g['lastMsgTime'] ?? g['updatedAt'] ?? g['createdAt'])?.toString();
    final nameStr = name.toString();
    return _wrapSessionDismissible(
      dismissKey: 'g:$groupId',
      pinKey: pinKey,
      title: nameStr,
      unread: unread,
      lastMsgId: lastMsgId,
      sessionId: _sessionIdForGroup(groupId),
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(Icons.group, size: 20, color: Colors.white)),
      title: Text(
        nameStr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal),
      ),
      subtitle: Text(
        sessionListPreview(
          g,
          pinned: pinned,
          muted: muted,
          mentionUnread: _groupHasMentionUnread(g),
          newNotice: _newNoticeGroups.contains(groupId),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: unread > 0 ? Colors.grey.shade800 : Colors.grey.shade600),
      ),
      trailing: _sessionTrailing(unread: unread, timeIso: time),
      onLongPress: () => _showSessionActions(
        pinKey: pinKey,
        title: nameStr,
        sessionId: _sessionIdForGroup(groupId),
        unread: unread,
        lastMsgId: lastMsgId,
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatPage(
              token: widget.token,
              groupId: g['groupId'] ?? '',
              groupName: name,
              userId: widget.userId,
              msgStream: widget.msgStream,
              initialMembers: (g['members'] as List<dynamic>?) ?? [],
            ),
          ),
        );
        if (mounted) _loadAll();
      },
    ),
    );
  }

  Widget _singleTile(dynamic s) {
    final unread = sessionUnread(s);
    final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
    final peerName = (s['peerName'] ?? peerId).toString();
    final peerCode = (s['peerUserCode'] ?? '').toString();
    final peerLevel = (s['peerLevelName'] ?? '').toString();
    final peerPremium = s['peerPremium'] == true;
    final sessionId = (s['sessionId'] ?? '').toString();
    final pinKey = _singlePinKey(peerId);
    final pinned = _isPinned(pinKey);
    final muted = _isMuted(pinKey);
    final time = (s['lastMsgTime'] ?? s['updatedAt'] ?? s['createdAt'])?.toString();
    final lastMsgId = (s['lastMsgId'] ?? '').toString();
    final initial = peerName.isNotEmpty ? peerName[0].toUpperCase() : '?';
    return _wrapSessionDismissible(
      dismissKey: 's:$peerId',
      pinKey: pinKey,
      title: peerName,
      unread: unread,
      lastMsgId: lastMsgId,
      sessionId: sessionId.isEmpty ? null : sessionId,
      child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(child: Text(initial)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal),
            ),
          ),
          if (peerPremium && peerLevel.isNotEmpty) PremiumLevelChip(levelName: peerLevel, compact: true),
        ],
      ),
      subtitle: peerCode.isNotEmpty
          ? GestureDetector(
              onTap: () => showUserProfileSheet(
                context,
                userId: peerId,
                displayName: peerName,
                userCode: peerCode,
                levelName: peerLevel,
                premium: peerPremium,
                token: widget.token,
                sheetContext: UserProfileContext.viewOnly,
              ),
              child: Text(
                '$peerCode · ${sessionListPreview(s, pinned: pinned, muted: muted, mentionUnread: _singleHasMentionUnread(s))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: unread > 0 ? Colors.grey.shade800 : Colors.grey.shade600),
              ),
            )
          : Text(
              sessionListPreview(
                s,
                pinned: pinned,
                muted: muted,
                mentionUnread: _singleHasMentionUnread(s),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread > 0 ? Colors.grey.shade800 : Colors.grey.shade600),
            ),
      trailing: _sessionTrailing(unread: unread, timeIso: time),
      onLongPress: () => _showSessionActions(
        pinKey: pinKey,
        title: peerName,
        sessionId: sessionId.isEmpty ? null : sessionId,
        unread: unread,
        lastMsgId: lastMsgId,
      ),
      onTap: () async {
        if (peerId.isEmpty) return;
        await _openChatPage(peerId, session: s, peerName: peerName);
      },
    ),
    );
  }

  List<Widget> _buildListChildren() {
    final groups = _filteredGroups;
    final sessions = _filteredSessions;
    final contacts = _remoteOnlyUsers;
    final searching = _searchQuery.trim().isNotEmpty;
    final children = <Widget>[];

    if (searching && groups.isEmpty && sessions.isEmpty && contacts.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _remoteSearchLoading
                ? '正在搜索联系人…'
                : '没有匹配的会话或联系人\n可搜：昵称、展示码、邮箱、群名、最后一条消息\n（不含聊天记录全文）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
          ),
        ),
      ));
      return children;
    }

    if (!searching && groups.isEmpty && sessions.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _showHidden ? '暂无隐藏会话' : '暂无会话',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ));
      return children;
    }

    if (groups.isNotEmpty) {
      children.add(_sectionHeader(
        title: '群聊',
        count: groups.length,
        unread: _unreadSum(groups, group: true),
        expanded: searching ? true : _groupsExpanded,
        onToggle: searching ? null : () async {
          setState(() => _groupsExpanded = !_groupsExpanded);
          await SessionStore.saveImGroupsExpanded(_groupsExpanded);
        },
      ));
      if (searching || _groupsExpanded) {
        for (final g in groups) {
          children.add(_groupTile(g));
          children.add(Divider(height: 1, indent: 72, color: Colors.grey.shade200));
        }
      }
    }
    if (sessions.isNotEmpty) {
      children.add(_sectionHeader(
        title: '单聊',
        count: sessions.length,
        unread: _unreadSum(sessions),
        expanded: searching ? true : _singlesExpanded,
        onToggle: searching ? null : () async {
          setState(() => _singlesExpanded = !_singlesExpanded);
          await SessionStore.saveImSinglesExpanded(_singlesExpanded);
        },
      ));
      if (searching || _singlesExpanded) {
        for (final s in sessions) {
          children.add(_singleTile(s));
          children.add(Divider(height: 1, indent: 72, color: Colors.grey.shade200));
        }
      }
    }
    if (contacts.isNotEmpty) {
      children.add(_sectionHeader(
        title: '联系人',
        count: contacts.length,
        unread: 0,
        expanded: true,
        onToggle: null,
      ));
      for (final u in contacts) {
        children.add(_contactTile(u));
        children.add(Divider(height: 1, indent: 72, color: Colors.grey.shade200));
      }
    }
    return children;
  }

  String _userDisplayName(dynamic u) =>
      (u['nickname'] ?? u['displayName'] ?? u['userCode'] ?? u['userId'] ?? '').toString();

  Widget _contactTile(dynamic u) {
    final userId = (u['userId'] ?? '').toString();
    final name = _userDisplayName(u);
    final userCode = (u['userCode'] ?? '').toString();
    final levelName = (u['levelName'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(child: Text(initial)),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (userCode.isNotEmpty) UserCodeRow(userCode: userCode, levelName: levelName),
          if (email.isNotEmpty)
            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
      trailing: const Icon(Icons.chat_bubble_outline, size: 20),
      onTap: () async {
        if (userId.isEmpty) return;
        await _openChatPage(
          userId,
          peerName: name,
          peerUserCode: userCode,
          peerLevelName: levelName,
        );
        if (mounted) _clearSearch();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final listEmpty = _filteredGroups.isEmpty && _filteredSessions.isEmpty && _remoteOnlyUsers.isEmpty;
    final noData = _groups.isEmpty && _sessions.isEmpty;

    final barW = MediaQuery.sizeOf(context).width;
    final searchW = barW * 2 / 3;
    final labelStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16) ?? const TextStyle(fontSize: 16);

    Widget plusBtn() {
      if (!_showHidden) {
        return toolbarPlusButton(
          context,
          onPressed: () => showChatComposerMoreSheet(context, actions: [
            ChatComposerAction(id: 'new', icon: Icons.add_comment_outlined, label: '发起聊天', onTap: _showNewChatMenu),
            ChatComposerAction(id: 'contacts', icon: Icons.contacts_outlined, label: '通讯录', onTap: () => _openContacts(context)),
            ChatComposerAction(id: 'filter', icon: Icons.filter_list, label: '筛选', onTap: () => _showFilterSheet()),
            ChatComposerAction(id: 'hidden', icon: Icons.visibility_off_outlined, label: '已隐藏', onTap: () => setState(() => _showHidden = true)),
            if (_totalUnread > 0)
              ChatComposerAction(id: 'read_all', icon: Icons.done_all_outlined, label: '全部已读', onTap: _markAllRead),
            ChatComposerAction(id: 'refresh', icon: Icons.refresh, label: '刷新', onTap: _loadAll),
          ]),
        );
      }
      return toolbarPlusButton(
        context,
        onPressed: () => showChatComposerMoreSheet(context, actions: [
          if (_hidden.isNotEmpty)
            ChatComposerAction(id: 'restore_all', icon: Icons.unarchive_outlined, label: '全部恢复', onTap: _restoreAllHidden),
          ChatComposerAction(id: 'back', icon: Icons.chat_outlined, label: '返回列表', onTap: () => setState(() => _showHidden = false)),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        titleSpacing: 16,
        actions: const [],
        title: SizedBox(
          width: barW - 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(_showHidden ? '已隐藏' : '消息', style: labelStyle),
                  plusBtn(),
                ],
              ),
              SizedBox(
                width: searchW,
                child: TextField(
                  controller: _searchController,
                  textAlign: TextAlign.center,
                  style: labelStyle.copyWith(fontWeight: FontWeight.normal),
                  decoration: InputDecoration(
                    hintText: '昵称/展示码/群名',
                    hintStyle: labelStyle.copyWith(
                      fontWeight: FontWeight.normal,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    suffixIcon: _searchQuery.trim().isEmpty
                        ? null
                        : IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _clearSearch,
                          ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasActiveFilters)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.filter_list, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_filterSummary, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface))),
                    TextButton(onPressed: _clearFilters, child: const Text('清除')),
                  ],
                ),
              ),
            ),
          if (_showHidden)
            Material(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('已隐藏会话 · 左滑或长按可恢复', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
            ),
          if (_isSearching && _remoteSearchLoading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading && _sessions.isEmpty && _groups.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : noData
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('暂无会话', style: TextStyle(color: Colors.grey.shade600)),
                            const SizedBox(height: 16),
                            FilledButton.icon(onPressed: _showNewChatMenu, icon: const Icon(Icons.add), label: const Text('发起聊天')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: listEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 80),
                                children: _buildListChildren(),
                              )
                            : ListView(padding: const EdgeInsets.only(bottom: 80), children: _buildListChildren()),
                      ),
          ),
        ],
      ),
      floatingActionButton: _showHidden
          ? null
          : FloatingActionButton(
              heroTag: 'im_fab',
              onPressed: _showNewChatMenu,
              child: const Icon(Icons.add),
            ),
    );
  }

  void _showNewChatMenu() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('发起单聊'),
              subtitle: const Text('搜索邮箱 / 昵称 / 用户 ID'),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (!mounted) return;
                _showNewChat(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('创建群聊'),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (!mounted) return;
                _showCreateGroup(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('加入群聊'),
              onTap: () {
                Navigator.pop(sheetCtx);
                if (!mounted) return;
                _showJoinGroup(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openContacts(BuildContext context) async {
    final recent = _sessions.map((s) {
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      final peerName = (s['peerName'] ?? peerId).toString();
      return {'userId': peerId, 'displayName': peerName};
    }).where((u) => u['userId']!.isNotEmpty).toList();

    final picked = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactsPage(
          im: _im,
          currentUserId: widget.userId,
          recentUsers: recent,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final peerId = picked['userId'] ?? '';
    if (peerId.isEmpty) return;
    final peerName = picked['displayName'] ?? peerId;
    await _openChatPage(peerId, peerName: peerName);
  }

  void _showNewChat(BuildContext context) async {
    final recent = _sessions.map((s) {
      final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
      final peerName = (s['peerName'] ?? peerId).toString();
      return {'userId': peerId, 'displayName': peerName};
    }).where((u) => u['userId']!.isNotEmpty).toList();

    final ids = await showUserPickSheet(
      context,
      im: _im,
      title: '发起单聊',
      confirmLabel: '按输入开始聊天',
      recentUsers: recent,
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final peerId = ids.first;
    await _openChatPage(peerId);
  }

  void _showCreateGroup(BuildContext context) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('创建群聊'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '群名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dlgCtx, nameController.text.trim()), child: const Text('下一步')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final members = await showUserPickSheet(
      context,
      im: _im,
      title: '邀请成员',
      multiSelect: true,
      confirmLabel: '创建群聊',
      excludeUserIds: {widget.userId},
    );
    if (members == null || members.isEmpty || !mounted) return;
    await _createGroup(name, members);
  }

  Future<void> _createGroup(String name, List<String> members) async {
    try {
      final resp = await _im.createGroup(name, members);
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('群聊 "$name" 创建成功')));
        _loadAll();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  void _showJoinGroup(BuildContext context) {
    final groupIdController = TextEditingController();
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('加入群聊'),
        content: TextField(controller: groupIdController, decoration: const InputDecoration(labelText: '群组 ID', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final id = groupIdController.text;
              Navigator.pop(dlgCtx);
              await _joinGroup(id);
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinGroup(String groupId) async {
    try {
      final resp = await _im.joinGroup(groupId);
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('加入群聊成功')));
        _loadAll();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入失败: $e')));
    }
  }
}
