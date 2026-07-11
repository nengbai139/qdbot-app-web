import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../ai_bubble.dart';
import '../api/im_api.dart';
import '../api/upload_api.dart';
import '../session.dart';
import '../call/call_service.dart';
import '../call/call_signal.dart';
import '../util/audio_playback.dart';
import '../util/message_cache.dart';
import 'drive/drive_picker_sheet.dart';
import 'chat_helpers.dart';
import 'file_message.dart';
import 'media_bubble.dart';
import 'media_message.dart';
import 'im_media.dart';
import '../util/video_viewer.dart';
import 'voice_record_sheet.dart';
import 'circle/circle_navigation.dart';
import 'circle/meeting_deep_link.dart';
import 'circle/meeting_invite_card.dart';
import 'premium/contact_card.dart';
import 'premium/share_contact_sheet.dart';
import 'premium/user_code_display.dart';
import 'premium/user_profile_sheet.dart';

class ChatPage extends StatefulWidget {
  final String token;
  final String userId;
  final String peerId;
  final String peerName;
  final String peerUserCode;
  final String peerLevelName;
  final String userCode;
  final Stream<Map<String, dynamic>>? msgStream;

  const ChatPage({
    super.key,
    required this.token,
    required this.userId,
    required this.peerId,
    required this.peerName,
    this.peerUserCode = '',
    this.peerLevelName = '',
    this.userCode = '',
    this.msgStream,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _searchVisible = false;
  bool _mentionFilter = false;
  String _searchQuery = '';
  bool _uploadingImage = false;
  bool _uploadingFile = false;
  bool _uploadingVoice = false;
  bool _uploadingVideo = false;
  bool _enterToSend = true;
  bool _showReadBadge = true;
  bool _fromCache = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _pageSize = 50;
  Set<String> _myMentionNames = {};
  Map<String, dynamic>? _replyTo;
  StreamSubscription? _wsSub;
  Timer? _twinPollTimer;
  late final ImApi _im = ImApi(widget.token);
  late final UploadApi _upload = UploadApi(widget.token);

  void _cancelReply() => setState(() => _replyTo = null);
  void _startReply(Map<String, dynamic> msg) => setState(() => _replyTo = msg);

  bool _isMe(dynamic m) {
    final from = (m['fromUserId'] ?? '').toString();
    return from == widget.userId || from == 'me';
  }

  List<dynamic> get _visibleMessages {
    var list = filterMessagesByQuery(_messages, _searchQuery).where((m) => !isHiddenImMessage(m)).toList();
    if (_mentionFilter) list = list.where((m) => (m['mentioned'] ?? false) == true).toList();
    return list;
  }
  List<Object> get _listItems => buildMessageListWithDates(_visibleMessages);

  bool _msgMentionsMe(String content) => lastMsgMentionsMe(content, _myMentionNames);

  Future<void> _loadChatPrefs() async {
    final enter = await SessionStore.loadEnterToSend();
    final read = await SessionStore.loadShowReadBadge();
    if (mounted) setState(() {
      _enterToSend = enter;
      _showReadBadge = read;
    });
  }

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

  void _annotateMentions(List<dynamic> msgs) {
    for (final m in msgs) {
      if (m is Map) {
        final c = (m['content'] ?? '').toString();
        m['mentioned'] = _msgMentionsMe(c);
      }
    }
  }

  Future<void> _revokeMessage(String msgId) async {
    try {
      final resp = await _im.revokeMessage(msgId);
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => (m['msgId'] ?? '') == msgId);
          if (idx >= 0) {
            _messages[idx]['content'] = '[消息已撤回]';
            _messages[idx]['contentType'] = 'revoked';
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('撤回失败: ${resp.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Widget _messageBubble(dynamic m, bool isMe, String c, String ct, bool revoked, bool md, String? ts, bool mentioned) {
    final invite = !revoked ? tryParseMeetingInvite(c, contentType: ct) : null;
    if (invite != null) {
      return MeetingInviteBubble(
        invite: invite,
        isMe: isMe,
        onJoin: () => openCircleRoomById(
          context,
          token: widget.token,
          userId: widget.userId,
          roomId: invite.roomId,
          joinPasscode: invite.passcode ?? '',
        ),
      );
    }
    final card = !revoked ? tryParseContactCard(c, contentType: ct) : null;
    if (card != null) {
      return ContactCardBubble(
        card: card,
        isMe: isMe,
        onTap: () => openContactCard(
          context,
          card: card,
          token: widget.token,
          myUserId: widget.userId,
          onOpenChat: card.userId.isNotEmpty && card.userId != widget.userId
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        token: widget.token,
                        userId: widget.userId,
                        peerId: card.userId,
                        peerName: card.displayName,
                        peerUserCode: card.userCode,
                        peerLevelName: card.levelName,
                        userCode: widget.userCode,
                      ),
                    ),
                  )
              : null,
        ),
      );
    }
    final voice = !revoked ? tryParseMediaMessage(c, contentType: ct, kinds: {'voice', 'audio'}) : null;
    if (voice != null) {
      return VoiceMessageBubble(media: voice, isMe: isMe, token: widget.token);
    }
    final video = !revoked ? tryParseVideoMessage(c, contentType: ct) : null;
    if (video != null) {
      return GestureDetector(
        onLongPress: video.url.isNotEmpty
            ? () => showVideoActionSheet(context, url: video.url, name: video.name ?? 'video.mp4')
            : null,
        child: VideoMessageBubble(
          media: video,
          isMe: isMe,
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
      );
    }
    final file = !revoked ? tryParseFileMessage(c, contentType: ct) : null;
    if (file != null) {
      return FileMessageBubble(
        file: file,
        isMe: isMe,
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
      );
    }
    final useMentions = (ct == 'text' || ct.isEmpty) && !md && !revoked;
    return AiBubble(
      isUser: isMe,
      isMarkdown: md,
      isBot: ct == 'bot_reply',
      content: c,
      contentType: ct,
      createdAt: ts,
      context: context,
      mentionMeNames: useMentions ? _myMentionNames : null,
    );
  }

  Widget _messageTile(dynamic m) {
    final isMe = _isMe(m);
    final c = m['content'] ?? '';
    final ct = (m['contentType'] ?? 'text').toString();
    final revoked = ct == 'revoked';
    final failed = m['status'] == 'failed';
    final md = shouldRenderMarkdown(c.toString(), contentType: ct, isUser: isMe);
    final ts = (m['createdAt'] ?? m['created_at'])?.toString();
    final mentioned = (m['mentioned'] ?? false) == true;
    final peerInitial = widget.peerName.isNotEmpty ? widget.peerName[0] : '?';
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: revoked
              ? null
              : () => showMessageActionSheet(
                    context,
                    content: c.toString(),
                    onReply: () => _startReply(Map<String, dynamic>.from(m as Map)),
                    onRevoke: isMe ? () => _revokeMessage((m['msgId'] ?? '').toString()) : null,
                  ),
          child: ImMessageRow(
            isMe: isMe,
            avatarLabel: isMe ? '我' : peerInitial,
            mentioned: mentioned,
            bubble: _messageBubble(m, isMe, c.toString(), ct, revoked, md, ts, mentioned),
          ),
        ),
        if (failed)
          Padding(
            padding: EdgeInsets.only(right: isMe ? 58 : 12, bottom: 4),
            child: TextButton.icon(
              onPressed: () => _sendMessage(retryContent: c.toString(), retryTempId: m['msgId'], contentType: ct),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('发送失败，点此重试', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700, visualDensity: VisualDensity.compact),
            ),
          ),
        messageReadBadge(m, isMe: isMe, enabled: _showReadBadge),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    CallCoordinator.instance.registerChatPeer(widget.peerId, widget.peerName);
    _loadChatPrefs();
    _loadMentionNames();
    _bootstrapMessages();
    _scrollController.addListener(_onScroll);
    _wsSub = widget.msgStream?.listen((m) {
      if (!mounted) return;
      final type = (m['type'] as String? ?? '').toString();
      if (type == 'im_revoke') {
        final gid = (m['groupId'] ?? '').toString();
        if (gid.isNotEmpty) return;
        final revokeMsgId = (m['msgId'] ?? '').toString();
        setState(() {
          final idx = _messages.indexWhere((msg) => (msg['msgId'] ?? '') == revokeMsgId);
          if (idx >= 0) {
            _messages[idx]['content'] = '[消息已撤回]';
            _messages[idx]['contentType'] = 'revoked';
          }
        });
        return;
      }
      if (type != 'im') return;
      final fromId = (m['fromUserId'] ?? m['ext']?['fromUserId'] ?? '').toString();
      final toId = (m['toUserId'] ?? m['ext']?['toUserId'] ?? '').toString();
      final gid = (m['groupId'] ?? m['ext']?['groupId'] ?? '').toString();
      if (gid.isNotEmpty) return;
      if (fromId != widget.peerId && fromId != widget.userId) return;
      if (fromId == widget.userId) return;
      if (toId.isNotEmpty && toId != widget.userId && fromId != widget.peerId) return;
      setState(() {
        final c = (m['content'] ?? m['ext']?['content'] ?? '').toString();
        _messages.insert(0, {
          'msgId': m['msgId'] ?? '',
          'fromUserId': fromId,
          'content': c,
          'contentType': m['contentType'] ?? m['ext']?['contentType'] ?? 'text',
          'createdAt': m['createdAt'] ?? DateTime.now().toIso8601String(),
          'mentioned': _msgMentionsMe(c),
        });
      });
      _scrollToBottom();
      markIncomingRead(_im, _messages, _isMe, onUpdated: () {
        if (mounted) setState(() {});
      });
      MessageCache.mergeIm(MessageCache.imSingleKey(widget.peerId), _messages);
    });
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading || _searchVisible) return;
    final pos = _scrollController.position;
    if (!pos.hasPixels || pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  Future<void> _bootstrapMessages() async {
    final cached = await MessageCache.load(MessageCache.imSingleKey(widget.peerId));
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _loading = false;
        _annotateMentions(_messages);
      });
    }
    await _loadMessages(refresh: true);
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final resp = await _im.messages(widget.peerId, limit: _pageSize, offset: _messages.length);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final batch = List<dynamic>.from(data['messages'] ?? []).where((m) => !isHiddenImMessage(m)).toList();
        setState(() {
          _messages.addAll(batch);
          _annotateMentions(_messages);
          _hasMore = batch.length >= _pageSize;
        });
        await MessageCache.mergeIm(MessageCache.imSingleKey(widget.peerId), _messages);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    CallCoordinator.instance.unregisterChatPeer(widget.peerId);
    AudioPlaybackHub.stopAll();
    _scrollController.removeListener(_onScroll);
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _twinPollTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    if (refresh) _hasMore = true;
    try {
      final resp = await _im.messages(widget.peerId, limit: _pageSize, offset: 0);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() {
          _messages = List<dynamic>.from(data['messages'] ?? []).where((m) => !isHiddenImMessage(m)).toList();
          _annotateMentions(_messages);
          _loading = false;
          _fromCache = false;
          _hasMore = _messages.length >= _pageSize;
        });
        await MessageCache.mergeIm(MessageCache.imSingleKey(widget.peerId), _messages);
        markIncomingRead(_im, _messages, _isMe, onUpdated: () {
          if (mounted) setState(() {});
        });
      } else if (mounted) {
        setState(() {
          _loading = false;
          _fromCache = _messages.isNotEmpty;
        });
        if (resp.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录已过期，请重新登录')));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fromCache = _messages.isNotEmpty;
        });
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_uploadingImage) return;
    final picked = await pickImageBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await _upload.uploadImageBytes(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      await _sendMessage(retryContent: url, contentType: 'image');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_uploadingFile) return;
    final picked = await pickFileBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploadingFile = true);
    try {
      final url = await _upload.uploadFileBytes(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      final name = picked.name ?? '文件';
      final payload = encodeFileMessage(url: url, name: name, size: picked.bytes.length);
      await _sendMessage(retryContent: payload, contentType: 'file');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  Future<void> _pickFromDrive() async {
    if (_uploadingFile) return;
    final node = await showDrivePickerSheet(context, token: widget.token, userId: widget.userId);
    if (node == null || !mounted) return;
    setState(() => _uploadingFile = true);
    try {
      final payload = encodeDriveFileMessage(node);
      await _sendMessage(retryContent: payload, contentType: 'file');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
    }
  }

  Future<void> _pickAndSendVoice() async {
    if (_uploadingVoice) return;
    final picked = await showVoiceRecordSheet(context);
    if (picked == null || !mounted) return;
    setState(() => _uploadingVoice = true);
    try {
      final url = await _upload.uploadAudioBytes(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      final payload = encodeMediaMessage(
        url: url,
        durationMs: picked.durationMs,
        name: picked.name,
        size: picked.bytes.length,
        waveform: picked.waveform,
      );
      await _sendMessage(retryContent: payload, contentType: 'voice');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('语音发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
    }
  }

  Future<void> _pickAndSendVideo() async {
    if (_uploadingVideo) return;
    final picked = await pickVideoBytes();
    if (picked == null || !mounted) return;
    if (picked.bytes.length > 15 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端建议视频不超过 15MB，过大可能上传很慢或失败')),
      );
    }
    setState(() => _uploadingVideo = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视频上传中，请稍候…'), duration: Duration(seconds: 30)),
    );
    try {
      final uploaded = await _upload.uploadVideoWithPoster(
        picked.bytes,
        userId: widget.userId,
        filename: picked.name,
      );
      if (!mounted) return;
      final payload = encodeMediaMessage(
        url: uploaded.url,
        name: picked.name,
        size: picked.bytes.length,
        poster: uploaded.poster,
      );
      await _sendMessage(retryContent: payload, contentType: 'video');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频发送失败: $e')));
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _startCall(CallMedia media) async {
    await CallCoordinator.instance.startOutgoing(
      peerId: widget.peerId,
      peerName: widget.peerName,
      media: media,
    );
  }

  void _scheduleTwinReplyPoll() {
    // ponytail: WS 重连竞态可能丢推送；短轮询兜底数字分身代答
    _twinPollTimer?.cancel();
    _twinPollTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _loadMessages(refresh: true);
    });
  }

  Future<void> _sendMessage({String? retryContent, String? retryTempId, String contentType = 'text'}) async {
    var content = (retryContent ?? _msgController.text).trim();
    if (content.isEmpty) return;

    if (retryContent == null && contentType == 'text') {
      content = applyReplyQuote(content, _replyTo);
      _cancelReply();
      _msgController.clear();
    }

    final tempId = retryTempId ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    if (retryTempId == null) {
      setState(() {
        _messages.insert(0, {
          'msgId': tempId,
          'fromUserId': widget.userId,
          'content': content,
          'contentType': contentType,
          'createdAt': DateTime.now().toIso8601String(),
        });
      });
      _scrollToBottom();
    } else {
      setState(() {
        final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
        if (idx >= 0) _messages[idx]['status'] = 'sending';
      });
    }

    try {
      final resp = await _im.send(toUserId: widget.peerId, content: content, contentType: contentType);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final serverMsgId = data['msgId'] as String?;
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
            if (idx >= 0) {
              if (serverMsgId != null) _messages[idx]['msgId'] = serverMsgId;
              _messages[idx]['status'] = 'sent';
            }
          });
          if (contentType == 'text') _scheduleTwinReplyPoll();
        }
      } else if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
          if (idx >= 0) _messages[idx]['status'] = 'failed';
        });
        final err = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $err')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
          if (idx >= 0) _messages[idx]['status'] = 'failed';
        });
        if (retryTempId == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
        }
      }
    }
  }

  void _showPeerProfile() {
    showUserProfileSheet(
      context,
      userId: widget.peerId,
      displayName: widget.peerName,
      userCode: widget.peerUserCode,
      levelName: widget.peerLevelName,
      premium: widget.peerLevelName.isNotEmpty && widget.peerLevelName != '普通',
      token: widget.token,
      sheetContext: UserProfileContext.viewOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜索消息…', border: InputBorder.none, isDense: true),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : GestureDetector(
                onTap: _showPeerProfile,
                child: Row(
                children: [
                  CircleAvatar(radius: 18, backgroundColor: theme.colorScheme.primaryContainer, child: Text(initial, style: TextStyle(color: theme.colorScheme.onPrimaryContainer))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.peerName, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16)),
                        if (widget.peerUserCode.isNotEmpty)
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.peerUserCode,
                                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.peerLevelName.isNotEmpty && widget.peerLevelName != '普通') ...[
                                const SizedBox(width: 4),
                                PremiumLevelChip(levelName: widget.peerLevelName, compact: true),
                              ],
                            ],
                          )
                        else
                          Text('单聊', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
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
                if (!CallCoordinator.instance.inCall)
                  ChatComposerAction(
                    id: 'call_audio',
                    icon: Icons.phone_outlined,
                    label: '语音通话',
                    onTap: () => _startCall(CallMedia.audio),
                  ),
                if (!CallCoordinator.instance.inCall)
                  ChatComposerAction(
                    id: 'call_video',
                    icon: Icons.videocam_outlined,
                    label: '视频通话',
                    onTap: () => _startCall(CallMedia.video),
                  ),
                ChatComposerAction(
                  id: 'search',
                  icon: Icons.search,
                  label: '搜索',
                  onTap: () => setState(() => _searchVisible = true),
                ),
                ChatComposerAction(
                  id: 'mention_filter',
                  icon: Icons.alternate_email,
                  label: _mentionFilter ? '显示全部' : '@我的',
                  onTap: () => setState(() => _mentionFilter = !_mentionFilter),
                ),
              ]),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_fromCache)
            Material(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 14, color: Colors.orange.shade800),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('网络不可用，显示本地缓存', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
                    ),
                    TextButton(onPressed: () => _loadMessages(refresh: true), child: const Text('重试')),
                  ],
                ),
              ),
            ),
          if (_mentionFilter)
            Material(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('仅显示 @我的消息 · ${_visibleMessages.length} 条', style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
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
          if (_loading && _visibleMessages.isEmpty) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _visibleMessages.isEmpty
                ? Center(child: Text(_searchQuery.isEmpty ? '和 ${widget.peerName} 打个招呼吧' : '无匹配消息', style: TextStyle(color: Colors.grey.shade600)))
                : RefreshIndicator(
                        onRefresh: () => _loadMessages(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _listItems.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (_loadingMore && i == _listItems.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            final item = _listItems[i];
                            if (item is String) return chatDateChip(item);
                            return _messageTile(item);
                          },
                        ),
                      ),
          ),
          if (_uploadingImage || _uploadingFile || _uploadingVoice || _uploadingVideo) const LinearProgressIndicator(minHeight: 2),
          if (_replyTo != null)
            replyPreviewBar(quote: (_replyTo!['content'] ?? '').toString(), onCancel: _cancelReply),
          chatComposer(
            context: context,
            controller: _msgController,
            onSend: _sendMessage,
            onPickImage: _pickAndSendImage,
            onPickFile: _pickAndSendFile,
            onPickDrive: _pickFromDrive,
            onPickVoice: _pickAndSendVoice,
            onPickVideo: _pickAndSendVideo,
            enterToSend: _enterToSend,
          ),
        ],
      ),
    );
  }
}
