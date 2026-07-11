import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../ai_bubble.dart';
import '../api/ai_api.dart';
import '../api/im_api.dart';
import '../session.dart';
import '../util/notify_inbox.dart';
import '../util/message_cache.dart';
import '../util/text_reveal.dart';
import '../util/circle_conv.dart';
import 'ai_skill_chips.dart';
import 'user_skills_page.dart';
import 'chat_helpers.dart';
import '../api/upload_api.dart';
import 'file_message.dart';
import 'media_message.dart';
import 'media_bubble.dart';
import 'im_media.dart';
import '../util/video_viewer.dart';
import 'forward_target_sheet.dart';
import 'profile/payment/ai_subscription_pay_page.dart';
import '../util/media_url.dart';
import '../util/file_mime.dart';
import 'drive/drive_picker_sheet.dart';
import 'scene_banner.dart';

class AIChatPage extends StatefulWidget {
  /// ponytail: 防止通知/列表重复 push 同一会话导致 bootstrap 重启
  static String? activeConvId;

  final String token;
  final String userId;
  final String convId;
  final String title;
  final Stream<Map<String, dynamic>>? msgStream;
  final VoidCallback? onTitleChanged;
  final VoidCallback? onArchived;
  final String? initialUserSkillId;
  final String? initialMessage;
  const AIChatPage({
    super.key,
    required this.token,
    required this.userId,
    required this.convId,
    required this.title,
    this.msgStream,
    this.onTitleChanged,
    this.onArchived,
    this.initialUserSkillId,
    this.initialMessage,
  });

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  List<dynamic> _messages = [];
  int _lastReadMsgId = 0;
  int _readUpToId = 0;
  int _firstUnreadIndex = -1;
  bool _loading = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  String _convId = '';
  String _title = '';
  bool _aiPro = false;
  bool _enterToSend = true;
  bool _fromCache = false;
  bool _streaming = false;
  bool _waitingReply = false;
  final _reveal = TextReveal();
  AiSubscription? _aiSub;
  AiQuota? _quota;
  Timer? _quotaTick;
  StreamSubscription? _ws;
  late final AiApi _ai = AiApi(widget.token);
  late final ImApi _im = ImApi(widget.token);
  late final UploadApi _upload = UploadApi(widget.token);
  List<UserSkill> _userSkills = [];
  String? _activeUserSkillId;
  bool _uploadingMedia = false;
  int _pollGeneration = 0;
  String? _appliedFinalSig;
  Timer? _finalWsDebounce;
  Timer? _msgRefreshDebounce;
  bool _bootstrapped = false;
  String? _pendingUserContent;
  String? _pendingUserContentType;

  List<dynamic> get _effectiveMessages {
    if (_pendingUserContent == null) return _messages;
    if (aiLastUserContent(_messages) == _pendingUserContent) return _messages;
    return [
      ..._messages,
      {
        'role': 'user',
        'content': _pendingUserContent,
        'contentType': _pendingUserContentType ?? 'text',
      },
    ];
  }

  void _setMessages(List<dynamic> next) {
    _messages = next;
    if (_pendingUserContent != null && aiLastUserContent(next) == _pendingUserContent) {
      _pendingUserContent = null;
      _pendingUserContentType = null;
    }
  }

  List<dynamic> get _displayMessages => _collapseStaleProgress(_effectiveMessages);
  List<dynamic> get _visibleMessages => filterMessagesByQuery(_displayMessages, _searchQuery);

  String get _activeUserSkillName {
    if (_activeUserSkillId == null) return _title;
    for (final s in _userSkills) {
      if (s.skillId == _activeUserSkillId) return s.name;
    }
    return _title;
  }

  AiSkillMode get _skillMode =>
      _activeUserSkillId != null ? AiSkillMode.user : AiSkillMode.free;

  void _applySkillSelection(String? userSkillId) {
    setState(() => _activeUserSkillId = userSkillId);
  }

