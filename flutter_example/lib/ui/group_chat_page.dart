import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../ai_bubble.dart';
import '../api/im_api.dart';
import '../api/upload_api.dart';
import '../session.dart';
import '../util/audio_playback.dart';
import '../util/message_cache.dart';
import 'drive/drive_picker_sheet.dart';
import 'chat_helpers.dart';
import 'chat_page.dart';
import 'file_message.dart';
import 'media_bubble.dart';
import 'media_message.dart';
import 'im_media.dart';
import '../util/video_viewer.dart';
import 'voice_record_sheet.dart';
import 'user_pick_sheet.dart';
import 'circle/circle_navigation.dart';
import 'circle/meeting_deep_link.dart';
import 'circle/meeting_invite_card.dart';
import 'premium/contact_card.dart';
import 'premium/share_contact_sheet.dart';
import 'premium/user_code_display.dart';
import 'premium/user_profile_sheet.dart';

class GroupChatPage extends StatefulWidget {
  final String token;
  final String groupId;
  final String groupName;
  final String userId;
  final Stream<Map<String, dynamic>>? msgStream;
  final List<dynamic> initialMembers;

  const GroupChatPage({
    super.key,
    required this.token,
    required this.groupId,
    required this.groupName,
    required this.userId,
    this.msgStream,
    this.initialMembers = const [],
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  // 引用回复
  Map<String, dynamic>? _replyTo;

  void _cancelReply() { setState(() => _replyTo = null); }

  void _startReply(Map<String, dynamic> msg) {
    setState(() => _replyTo = msg);
  }

  bool _isMe(dynamic m) {
    final from = (m['senderId'] ?? m['fromUserId'] ?? '').toString();
    return from == widget.userId || from == 'me';
  }

// 群公告变量
  String _notice = '';
  bool _noticeIsNew = false;

  Future<void> _loadChatPrefs() async {
    final enter = await SessionStore.loadEnterToSend();
    final read = await SessionStore.loadShowReadBadge();
    if (mounted) setState(() {
      _enterToSend = enter;
      _showReadBadge = read;
    });
  }

  Future<void> _loadNotice() async {
    try {
      final resp = await _im.groupNotice(widget.groupId);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final notice = (data['notice'] ?? '').toString();
        final seen = await SessionStore.loadGroupNoticeSeen(widget.groupId);
        setState(() {
          _notice = notice;
          _noticeIsNew = notice.isNotEmpty && seen != notice.hashCode.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _markNoticeSeen() async {
    if (_notice.isEmpty) return;
    await SessionStore.saveGroupNoticeSeen(widget.groupId, _notice.hashCode.toString());
    if (mounted) setState(() => _noticeIsNew = false);
  }

  Future<void> _showNotice() async {
    await _markNoticeSeen();
    if (!mounted || _notice.isEmpty) return;
    final isOwner = _members.any((m) => m['userId'] == widget.userId && m['role'] == 'owner');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('群公告'),
        content: SingleChildScrollView(child: Text(_notice)),
        actions: [
          if (isOwner)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _editNotice();
              },
              child: const Text('编辑'),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _editNotice() async {
    final controller = TextEditingController(text: _notice);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('群公告'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '公告内容', border: OutlineInputBorder(), hintText: '输入群公告，如群规、通知等'),
          maxLines: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('清空')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      final resp = await _im.updateGroupNotice(widget.groupId, result);
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _notice = result;
          _noticeIsNew = false;
        });
        await SessionStore.saveGroupNoticeSeen(widget.groupId, result.hashCode.toString());
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('公告已更新')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
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

  Future<void> _transferOwner(String newOwnerId, String newOwnerName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('转让群主'),
        content: Text('确定将群主转让给 $newOwnerName？\n转让后你将变为普通成员。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认转让'), style: FilledButton.styleFrom(backgroundColor: Colors.orange)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final resp = await _im.transferOwner(widget.groupId, newOwnerId);
      if (resp.statusCode == 200 && mounted) {
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('群主已转让给 $newOwnerName')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<dynamic> _messages = [];
  List<dynamic> _members = [];
  bool _loading = true;
  bool _loadingMembers = true;
  bool _fromCache = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _pageSize = 50;
  bool _searchVisible = false;
  bool _mentionFilter = false;
  String _searchQuery = '';

  Set<String> get _myMentionNames {
    final myInfo = _members.isNotEmpty
        ? _members.firstWhere(
            (m) => (m['userId'] ?? '') == widget.userId,
            orElse: () => <String, dynamic>{},
          )
        : <String, dynamic>{};
    return {
      widget.userId,
      if (myInfo['nickname'] is String) myInfo['nickname'] as String,
      if (myInfo['userCode'] is String) myInfo['userCode'] as String,
      if (myInfo['displayName'] is String) myInfo['displayName'] as String,
    }.where((n) => n.isNotEmpty).toSet();
  }
  bool _uploadingImage = false;
  bool _uploadingFile = false;
  bool _uploadingVoice = false;
  bool _uploadingVideo = false;
  bool _enterToSend = true;
  bool _showReadBadge = true;
  StreamSubscription? _wsSub;
  late final ImApi _im = ImApi(widget.token);
  late final UploadApi _upload = UploadApi(widget.token);

  @override
  void initState() {
    super.initState();
    _loadChatPrefs();
    _loadMembers();
    _bootstrapMessages();
    _loadNotice();
    _scrollController.addListener(_onScroll);
    // 监听 WebSocket 实时消息，替代轮询
    _wsSub = widget.msgStream?.listen((m) {
      if (!mounted) return;
      final type = m['type'] as String? ?? '';
      // 撤回消息
      if (type == 'im_revoke' && mounted) {
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
      // 群消息：groupId 可能在顶层（step 8）或 ext 内（step 9 fallback）
      final gid = (m['groupId'] ?? m['ext']?['groupId'] ?? '').toString();
      if (type == 'im' && gid == widget.groupId) {
        // 实时收到群消息，追加到列表（跳过自己发的，已通过乐观更新显示）
        final fromId = (m['fromUserId'] ?? m['ext']?['fromUserId'] ?? '').toString();
        if (fromId == widget.userId) return;
        final c = (m['content'] ?? m['ext']?['content'] ?? '').toString();
        final mentioned = _myMentionNames.any((name) => c.contains('@$name')) || c.contains('@所有人');
        setState(() {
          _messages.insert(0, {
            'msgId': m['msgId'] ?? '',
            'fromUserId': fromId,
            'senderName': (m['senderName'] ?? m['ext']?['senderName'] ?? fromId).toString(),
            'content': m['content'] ?? m['ext']?['content'] ?? '',
            'contentType': (m['contentType'] ?? m['ext']?['contentType'] ?? 'text').toString(),
            'createdAt': (m['createdAt'] ?? DateTime.now().toIso8601String()).toString(),
            'mentioned': mentioned,
          });
        });
        _scrollToBottom();
        markIncomingRead(_im, _messages, _isMe, onUpdated: () {
          if (mounted) setState(() {});
        });
        MessageCache.mergeIm(MessageCache.imGroupKey(widget.groupId), _messages);
      }
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
    final cached = await MessageCache.load(MessageCache.imGroupKey(widget.groupId));
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _loading = false;
      });
    }
    await _loadMessages(refresh: true);
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final resp = await _im.groupMessages(widget.groupId, limit: _pageSize, offset: _messages.length);
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final batch = _mapGroupMessages(data['messages'] as List<dynamic>? ?? []);
        setState(() {
          _messages.addAll(batch);
          _hasMore = batch.length >= _pageSize;
        });
        await MessageCache.mergeIm(MessageCache.imGroupKey(widget.groupId), _messages);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<dynamic> _mapGroupMessages(List<dynamic> raw) {
    final myInfo = _members.isNotEmpty
        ? _members.firstWhere(
            (m) => (m['userId'] ?? '') == widget.userId,
            orElse: () => {},
          )
        : {};
    final myNames = {
      widget.userId,
      if (myInfo is Map && myInfo['nickname'] is String) myInfo['nickname'] as String,
      if (myInfo is Map) (myInfo['userId'] ?? '').toString(),
    }.where((n) => n.isNotEmpty).toSet();

    return raw.map((m) {
      final c = (m['content'] ?? '').toString();
      final mentioned = myNames.any((name) => c.contains('@$name')) || c.contains('@所有人');
      return {
        ...Map<String, dynamic>.from(m as Map),
        'mentioned': mentioned,
      };
    }).toList();
  }

  @override
  void dispose() {
    AudioPlaybackHub.stopAll();
    _scrollController.removeListener(_onScroll);
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
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

  Future<void> _openDirectChat(String peerId, String peerName, String peerUserCode, String peerLevelName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          token: widget.token,
          userId: widget.userId,
          peerId: peerId,
          peerName: peerName,
          peerUserCode: peerUserCode,
          peerLevelName: peerLevelName,
          msgStream: widget.msgStream,
        ),
      ),
    );
  }

  Future<void> _loadMembers() async {
    try {
      final resp = await _im.groupMembers(widget.groupId);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) {
          setState(() {
            _members = data['members'] ?? [];
            _loadingMembers = false;
          });
        }
      } else {
        debugPrint('_loadMembers failed: ${resp.statusCode} ${resp.body}');
        if (mounted) setState(() => _loadingMembers = false);
      }
    } catch (e) {
      debugPrint('_loadMembers error: $e');
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    if (refresh) _hasMore = true;
    try {
      final resp = await _im.groupMessages(widget.groupId, limit: _pageSize, offset: 0);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) {
          final msgs = _mapGroupMessages(data['messages'] as List<dynamic>? ?? []);
          setState(() {
            _messages = msgs.where((m) => !isHiddenImMessage(m)).toList();
            _loading = false;
            _fromCache = false;
            _hasMore = msgs.length >= _pageSize;
          });
          await MessageCache.mergeIm(MessageCache.imGroupKey(widget.groupId), _messages);
          await markIncomingRead(_im, _messages, _isMe, onUpdated: () {
            if (mounted) setState(() {});
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
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
          'senderName': '我',
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
      final resp = await _im.send(groupId: widget.groupId, content: content, contentType: contentType);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final serverMsgId = data['msgId'] as String?;
        if (serverMsgId != null && mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
            if (idx >= 0) {
              _messages[idx]['msgId'] = serverMsgId;
              _messages[idx]['status'] = 'sent';
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['msgId'] == tempId);
            if (idx >= 0) _messages[idx]['status'] = 'failed';
          });
          if (retryTempId == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: ${resp.body}')));
          }
        }
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

  List<dynamic> get _visibleMessages {
    var list = filterMessagesByQuery(_messages, _searchQuery).where((m) => !isHiddenImMessage(m)).toList();
    if (_mentionFilter) {
      list = list.where((m) => (m['mentioned'] ?? false) == true).toList();
    }
    return list;
  }
  List<Object> get _listItems => buildMessageListWithDates(_visibleMessages);

  Widget _groupMessageBubble(dynamic m, bool isMe, String c, String ct, bool revoked, bool md, String? ts) {
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
              ? () => _openDirectChat(card.userId, card.displayName, card.userCode, card.levelName)
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
    return AiBubble(
      isUser: isMe,
      isMarkdown: md,
      isBot: ct == 'bot_reply',
      content: c,
      contentType: ct,
      createdAt: ts,
      context: context,
      mentionMeNames: ct == 'text' || ct.isEmpty ? _myMentionNames : null,
    );
  }

  Widget _groupMessageTile(dynamic m) {
    final isMe = _isMe(m);
    final c = m['content'] ?? '';
    final ct = (m['contentType'] ?? 'text').toString();
    final revoked = ct == 'revoked';
    final failed = m['status'] == 'failed';
    final md = shouldRenderMarkdown(c.toString(), contentType: ct, isUser: isMe);
    final ts = (m['createdAt'] ?? m['created_at'])?.toString();
    final sender = (m['senderName'] ?? m['fromUserId'] ?? '').toString();
    final senderCode = (m['senderUserCode'] ?? '').toString();
    final senderLevel = (m['senderLevelName'] ?? '').toString();
    final fromId = (m['fromUserId'] ?? m['senderId'] ?? '').toString();
    final mentioned = (m['mentioned'] ?? false) == true;
    final senderInitial = sender.isNotEmpty ? sender[0] : '?';
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
            avatarLabel: isMe ? '我' : senderInitial,
            senderName: isMe ? null : sender,
            senderUserCode: isMe ? null : senderCode,
            senderLevelName: isMe ? null : senderLevel,
            onSenderTap: isMe
                ? null
                : () => showUserProfileSheet(
                      context,
                      userId: fromId,
                      displayName: sender,
                      userCode: senderCode,
                      levelName: senderLevel,
                      premium: m['senderPremium'] == true,
                      token: widget.token,
                      sheetContext: UserProfileContext.fromGroup,
                      onMessage: fromId.isNotEmpty && fromId != widget.userId
                          ? () => _openDirectChat(fromId, sender, senderCode, senderLevel)
                          : null,
                    ),
            mentioned: mentioned,
            bubble: _groupMessageBubble(m, isMe, c.toString(), ct, revoked, md, ts),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: '搜索群消息…', border: InputBorder.none, isDense: true),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : GestureDetector(
          onTap: () => _editGroupName(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.groupName, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
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
              onPressed: () {
                final isOwner = _members.any((m) => m['userId'] == widget.userId && m['role'] == 'owner');
                showChatComposerMoreSheet(context, actions: [
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
                  ChatComposerAction(
                    id: 'members',
                    icon: Icons.people_outline,
                    label: '群成员',
                    onTap: () async {
                      await _loadMembers();
                      if (context.mounted) _showMembers(context);
                    },
                  ),
                  if (isOwner)
                    ChatComposerAction(
                      id: 'notice',
                      icon: Icons.campaign_outlined,
                      label: '群公告',
                      onTap: _showNotice,
                    ),
                  if (isOwner)
                    ChatComposerAction(
                      id: 'transfer',
                      icon: Icons.swap_horiz,
                      label: '转让群主',
                      onTap: () async {
                        if (_members.isEmpty) await _loadMembers();
                        if (context.mounted) _showTransferPicker(context);
                      },
                    ),
                  ChatComposerAction(
                    id: 'leave',
                    icon: Icons.logout,
                    label: '退出群聊',
                    onTap: _leaveGroup,
                  ),
                ]);
              },
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
                    Expanded(child: Text('网络不可用，显示本地缓存', style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
                    TextButton(onPressed: () => _loadMessages(refresh: true), child: const Text('重试')),
                  ],
                ),
              ),
            ),
          if (_notice.isNotEmpty)
            Material(
              color: _noticeIsNew ? Colors.orange.shade100 : Colors.amber.shade50,
              child: InkWell(
                onTap: _showNotice,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.campaign, size: 18, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _notice,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                        ),
                      ),
                      if (_noticeIsNew)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(8)),
                          child: const Text('新', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loading && _visibleMessages.isEmpty) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _visibleMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group, size: 64, color: Colors.blue),
                        const SizedBox(height: 16),
                        Text(
                          _mentionFilter
                              ? '暂无 @我的消息'
                              : (_searchQuery.isEmpty ? '暂无消息，来发第一条吧' : '无匹配消息'),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        if (_members.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('${_members.length} 位成员', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
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
                          return _groupMessageTile(item);
                        },
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('找到 ${_visibleMessages.length} 条匹配', style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
              ),
            ),
          if (_replyTo != null)
            replyPreviewBar(
              quote: (_replyTo!['content'] ?? '').toString(),
              onCancel: _cancelReply,
            ),
          if (_uploadingImage || _uploadingFile || _uploadingVoice || _uploadingVideo) const LinearProgressIndicator(minHeight: 2),
          chatComposer(
            context: context,
            controller: _msgController,
            onSend: _sendMessage,
            onPickImage: _pickAndSendImage,
            onPickFile: _pickAndSendFile,
            onPickDrive: _pickFromDrive,
            onPickVoice: _pickAndSendVoice,
            onPickVideo: _pickAndSendVideo,
            hint: '输入消息 @提及成员',
            enterToSend: _enterToSend,
            onChanged: (value) {
              if (value.endsWith('@') || value.endsWith('@ ')) _showMentionPicker();
            },
            moreActions: [
              ChatComposerAction(
                id: 'mention',
                icon: Icons.alternate_email,
                label: '@提及',
                onTap: _showMentionPicker,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _inviteMembers() async {
    final existing = _members.map((m) => (m['userId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
    final members = await showUserPickSheet(
      context,
      im: _im,
      title: '邀请成员',
      multiSelect: true,
      confirmLabel: '邀请',
      excludeUserIds: existing,
    );
    if (members == null || members.isEmpty || !mounted) return;

    try {
      final resp = await _im.inviteMembers(widget.groupId, members);

      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final r = data['result'];
        final added = (r['added'] as List<dynamic>?) ?? [];
        final skipped = (r['skipped'] as List<dynamic>?) ?? [];
        final failed = (r['failed'] as List<dynamic>?) ?? [];

        var msg = '';
        if (added.isNotEmpty) msg += '已邀请: ${added.join(", ")}';
        if (skipped.isNotEmpty) msg += '${msg.isNotEmpty ? "\n" : ""}已在群中: ${skipped.join(", ")}';
        if (failed.isNotEmpty) msg += '${msg.isNotEmpty ? "\n" : ""}邀请失败: ${failed.join(", ")}';
        if (msg.isEmpty) msg = '未添加任何成员';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );

        if (added.isNotEmpty) _loadMembers(); // 刷新成员列表
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('邀请失败: ${resp.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络错误: $e')),
        );
      }
    }
  }


  void _showMentionPicker() {
    if (!mounted) return;
    if (_members.isEmpty) {
      _loadMembers().then((_) {
        if (!mounted || _members.isEmpty) return;
        _showMentionPicker();
      });
      return;
    }
    final members = _members.whereType<Map>().toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要 @ 的成员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange,
                child: Icon(Icons.campaign, size: 20, color: Colors.white),
              ),
              title: Text('所有人', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('通知所有群成员'),
              onTap: () {
                Navigator.pop(sheetCtx);
                var text = _msgController.text;
                if (text.endsWith('@')) text = text.substring(0, text.length - 1);
                if (text.endsWith('@ ')) text = text.substring(0, text.length - 2);
                _msgController.text = '$text@所有人 ';
                _msgController.selection = TextSelection.collapsed(offset: _msgController.text.length);
              },
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (_, i) {
                  final m = members[i];
                  final name = (m['nickname'] ?? m['displayName'] ?? m['userId'] ?? m['name'] ?? '未知').toString();
                  final code = (m['userCode'] ?? '').toString();
                  final level = (m['levelName'] ?? '').toString();
                  final tag = mentionInsertTag(Map<String, dynamic>.from(m as Map));
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(name)),
                        if (m['premium'] == true && level.isNotEmpty) PremiumLevelChip(levelName: level, compact: true),
                      ],
                    ),
                    subtitle: Text(code.isNotEmpty ? '$code · ${m['role'] == 'owner' ? '群主' : '成员'}' : (m['role'] == 'owner' ? '群主' : '成员')),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      var text = _msgController.text;
                      if (text.endsWith('@')) text = text.substring(0, text.length - 1);
                      if (text.endsWith('@ ')) text = text.substring(0, text.length - 2);
                      _msgController.text = '$text@$tag ';
                      _msgController.selection = TextSelection.collapsed(offset: _msgController.text.length);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

    Future<void> _removeMember(String userId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定将 $name 移出群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除'), style: FilledButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final resp = await _im.leaveGroup(widget.groupId, userId: userId);
      if (resp.statusCode == 200 && mounted) {
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已移除 $name')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

    Future<void> _editGroupName() async {
    final controller = TextEditingController(text: widget.groupName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '群名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final resp = await _im.renameGroup(widget.groupId, result);
      if (resp.statusCode == 200 && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('群名称已改为: $result')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改失败: ${resp.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _setMemberAlias(String userId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('设置备注名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '备注名', border: OutlineInputBorder(), hintText: '输入易于识别的名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final resp = await _im.setMemberAlias(widget.groupId, userId, result);
      if (resp.statusCode == 200 && mounted) {
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备注已更新: $result')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('设置失败: ${resp.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('确定退出该群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出'), style: FilledButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final resp = await _im.leaveGroup(widget.groupId);
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出群聊')));
        Navigator.pop(context); // 返回到消息列表
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  void _showTransferPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('选择新群主', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            ...(_members.where((m) => m['userId'] != widget.userId).map((m) {
              final name = (m['nickname'] ?? m['userId'] ?? '未知').toString();
              return ListTile(
                leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                title: Text(name),
                onTap: () {
                  Navigator.pop(context);
                  _transferOwner((m['userId'] ?? '').toString(), name);
                },
              );
            }).toList()),
          ],
        ),
      ),
    );
  }

void _showMembers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('群成员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${_members.length} 人', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      _inviteMembers();
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('邀请', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: _loadingMembers
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _members.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('暂无成员信息，下拉刷新重试')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _members.length,
                          itemBuilder: (_, i) {
                            final m = _members[i];
                            final name = (m['nickname'] ?? m['displayName'] ?? m['userId'] ?? m['name'] ?? '未知').toString();
                            final role = (m['role'] ?? 'member').toString();
                            final code = (m['userCode'] ?? '').toString();
                            final level = (m['levelName'] ?? '').toString();
                            final uid = (m['userId'] ?? '').toString();
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(name)),
                                  if (m['premium'] == true && level.isNotEmpty) PremiumLevelChip(levelName: level, compact: true),
                                ],
                              ),
                              subtitle: Text(
                                code.isNotEmpty
                                    ? '$code · ${role == 'owner' ? '群主' : role == 'admin' ? '管理员' : '成员'}'
                                    : (role == 'owner' ? '群主' : role == 'admin' ? '管理员' : '成员'),
                              ),
                              onTap: uid.isNotEmpty && uid != widget.userId
                                  ? () {
                                      Navigator.pop(context);
                                      showUserProfileSheet(
                                        context,
                                        userId: uid,
                                        displayName: name,
                                        userCode: code,
                                        levelName: level,
                                        premium: m['premium'] == true,
                                        token: widget.token,
                                        sheetContext: UserProfileContext.fromGroup,
                                        onMessage: () => _openDirectChat(uid, name, code, level),
                                      );
                                    }
                                  : null,
                                onLongPress: () {
                                  Navigator.pop(context);
                                  _setMemberAlias((m['userId'] ?? '').toString(), name);
                                },
                              trailing: role == 'owner'
                                  ? const Chip(label: Text('群主', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)
                                  : PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_horiz, size: 18),
                                      onSelected: (v) {
                                        Navigator.pop(context);
                                        if (v == 'transfer') _transferOwner((m['userId']??'').toString(), name);
                                        if (v == 'remove') _removeMember((m['userId']??'').toString(), name);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'transfer', child: Text('转让群主')),
                                        const PopupMenuItem(value: 'remove', child: Text('移除成员', style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