  void _showSkillPicker() {
    showAiSkillPickerSheet(
      context: context,
      mode: _skillMode,
      selectedUserSkillId: _activeUserSkillId,
      userSkills: _userSkills,
      onManageUserSkills: _openUserSkillsManager,
      onSelected: (userSkillId) {
        _applySkillSelection(userSkillId);
        if (!mounted) return;
        final msg = userSkillId == null || userSkillId.isEmpty
            ? '已切换为自由对话'
            : '已选专有 Skill：$_activeUserSkillName';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
        );
      },
    );
  }

  String get _composerHint =>
      _activeUserSkillId != null ? '问「$_activeUserSkillName」…' : '问助手…';

  void _openUserSkillsManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserSkillsPage(token: widget.token, userId: widget.userId, msgStream: widget.msgStream),
      ),
    ).then((_) => _loadUserSkills());
  }

  Map<String, dynamic> _parseSkillBody(String body) {
    final j = jsonDecode(body);
    if (j is! Map) return {};
    final m = Map<String, dynamic>.from(j);
    if (m['data'] is Map) return Map<String, dynamic>.from(m['data'] as Map);
    return m;
  }

  Future<void> _loadChatPrefs() async {
    final enter = await SessionStore.loadEnterToSend();
    if (mounted) setState(() => _enterToSend = enter);
  }

  @override
  void initState() {
    super.initState();
    _loadChatPrefs();
    _convId = widget.convId;
    _title = widget.title;
    _trackActiveConv();
    _activeUserSkillId = widget.initialUserSkillId;
    if (_convId.isNotEmpty) _bootstrapMessages();
    _loadUserSkills().then((_) async {
      if (!mounted) return;
      // ponytail: 新对话才应用用户设置的默认模式；已有会话保持自由对话
      if (widget.initialUserSkillId == null && _convId.isEmpty) {
        final defaultId = await SessionStore.loadDefaultAiUserSkillId();
        if (defaultId != null && _userSkills.any((s) => s.skillId == defaultId)) {
          setState(() => _activeUserSkillId = defaultId);
        }
      }
      final trial = widget.initialMessage?.trim();
      if (trial != null && trial.isNotEmpty && widget.initialUserSkillId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sendSkill(trial, userSkillId: widget.initialUserSkillId);
        });
      }
    });
    _ai.getSubscription().then((s) {
      if (mounted) setState(() {
        _aiPro = s.active;
        _aiSub = s;
      });
    }).catchError((_) {});
    _loadQuota();
    _quotaTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _quota != null) setState(() {});
    });
    _scrollController.addListener(_onScroll);
    _ws = widget.msgStream?.listen(_onAiWsMessage);
  }

  void _onAiWsMessage(Map<String, dynamic> m) {
    if ((m['type'] ?? '').toString() != 'ai') return;
    if (isCircleUtilityWs(Map<String, dynamic>.from(m))) return;
    final c = aiConvIdFromWs(Map<String, dynamic>.from(m));
    // ponytail: 新对话首次 WS 通知时 _convId 可能还是空，用 WS 的 convId 补上
    if (_convId.isEmpty && c.isNotEmpty && mounted) {
      _convId = c;
      _trackActiveConv();
    }
    if (!mounted || c.isEmpty || c != _convId) return;
    final content = (m['content'] ?? '').toString();
    if (isAgentProgressContent(content)) {
      if (_waitingReply && mounted && !_loading) setState(() => _loading = true);
      _scheduleMessagesRefresh();
      return;
    }
    // ponytail: 非过程 WS（含「正在处理中…」超时提示）不能停轮询；等 DB 里出现最终回复再结束
    _scheduleMessagesRefresh();
    _scheduleFinalReplyFetch();
  }

  void _scheduleFinalReplyFetch() {
    _finalWsDebounce?.cancel();
    _finalWsDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _fetchAndApplyFinalReply();
    });
  }

  bool _tailLooksAwaitingReply(List<dynamic> messages) {
    if (messages.isEmpty) return false;
    final m = messages.last;
    if (m is! Map) return false;
    final role = (m['role'] ?? '').toString();
    if (role == 'user') return true;
    if (role == 'assistant') {
      return isAgentProgressContent((m['content'] ?? '').toString());
    }
    return false;
  }

  void _scheduleMessagesRefresh() {
    if (!_waitingReply && !_loading && !_tailLooksAwaitingReply(_messages)) return;
    _msgRefreshDebounce?.cancel();
    _msgRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _syncMessagesWhileWaiting();
    });
  }

  Future<List<dynamic>?> _pullMessages({bool preferIncremental = true, bool forceFull = false}) async {
    if (_convId.isEmpty) return null;
    final since = (!forceFull && preferIncremental) ? _maxMessageId(_messages) : 0;
    final resp = await _ai.messages(_convId, since: since);
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    final list = (data['messages'] as List?) ?? [];
    if (since > 0) {
      if (list.isEmpty) return List<dynamic>.from(_effectiveMessages);
      final known = _messages.map(aiMessageId).toSet();
      final tail = <dynamic>[];
      for (final m in list) {
        final id = aiMessageId(m);
        if (id > since || (id > 0 && !known.contains(id))) tail.add(m);
      }
      if (tail.isEmpty) return List<dynamic>.from(_effectiveMessages);
      return mergeAiMessagesWithPending(_effectiveMessages, [..._messages, ...tail]);
    }
    return mergeAiMessagesWithPending(_effectiveMessages, list);
  }

  Future<void> _syncMessagesWhileWaiting() async {
    if (_convId.isEmpty || !mounted) return;
    try {
      final merged = await _pullMessages();
      if (merged == null || !mounted) return;
      final changed = merged.length != _messages.length ||
          !aiServerCaughtUpWithLocal(_effectiveMessages, merged) ||
          aiLastUserContent(_effectiveMessages) != aiLastUserContent(merged);
      if (changed) {
        setState(() => _setMessages(merged));
        if (_convId.isNotEmpty) MessageCache.mergeAi(MessageCache.aiKey(_convId), merged);
        if (_userNearBottom()) _scrollToBottom(force: true);
      }
      if (_findFinalAssistantReply(merged) != null) {
        _applyAssistantReplyOnce(merged);
        if (mounted) {
          setState(() {
            _loading = false;
            _waitingReply = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndApplyFinalReply() async {
    if (_convId.isEmpty || _streaming || !mounted) return;
    try {
      final merged = await _pullMessages();
      if (merged == null || !mounted) return;
      if (_findFinalAssistantReply(merged) == null) return;
      _applyAssistantReplyOnce(merged);
      if (mounted) {
        setState(() {
          _loading = false;
          _waitingReply = false;
        });
      }
    } catch (_) {}
  }

  void _trackActiveConv() {
    if (_convId.isNotEmpty) AIChatPage.activeConvId = _convId;
  }

  // ponytail: matches enterprise-gateway progressMsg stage names / progress bar
  bool _looksLikeAgentProgress(String content) => isAgentProgressContent(content);

  int _lastUserIndex(List<dynamic> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if ((messages[i]['role'] ?? '').toString() == 'user') return i;
    }
    return -1;
  }

  // 只认最后一轮用户消息之后的最终回复，避免新问题触发重播上一轮答案
  String? _findFinalAssistantReply(List<dynamic> messages) {
    final start = _lastUserIndex(messages);
    if (start < 0) return null;
    for (var i = messages.length - 1; i > start; i--) {
      final m = messages[i];
      if (m is! Map || (m['role'] ?? '').toString() != 'assistant') continue;
      final content = (m['content'] ?? '').toString();
      if (content.isEmpty || _looksLikeAgentProgress(content)) continue;
      return content;
    }
    return null;
  }

  String? _replySignature(List<dynamic> messages) {
    final start = _lastUserIndex(messages);
    if (start < 0) return null;
    for (var i = messages.length - 1; i > start; i--) {
      final m = messages[i];
      if (m is! Map || (m['role'] ?? '').toString() != 'assistant') continue;
      final content = (m['content'] ?? '').toString();
      if (content.isEmpty || _looksLikeAgentProgress(content)) continue;
      return '${_convId}|${_messageId(m)}|${content.length}|${content.hashCode}';
    }
    return null;
  }

  void _applyAssistantReplyOnce(List<dynamic> messages) {
    if (!aiServerCaughtUpWithLocal(_effectiveMessages, messages)) return;
    final sig = _replySignature(messages);
    if (sig == null || sig == _appliedFinalSig) return;
    _appliedFinalSig = sig;
    _applyAssistantReply(messages);
  }

  // 已完成轮次的过程反馈不再展示，只保留当前等待中的过程
  List<dynamic> _collapseStaleProgress(List<dynamic> messages) {
    final out = <dynamic>[];
    var i = 0;
    while (i < messages.length) {
      final m = messages[i];
      if (m is! Map ||
          (m['role'] ?? '').toString() != 'assistant' ||
          !_looksLikeAgentProgress((m['content'] ?? '').toString())) {
        out.add(m);
        i++;
        continue;
      }
      var j = i;
      while (j < messages.length) {
        final mj = messages[j];
        if (mj is! Map || (mj['role'] ?? '').toString() != 'assistant') break;
        if (!_looksLikeAgentProgress((mj['content'] ?? '').toString())) break;
        j++;
      }
      var hasFinalAfter = false;
      for (var k = j; k < messages.length; k++) {
        final mk = messages[k];
        if (mk is Map && (mk['role'] ?? '').toString() == 'user') break;
        if (mk is Map &&
            (mk['role'] ?? '').toString() == 'assistant' &&
            !_looksLikeAgentProgress((mk['content'] ?? '').toString())) {
          hasFinalAfter = true;
          break;
        }
      }
      if (!hasFinalAfter) {
        for (var k = i; k < j; k++) out.add(messages[k]);
      }
      i = j;
    }
    return out;
  }

  int _messageId(dynamic m) {
    if (m is! Map) return 0;
    final v = m['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _maxMessageId(List<dynamic> messages) {
    var max = 0;
    for (final m in messages) {
      final id = _messageId(m);
      if (id > max) max = id;
    }
    return max;
  }

  void _recomputeUnreadAnchor() {
    var hasId = false;
    for (final m in _visibleMessages) {
      if (_messageId(m) > 0) {
        hasId = true;
        break;
      }
    }
    if (!hasId) {
      _firstUnreadIndex = -1;
      return;
    }
    _firstUnreadIndex = -1;
    for (var i = 0; i < _visibleMessages.length; i++) {
      if (_messageId(_visibleMessages[i]) > _lastReadMsgId) {
        _firstUnreadIndex = i;
        return;
      }
    }
  }

  GlobalKey _keyForIndex(int i) => _itemKeys.putIfAbsent(i, () => GlobalKey());

  void _clearItemKeys() => _itemKeys.clear();

  bool _userNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 200;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _convId.isEmpty) return;
    if (_userNearBottom()) _markReadThrough(_maxMessageId(_messages));
  }

  Future<void> _initReadCursor() async {
    if (_convId.isEmpty) return;
    _lastReadMsgId = await SessionStore.loadAiLastReadMsgId(_convId);
    _readUpToId = _lastReadMsgId;
    _recomputeUnreadAnchor();
  }

  Future<void> _markReadThrough(int msgId) async {
    if (_convId.isEmpty || msgId <= 0 || msgId <= _readUpToId) return;
    _readUpToId = msgId;
    _lastReadMsgId = msgId;
    _recomputeUnreadAnchor();
    await SessionStore.saveAiLastReadMsgId(_convId, msgId);
    NotifyInbox.markAiConvRead(token: widget.token, convId: _convId);
  }

  void _persistReadProgress() {
    if (_convId.isEmpty || _readUpToId <= 0) return;
    SessionStore.saveAiLastReadMsgId(_convId, _readUpToId);
  }

  void _scrollToBottom({bool force = false, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (attempt < 8) _scrollToBottom(force: force, attempt: attempt + 1);
        return;
      }
      if (!force && !_userNearBottom()) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) {
        _scrollController.jumpTo(max);
        return;
      }
      if (attempt < 8) _scrollToBottom(force: force, attempt: attempt + 1);
    });
  }

  void _restoreScroll(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(offset.clamp(0.0, _scrollController.position.maxScrollExtent));
    });
  }

  void _applyScrollAnchor({double? preserveOffset}) {
    if (_searchQuery.isNotEmpty) return;
    if (preserveOffset != null) {
      _restoreScroll(preserveOffset);
      return;
    }
    _scrollToBottom(force: true);
  }

  Future<void> _afterMessagesUpdated({bool preserveScroll = false, double? scrollOffset}) async {
    if (!mounted) return;
    _recomputeUnreadAnchor();
    _applyScrollAnchor(preserveOffset: preserveScroll ? scrollOffset : null);
  }

  @override
  void dispose() {
    if (AIChatPage.activeConvId == _convId) AIChatPage.activeConvId = null;
    _persistReadProgress();
    _reveal.dispose();
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _quotaTick?.cancel();
    _finalWsDebounce?.cancel();
    _msgRefreshDebounce?.cancel();
    _ws?.cancel();
    super.dispose();
  }

  Future<void> _loadUserSkills() async {
    try {
      final list = await _ai.fetchUserSkills();
      if (mounted) setState(() => _userSkills = list);
    } catch (_) {}
  }

  Future<void> _loadQuota() async {
    try {
      final q = await _ai.getQuota();
      if (mounted) setState(() => _quota = q);
    } catch (_) {}
  }

  Future<void> _openSubscribe() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiSubscriptionPayPage(
          token: widget.token,
          userId: widget.userId,
          current: _aiSub,
        ),
      ),
    );
    _loadQuota();
    _ai.getSubscription().then((s) {
      if (mounted) setState(() {
        _aiPro = s.active;
        _aiSub = s;
      });
    }).catchError((_) {});
  }

  void _showQuotaExceeded() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('今日 AI 配额已用完'),
        content: Text(
          _quota?.isPro == true
              ? 'Pro 用户每日 ${_quota?.limit ?? 200} 次 AI 调用已达上限，明日 0 点重置。'
              : '免费用户每日 ${_quota?.limit ?? 10} 次 AI 调用（对话+技能）。开通 AI Pro 可提升至 200 次/日。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
          if (_quota?.isPro != true)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _openSubscribe();
              },
              child: const Text('立即开通'),
            )
          else if (_aiSub?.expiringSoon == true)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _openSubscribe();
              },
              child: const Text('立即续订'),
            ),
        ],
      ),
    );
  }

  Future<void> _bootstrapMessages() async {
    if (_convId.isEmpty || _bootstrapped) return;
    _bootstrapped = true;
    await _initReadCursor();
    final cached = await MessageCache.load(MessageCache.aiKey(_convId));
    if (cached.isNotEmpty && mounted) {
      _clearItemKeys();
      setState(() {
        _messages = cached;
        _loading = false;
      });
    }
    await _syncMessagesFromServer(preserveScroll: false, forceFull: true);
    if (mounted) {
      _scrollToBottom(force: true);
      _markReadThrough(_maxMessageId(_messages));
      _finalizeReplyState(_messages);
    }
  }

  void _streamAssistantAt(int index, String full) {
    if (full.isEmpty || index < 0 || index >= _messages.length) return;
    // ponytail: Web/Safari 上打字机每 18ms setState 会抢焦点，输入框无法打字
    if (kIsWeb) {
      setState(() {
        final m = Map<String, dynamic>.from(_messages[index] as Map);
        m['content'] = full;
        _messages[index] = m;
        _streaming = false;
        _loading = false;
        _waitingReply = false;
      });
      if (_convId.isNotEmpty) MessageCache.mergeAi(MessageCache.aiKey(_convId), _messages);
      _scrollToBottom(force: true);
      return;
    }
    setState(() => _streaming = true);
    _reveal.reveal(
      full: full,
      onUpdate: (partial) {
        if (!mounted) return;
        final m = Map<String, dynamic>.from(_messages[index] as Map);
        m['content'] = partial;
        setState(() => _messages[index] = m);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _streaming = false);
        if (_convId.isNotEmpty) MessageCache.mergeAi(MessageCache.aiKey(_convId), _messages);
      },
    );
  }

  void _applyAssistantReply(List<dynamic> messages) {
    final list = List<dynamic>.from(messages);
    var streamIdx = -1;
    var full = '';
    var targetId = 0;
    final start = _lastUserIndex(list);
    for (var i = list.length - 1; i > start; i--) {
      if ((list[i]['role'] ?? '').toString() != 'assistant') continue;
      full = (list[i]['content'] ?? '').toString();
      if (full.isNotEmpty && !_looksLikeAgentProgress(full)) {
        streamIdx = i;
        targetId = _messageId(list[i]);
        break;
      }
    }
    if (streamIdx >= 0) {
      final cur = streamIdx < _messages.length ? (_messages[streamIdx]['content'] ?? '').toString() : '';
      if (cur == full && !_streaming) {
        setState(() {
          _setMessages(mergeAiMessagesWithPending(_effectiveMessages, list));
          _loading = false;
          _waitingReply = false;
        });
        if (_convId.isNotEmpty) MessageCache.mergeAi(MessageCache.aiKey(_convId), _messages);
        return;
      }
      list[streamIdx] = {...Map<String, dynamic>.from(list[streamIdx] as Map), 'content': ''};
    }
    _clearItemKeys();
    final merged = mergeAiMessagesWithPending(_effectiveMessages, list);
    setState(() => _setMessages(merged));
    if (streamIdx >= 0) {
      var idx = streamIdx;
      if (targetId > 0) {
        final byId = merged.indexWhere((m) => _messageId(m) == targetId);
        if (byId >= 0) idx = byId;
      }
      _streamAssistantAt(idx, full);
    } else if (_convId.isNotEmpty) {
      MessageCache.mergeAi(MessageCache.aiKey(_convId), merged);
    }
    if (_userNearBottom() || _firstUnreadIndex < 0) {
      _scrollToBottom(force: true);
    }
  }

  void _finalizeReplyState(List<dynamic> messages) {
    if (_findFinalAssistantReply(messages) != null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _waitingReply = false;
        });
      }
      return;
    }
    if (_tailLooksAwaitingReply(messages) && mounted && !_waitingReply) {
      setState(() => _waitingReply = true);
      _startReplyWatch();
    }
  }

  Future<void> _loadMessages({bool preserveScroll = false, bool forceFull = false}) async {
    await _syncMessagesFromServer(preserveScroll: preserveScroll, forceFull: forceFull);
  }

  Future<void> _syncMessagesFromServer({bool preserveScroll = false, bool forceFull = false}) async {
    if (_convId.isEmpty || _streaming) return;
    final offset = preserveScroll && _scrollController.hasClients ? _scrollController.offset : null;
    try {
      final merged = await _pullMessages(
        preferIncremental: _maxMessageId(_messages) > 0,
        forceFull: forceFull,
      );
      if (merged == null || !mounted) return;
      final oldMax = _maxMessageId(_messages);
      final newMax = _maxMessageId(merged);
      if (_pendingUserContent == null && newMax <= oldMax && merged.length == _messages.length) {
        _finalizeReplyState(merged);
        return;
      }

      final appendOnly = !forceFull && newMax > oldMax && merged.length > _messages.length;
      if (appendOnly) {
        final tail = merged.sublist(_messages.length);
        setState(() {
          _setMessages([..._messages, ...tail]);
          _fromCache = false;
        });
      } else {
        if (newMax != oldMax || merged.length != _messages.length) {
          _clearItemKeys();
        }
        setState(() {
          _setMessages(merged);
          _fromCache = false;
        });
      }
      await MessageCache.mergeAi(MessageCache.aiKey(_convId), _messages);
      final gotNew = newMax > oldMax;
      if (preserveScroll && offset != null && !gotNew) {
        _recomputeUnreadAnchor();
        _restoreScroll(offset);
      } else {
        await _afterMessagesUpdated(preserveScroll: false, scrollOffset: null);
        if (gotNew) _scrollToBottom(force: true);
      }
      final finalReply = _findFinalAssistantReply(_messages);
      if (finalReply != null) {
        _applyAssistantReplyOnce(_messages);
      }
      _finalizeReplyState(_messages);
    } catch (_) {
      if (mounted && _messages.isNotEmpty) setState(() => _fromCache = true);
    }
  }

  Future<void> _startReplyWatch() async {
    final gen = _pollGeneration;
    // ponytail: progress WS 是空包，必须轮询 DB 拉过程反馈和最终回复
    for (var i = 0; i < 40; i++) {
      await Future.delayed(Duration(seconds: widget.msgStream != null ? 3 : 2));
      if (!mounted || !_waitingReply || gen != _pollGeneration) return;
      await _syncMessagesWhileWaiting();
      if (!_waitingReply) return;
    }
    if (mounted && _waitingReply) {
      setState(() {
        _loading = false;
        _waitingReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 回复较慢，请点右上角刷新或稍后再看')),
      );
    }
  }

  Future<void> _sendSkill(String message, {String? userSkillId, String contentType = 'text'}) async {
    if (message.trim().isEmpty) return;
    if (_quota?.exhausted == true) {
      _showQuotaExceeded();
      return;
    }
    var usk = userSkillId ?? _activeUserSkillId;
    if (usk == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点输入框左侧图标选择专有 Skill')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _waitingReply = false;
    });
    _appliedFinalSig = null;
    setState(() => _messages.add({'role': 'user', 'content': message, 'contentType': contentType}));
    _scrollToBottom(force: true);
    try {
      final resp = await _ai.sendSkill(
        message: message,
        contentType: contentType,
        userSkillId: usk,
        sessionKey: _convId.isNotEmpty ? _convId : null,
      );
      if (resp.statusCode == 200 && mounted) {
        final data = _parseSkillBody(resp.body);
        final conv = (data['convId'] ?? '').toString();
        if (conv.isNotEmpty) {
          _convId = conv;
          _trackActiveConv();
          if (_title == '新对话' && usk != null) _title = _activeUserSkillName;
        }
        if (usk != null && _activeUserSkillId == null) {
          _activeUserSkillId = usk;
        }
        final reply = (data['content'] ?? data['reply'] ?? '').toString();
        final skill = (data['skillUsed'] ?? data['skill_used'] ?? '').toString();
        if (reply.isEmpty) {
          if (conv.isNotEmpty) {
            if (mounted) {
              setState(() {
                _loading = false;
                _waitingReply = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已提交，AI 正在思考（约 10～30 秒）…'), duration: Duration(seconds: 2)),
              );
            }
            await _startReplyWatch();
            _loadQuota();
            return;
          }
          setState(() {
            if (_messages.isNotEmpty) _messages.removeLast();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('技能未返回内容，请重试或改用「新对话」')),
          );
          return;
        }
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': '',
            'contentType': hasMarkdown(reply) ? 'markdown' : 'text',
            'skillUsed': skill,
          });
        });
        _streamAssistantAt(_messages.length - 1, reply);
        if (skill.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('技能: $skill'), duration: const Duration(seconds: 1)),
          );
        }
        _loadQuota();
        _scrollToBottom(force: true);
      } else if (resp.statusCode == 429 && mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
          try {
            _quota = AiQuota.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
          } catch (_) {}
        });
        _showQuotaExceeded();
      } else if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('技能调用失败: ${resp.body}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('技能调用失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pollForAssistant({int attempts = 20}) async {
    if (_convId.isEmpty) return;
    final gen = ++_pollGeneration;
    if (mounted) setState(() => _waitingReply = true);
    var lastMaxId = _maxMessageId(_messages);
    for (var i = 0; i < attempts; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _convId.isEmpty || gen != _pollGeneration) return;
      try {
        final resp = await _ai.messages(_convId);
        if (resp.statusCode != 200 || !mounted || gen != _pollGeneration) continue;
        final data = jsonDecode(resp.body);
        final list = (data['messages'] as List?) ?? [];
        final maxId = _maxMessageId(list);
        if (maxId > lastMaxId) lastMaxId = maxId;
        final finalReply = _findFinalAssistantReply(list);
        if (finalReply != null && !_streaming) {
          _applyAssistantReplyOnce(list);
          if (mounted) {
            setState(() {
              _loading = false;
              _waitingReply = false;
            });
          }
          return;
        }
        // ponytail: DB 里的过程反馈行不替换整表，避免 2s 轮询闪屏
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _waitingReply = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 回复较慢：请确认已选专有 Skill，或点右上角刷新；仍无回复请联系管理员查 enterprise 日志')),
      );
    }
  }

  Future<void> _sendWithContent(String content, {String contentType = 'text'}) async {
    if (content.trim().isEmpty) return;
    if (_quota?.exhausted == true) {
      _showQuotaExceeded();
      return;
    }
    if (_activeUserSkillId != null) {
      await _sendSkill(content, userSkillId: _activeUserSkillId, contentType: contentType);
      return;
    }

    setState(() => _loading = true);
    _appliedFinalSig = null;
    _pendingUserContent = content;
    _pendingUserContentType = contentType;
    setState(() {
      _messages.add({'role': 'user', 'content': content, 'contentType': contentType});
      _waitingReply = true;
    });
    _scrollToBottom(force: true);

    try {
      final resp = await _ai.send(convId: _convId, content: content, contentType: contentType);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['convId'] != null && (data['convId'] as String).isNotEmpty) {
          _convId = data['convId'];
          _trackActiveConv();
        }
        if (data['messages'] != null) {
          final list = List<dynamic>.from(data['messages']);
          if (list.isNotEmpty) {
            final merged = mergeAiMessagesWithPending(_effectiveMessages, list);
            final oldMax = _maxMessageId(_messages);
            final newMax = _maxMessageId(merged);
            if (newMax > oldMax || merged.length != _messages.length || _pendingUserContent != null) {
              if (!(newMax > oldMax && merged.length > _messages.length)) {
                _clearItemKeys();
              }
              setState(() {
                _setMessages(merged);
                _waitingReply = true;
              });
            } else {
              setState(() => _waitingReply = true);
            }
          } else {
            setState(() => _waitingReply = true);
          }
          if (_convId.isNotEmpty) MessageCache.mergeAi(MessageCache.aiKey(_convId), _messages);
          if (mounted) {
            _scheduleMessagesRefresh();
            _startReplyWatch();
          }
        }
        _loadQuota();
        if (_userNearBottom()) _scrollToBottom(force: true);
      } else if (resp.statusCode == 429 && mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
          _pendingUserContent = null;
          _pendingUserContentType = null;
          _waitingReply = false;
          try {
            _quota = AiQuota.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
          } catch (_) {}
        });
        _showQuotaExceeded();
      } else if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
          _pendingUserContent = null;
          _pendingUserContentType = null;
          _waitingReply = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: ${resp.body}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty) _messages.removeLast();
          _pendingUserContent = null;
          _pendingUserContentType = null;
          _waitingReply = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_uploadingMedia || _loading) return;
    final picked = await pickImageBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    try {
      final url = await _upload.uploadImageBytes(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      await _sendWithContent(url, contentType: 'image');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_uploadingMedia || _loading) return;
    final picked = await pickFileBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    try {
      final url = await _upload.uploadFileBytes(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      final name = picked.name ?? '文件';
      if (isImageFilename(name)) {
        await _sendWithContent(url, contentType: 'image');
      } else {
        final payload = encodeFileMessage(url: url, name: name, size: picked.bytes.length);
        await _sendWithContent(payload, contentType: 'file');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _pickAndSendVideo() async {
    if (_uploadingMedia || _loading) return;
    final picked = await pickVideoBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    try {
      final uploaded = await _upload.uploadVideoWithPoster(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      final payload = encodeMediaMessage(url: uploaded.url, name: picked.name, poster: uploaded.poster);
      await _sendWithContent(payload, contentType: 'video');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _pickFromDrive() async {
    if (_uploadingMedia || _loading) return;
    final node = await showDrivePickerSheet(context, token: widget.token, userId: widget.userId);
    if (node == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    try {
      final url = publicMediaUrl(node.downloadUrl ?? '');
      final mime = node.mimeType ?? '';
      if (isImageFilename(node.name) || mime.startsWith('image/')) {
        await _sendWithContent(url, contentType: 'image');
      } else if (isVideoFilename(node.name) || mime.startsWith('video/')) {
        final payload = encodeMediaMessage(url: url, name: node.name, size: node.sizeBytes);
        await _sendWithContent(payload, contentType: 'video');
      } else {
        await _sendWithContent(encodeDriveFileMessage(node), contentType: 'file');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('云盘发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _sendMessage({String? preset}) async {
    final content = (preset ?? _msgController.text).trim();
    if (content.isEmpty) return;
    if (_quota?.exhausted == true) {
      _showQuotaExceeded();
      return;
    }

    if (_activeUserSkillId != null) {
      await _sendSkill(content, userSkillId: _activeUserSkillId);
      if (preset == null) _msgController.clear();
      return;
    }

    if (preset == null) _msgController.clear();
    await _sendWithContent(content);
  }

  Future<void> _forwardToIm(String content) async {
    final target = await pickForwardTarget(context, _im);
    if (target == null || !mounted) return;
    try {
      final resp = target.kind == 'group'
          ? await _im.send(groupId: target.id, content: content)
          : await _im.send(toUserId: target.id, content: content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.statusCode == 200 ? '已转发' : '转发失败: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('转发失败: $e')));
    }
  }

  Future<void> _archiveConversation() async {
    if (_convId.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档对话'),
        content: Text('将「${_title.isEmpty ? '此对话' : _title}」移入已归档？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('归档')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final resp = await _ai.setStatus(_convId, 'archived');
      if (resp.statusCode == 200 && mounted) {
        widget.onArchived?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已归档'), duration: Duration(seconds: 1)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('归档失败: $e')));
    }
  }

  Future<void> _renameTitle() async {
    if (_convId.isEmpty) return;
    final controller = TextEditingController(text: _title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || !mounted) return;
    try {
      final resp = await _ai.updateTitle(_convId, newTitle);
      if (resp.statusCode == 200 && mounted) {
        setState(() => _title = newTitle);
        widget.onTitleChanged?.call();
      }
    } catch (_) {}
  }

  Widget _unreadDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.blue.shade200)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('以下为新消息', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
          ),
          Expanded(child: Divider(color: Colors.blue.shade200)),
        ],
      ),
    );
  }

  Widget _messageListItem(int i) {
    final showUnread = _searchQuery.isEmpty && i == _firstUnreadIndex && _firstUnreadIndex >= 0;
    return KeyedSubtree(
      key: _keyForIndex(i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showUnread) _unreadDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _messageTile(_visibleMessages[i]),
          ),
        ],
      ),
    );
  }

  Widget _messageTile(dynamic m) {
    final isUser = m['role'] == 'user';
    final con = (m['content'] ?? '').toString();
    final ct = (m['contentType'] ?? 'text').toString();
    final imageUrl = imageUrlFromMessage(m);
    if (imageUrl != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: AiBubble(
            isUser: isUser,
            isMarkdown: false,
            content: imageUrl,
            contentType: 'image',
            createdAt: (m['createdAt'] ?? m['created_at'])?.toString(),
            context: context,
          ),
        ),
      );
    }
    final video = tryParseVideoMessage(con, contentType: ct);
    if (video != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: VideoMessageBubble(
            media: video,
            isMe: isUser,
            onTap: video.url.isNotEmpty
                ? () async {
                    try {
                      await showVideoViewer(context, video.url, name: video.name ?? 'video.mp4');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法播放视频: $e')));
                      }
                    }
                  }
                : null,
          ),
        ),
      );
    }
    final file = tryParseFileMessage(con, contentType: ct);
    if (file != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: FileMessageBubble(
            file: file,
            isMe: isUser,
            onTap: file.url.isNotEmpty
                ? () async {
                    try {
                      await openFileUrl(file.url, name: file.name);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开文件: $e')));
                      }
                    }
                  }
                : null,
          ),
        ),
      );
    }
    final md = shouldRenderMarkdown(con, contentType: ct, isUser: isUser);
    final ts = (m['createdAt'] ?? m['created_at'])?.toString();
    final skillUsed = (m['skillUsed'] ?? m['skill_used'])?.toString();
    final bubble = AiBubble(
      isUser: isUser,
      isMarkdown: md,
      content: con,
      contentType: ct,
      createdAt: ts,
      skillUsed: skillUsed,
      context: context,
    );
    if (isUser || con.isEmpty) return bubble;
    return GestureDetector(
      onLongPress: () => showMessageActionSheet(context, content: con, onForward: () => _forwardToIm(con)),
      child: bubble,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜索对话…', border: InputBorder.none, isDense: true),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(_title, overflow: TextOverflow.ellipsis)),
                  if (_aiPro) ...[
                    const SizedBox(width: 6),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Pro', style: TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
              ),
        actions: [
          if (_searchVisible)
            IconButton(
              tooltip: '关闭搜索',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _searchVisible = false;
                _searchQuery = '';
                _searchController.clear();
              }),
            )
          else
            toolbarPlusButton(
              context,
              onPressed: () => showChatComposerMoreSheet(context, actions: [
                if (_convId.isNotEmpty)
                  ChatComposerAction(
                    id: 'archive',
                    icon: Icons.archive_outlined,
                    label: '归档',
                    onTap: _archiveConversation,
                  ),
                if (_convId.isNotEmpty)
                  ChatComposerAction(
                    id: 'rename',
                    icon: Icons.edit_outlined,
                    label: '重命名',
                    onTap: _renameTitle,
                  ),
                ChatComposerAction(
                  id: 'refresh',
                  icon: Icons.refresh,
                  label: '刷新',
                  onTap: () => _loadMessages(forceFull: true),
                ),
                ChatComposerAction(
                  id: 'search',
                  icon: Icons.search,
                  label: '搜索',
                  onTap: () => setState(() => _searchVisible = true),
                ),
              ]),
            ),
        ],
      ),
      body: Column(
        children: [
          const SceneBanner(text: '此处为私人助手，消息不会出现在 IM 群聊中。'),
          if (_fromCache)
            Material(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 14, color: Colors.orange.shade800),
                    const SizedBox(width: 6),
                    Expanded(child: Text('离线缓存', style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
                    TextButton(onPressed: () => _loadMessages(forceFull: true), child: const Text('刷新')),
                  ],
                ),
              ),
            ),
          if (_searchQuery.isNotEmpty)
            Material(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('找到 ${_visibleMessages.length} 条匹配', style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadMessages(forceFull: true),
              child: _visibleMessages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scrollController,
                      children: [
                        SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                        Center(
                          child: Text(
                            _searchQuery.isEmpty ? '开始和 AI 对话吧' : '无匹配消息',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _visibleMessages.length,
                      itemBuilder: (_, i) => _messageListItem(i),
                    ),
            ),
          ),
          if (_loading && !_streaming) const LinearProgressIndicator(minHeight: 2),
          if (_waitingReply && !_streaming)
            Material(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade700)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('AI 正在回复…', style: TextStyle(fontSize: 13, color: Colors.blue.shade900))),
                  ],
                ),
              ),
            ),
          if (_streaming)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('正在输出…', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
            ),
          if (_searchQuery.isEmpty && _quota != null)
            Material(
              color: _quota!.exhausted ? Colors.orange.shade50 : Colors.grey.shade100,
              child: InkWell(
                onTap: () {
                  if (_quota!.exhausted && !_quota!.isPro) {
                    _openSubscribe();
                  } else if (_aiSub?.expiringSoon == true) {
                    _openSubscribe();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 16, color: _quota!.exhausted ? Colors.orange : Colors.deepPurple),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            '今日 AI ${_quota!.used}/${_quota!.limit}${_quota!.isPro ? ' · Pro' : ''}',
                            if (_quota!.resetCountdown().isNotEmpty) _quota!.resetCountdown(),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                      ),
                      if (_quota!.exhausted && !_quota!.isPro)
                        FilledButton.tonal(
                          onPressed: _openSubscribe,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 28),
                          ),
                          child: const Text('开通 Pro', style: TextStyle(fontSize: 12)),
                        )
                      else if (_aiSub?.expiringSoon == true)
                        TextButton(
                          onPressed: _openSubscribe,
                          child: const Text('续订', style: TextStyle(fontSize: 12)),
                        )
                      else if (!_quota!.isPro)
                        Text('升级', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
              ),
            ),
          chatComposer(
            context: context,
            controller: _msgController,
            onSend: () => _sendMessage(),
            hint: _composerHint,
            enterToSend: _enterToSend,
            moreActions: _searchQuery.isEmpty
                ? [
                    ChatComposerAction(
                      id: 'image',
                      icon: Icons.image_outlined,
                      label: '图片',
                      onTap: (_loading || _uploadingMedia) ? () {} : _pickAndSendImage,
                    ),
                    ChatComposerAction(
                      id: 'file',
                      icon: Icons.attach_file,
                      label: '文件',
                      onTap: (_loading || _uploadingMedia) ? () {} : _pickAndSendFile,
                    ),
                    ChatComposerAction(
                      id: 'video',
                      icon: Icons.videocam_outlined,
                      label: '视频',
                      onTap: (_loading || _uploadingMedia) ? () {} : _pickAndSendVideo,
                    ),
                    ChatComposerAction(
                      id: 'drive',
                      icon: Icons.cloud_outlined,
                      label: '云盘',
                      onTap: (_loading || _uploadingMedia) ? () {} : _pickFromDrive,
                    ),
                    ChatComposerAction(
                      id: 'skill',
                      icon: _skillMode == AiSkillMode.user ? Icons.person_pin : Icons.auto_awesome_outlined,
                      label: _skillMode == AiSkillMode.user
                          ? (_activeUserSkillName ?? '专有Skill')
                          : 'Skill',
                      onTap: _showSkillPicker,
                    ),
                  ]
                : null,
          ),
        ],
      ),
    );
  }
}
