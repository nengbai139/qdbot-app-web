import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/ai_api.dart';
import '../util/circle_conv.dart';
import '../util/tab_data_cache.dart';
import 'chat_helpers.dart';
import 'ai_chat_page.dart';
import 'profile/payment/ai_subscription_pay_page.dart';
import 'scene_banner.dart';

class AIChatsTab extends StatefulWidget {
  final String token;
  final String userId;
  final Stream<Map<String, dynamic>>? msgStream;
  final bool Function()? isTabActive;
  const AIChatsTab({super.key, required this.token, required this.userId, this.msgStream, this.isTabActive});

  @override
  State<AIChatsTab> createState() => AIChatsTabState();
}

class AIChatsTabState extends State<AIChatsTab> with AutomaticKeepAliveClientMixin {
  List<dynamic> _conversations = [];
  bool _loading = true;
  bool _showArchived = false;
  String _searchQuery = '';
  AiSubscription? _aiSub;
  final _searchController = TextEditingController();
  StreamSubscription? _wsSub;
  Timer? _convReloadDebounce;
  DateTime? _lastFetch;
  bool _refreshing = false;
  String _convFingerprint = '';
  late final AiApi _ai = AiApi(widget.token);

  @override
  bool get wantKeepAlive => true;

  String _fingerprint(List<dynamic> list) {
    final b = StringBuffer();
    for (final c in list) {
      b
        ..write(c['convId'])
        ..write('|')
        ..write(c['lastMsgTime'] ?? c['updatedAt'])
        ..write('|')
        ..write((c['lastMsg'] ?? '').toString().length)
        ..write(';');
    }
    return b.toString();
  }

  List<dynamic> get _filtered {
    final list = _conversations.where((c) {
        final convId = (c['convId'] ?? '').toString();
        if (isCircleUtilityConvId(convId)) return false;
        final q = _searchQuery.trim().toLowerCase();
        if (q.isEmpty) return true;
        final title = (c['title'] ?? '').toString().toLowerCase();
        final last = (c['lastMsg'] ?? '').toString().toLowerCase();
        final model = (c['model'] ?? '').toString().toLowerCase();
        return '$title $last $model'.contains(q);
      }).toList();
    list.sort((a, b) => sessionTimeMs(b).compareTo(sessionTimeMs(a)));
    return list;
  }

  String _timeGroup(String? iso) {
    if (iso == null || iso.isEmpty) return '更早';
    final sep = formatDaySeparator(iso);
    if (sep == '今天' || sep == '昨天') return sep;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
      if (diff < 7) return '本周';
    } catch (_) {}
    return '更早';
  }

  List<Object> _groupedItems(List<dynamic> list) {
    final items = <Object>[];
    String? lastGroup;
    for (final c in list) {
      final g = _timeGroup((c['lastMsgTime'] ?? c['updatedAt'])?.toString());
      if (g != lastGroup) {
        items.add(g);
        lastGroup = g;
      }
      items.add(c);
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _boot();
    _wsSub = widget.msgStream?.listen((m) {
      if (!mounted || (m['type'] ?? '').toString() != 'ai') return;
      if (isCircleUtilityWs(Map<String, dynamic>.from(m))) return;
      final convId = aiConvIdFromWs(Map<String, dynamic>.from(m));
      if (convId.isEmpty || isCircleUtilityConvId(convId)) return;
      if (isAgentProgressContent((m['content'] ?? '').toString())) return;
      _debouncedLoadConversations();
    });
  }

  Future<void> _boot() async {
    if (!TabDataCache.hasConversations) await TabDataCache.restore(widget.token);
    if (!mounted) return;
    if (TabDataCache.hasConversations) {
      setState(() {
        _conversations = List<dynamic>.from(TabDataCache.conversations!);
        _aiSub = TabDataCache.aiSub;
        _loading = false;
      });
      _lastFetch = DateTime.now();
      _loadConversations(silent: true);
      _loadAiSub();
    } else {
      _loadConversations();
      _loadAiSub();
    }
  }

  void refreshIfStale({Duration maxAge = const Duration(seconds: 30)}) {
    final now = DateTime.now();
    if (_lastFetch != null && now.difference(_lastFetch!) < maxAge) return;
    _loadConversations(silent: _conversations.isNotEmpty);
    _loadAiSub();
  }

  void _debouncedLoadConversations() {
    if (widget.isTabActive != null && !widget.isTabActive!()) return;
    _convReloadDebounce?.cancel();
    _convReloadDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _loadConversations(silent: _conversations.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _convReloadDebounce?.cancel();
    _searchController.dispose();
    _wsSub?.cancel();
    super.dispose();
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _onSearchChanged(String v) => setState(() => _searchQuery = v);

  String _preview(dynamic c) {
    final last = (c['lastMsg'] ?? '').toString().trim();
    if (last.isNotEmpty) {
      if (isAgentProgressContent(last)) return 'AI 思考中…';
      final oneLine = last.replaceAll('\n', ' ');
      return oneLine.length > 60 ? '${oneLine.substring(0, 60)}…' : oneLine;
    }
    final model = (c['model'] ?? '').toString();
    return model.isEmpty ? '暂无消息' : model;
  }

  Future<void> _loadAiSub() async {
    try {
      final s = await _ai.getSubscription();
      if (mounted) setState(() => _aiSub = s);
      TabDataCache.putAiSub(s);
    } catch (_) {}
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && _conversations.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final resp = await _ai.conversations(status: _showArchived ? 'archived' : 'active');
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final list = (data['conversations'] as List?) ?? [];
        final fp = _fingerprint(list);
        if (fp == _convFingerprint && !_loading) {
          _lastFetch = DateTime.now();
          return;
        }
        _convFingerprint = fp;
        setState(() {
          _conversations = list;
          _loading = false;
        });
        TabDataCache.putConversations(list);
        _lastFetch = DateTime.now();
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _renameConversation(String convId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()),
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
      final resp = await _ai.updateTitle(convId, newTitle);
      if (mounted && resp.statusCode == 200) _loadConversations();
    } catch (_) {}
  }

  Future<bool> _setArchived(String convId, bool archive, {bool snack = true}) async {
    try {
      final resp = await _ai.setStatus(convId, archive ? 'archived' : 'active');
      if (mounted && resp.statusCode == 200) {
        if (snack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(archive ? '已归档' : '已恢复'), duration: const Duration(seconds: 1)),
          );
        }
        _loadConversations();
        return true;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
    return false;
  }

  Future<void> _deleteConversation(String convId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除「${title.isEmpty ? '此对话' : title}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final resp = await _ai.deleteConversation(convId);
      if (mounted && resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)));
        _loadConversations();
      }
    } catch (_) {}
  }

  Future<void> _restoreAllArchived() async {
    if (_conversations.isEmpty) return;
    final n = _conversations.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部恢复'),
        content: Text('恢复全部 $n 个归档对话？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var restored = 0;
    for (final c in List<dynamic>.from(_conversations)) {
      final convId = (c['convId'] ?? '').toString();
      if (convId.isEmpty) continue;
      if (await _setArchived(convId, false, snack: false)) restored++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢复 $restored 个对话'), duration: const Duration(seconds: 1)),
      );
      _loadConversations();
    }
  }

  void _showConversationActions(String convId, String title) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!_showArchived)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameConversation(convId, title);
                },
              ),
            ListTile(
              leading: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(_showArchived ? '恢复到列表' : '归档'),
              onTap: () {
                Navigator.pop(ctx);
                _setArchived(convId, !_showArchived);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConversation(convId, title);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(dynamic c) {
    final convId = (c['convId'] ?? '').toString();
    final title = (c['title'] ?? '新对话').toString();
    final time = (c['lastMsgTime'] ?? c['updatedAt'])?.toString();
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: _showArchived ? Colors.grey.shade300 : null,
        child: Icon(Icons.smart_toy, color: _showArchived ? Colors.grey.shade700 : null),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _showArchived ? Colors.grey.shade700 : null)),
      subtitle: Text(_preview(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
      trailing: Text(formatSessionTime(time), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      onLongPress: () => _showConversationActions(convId, title),
      onTap: () => _openChat(convId, title),
    );
    if (_searchQuery.trim().isNotEmpty) return tile;

    final archiving = !_showArchived;
    return Dismissible(
      key: ValueKey(convId),
      direction: DismissDirection.horizontal,
      background: Container(
        color: archiving ? Colors.grey.shade600 : Colors.green.shade500,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(archiving ? Icons.archive_outlined : Icons.unarchive_outlined, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) return _setArchived(convId, archiving);
        await _deleteConversation(convId, title);
        return false;
      },
      child: tile,
    );
  }

  void openFromNotify(Map<String, String> data) {
    final convId = data['convId'] ?? '';
    if (convId.isEmpty) return;
    if (convId == AIChatPage.activeConvId) return;
    String title = '对话';
    for (final c in _conversations) {
      if ((c['convId'] ?? '').toString() == convId) {
        title = (c['title'] ?? title).toString();
        break;
      }
    }
    _openChat(convId, title);
  }

  void _openChat(String convId, String title) {
    if (convId.isNotEmpty && convId == AIChatPage.activeConvId) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatPage(
          token: widget.token,
          userId: widget.userId,
          convId: convId,
          title: title,
          msgStream: widget.msgStream,
          onTitleChanged: _loadConversations,
          onArchived: _loadConversations,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filtered;
    final searching = _searchQuery.trim().isNotEmpty;
    final grouped = searching ? filtered.cast<Object>() : _groupedItems(filtered);

    final barW = MediaQuery.sizeOf(context).width;
    final searchW = barW * 2 / 3;
    final labelStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16) ?? const TextStyle(fontSize: 16);

    Widget plusBtn() => toolbarPlusButton(
          context,
          onPressed: () => showChatComposerMoreSheet(context, actions: [
            if (!_showArchived)
              ChatComposerAction(
                id: 'new',
                icon: Icons.add_comment_outlined,
                label: '新对话',
                onTap: () => _openChat('', '新对话'),
              ),
            ChatComposerAction(
              id: 'archive',
              icon: _showArchived ? Icons.chat_outlined : Icons.archive_outlined,
              label: _showArchived ? '返回对话' : '已归档',
              onTap: () {
                setState(() => _showArchived = !_showArchived);
                _loadConversations();
              },
            ),
            if (_showArchived && _conversations.isNotEmpty)
              ChatComposerAction(
                id: 'restore_all',
                icon: Icons.unarchive_outlined,
                label: '全部恢复',
                onTap: _restoreAllArchived,
              ),
            ChatComposerAction(
              id: 'refresh',
              icon: Icons.refresh,
              label: '刷新',
              onTap: _loadConversations,
            ),
          ]),
        );

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
                  Text(_showArchived ? '已归档' : '助手', style: labelStyle),
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
                    hintText: '搜索对话',
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
          SceneBanner(text: _showArchived ? '右滑恢复 · 左滑删除。' : '右滑归档 · 左滑删除。私人 AI 对话，仅自己可见。'),
          if (_aiSub?.expiringSoon == true)
            Material(
              color: Colors.orange.shade50,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.schedule, color: Colors.orange.shade800, size: 20),
                title: Text(
                  'AI Pro 将于 ${_aiSub!.daysLeft} 天后到期',
                  style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                ),
                trailing: TextButton(
                  onPressed: () async {
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
                    _loadAiSub();
                  },
                  child: const Text('续订'),
                ),
              ),
            ),
          Expanded(
            child: _loading && _conversations.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _conversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_showArchived ? '暂无归档对话' : '暂无 AI 对话', style: TextStyle(color: Colors.grey.shade600)),
                            if (!_showArchived) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => _openChat('', '新对话'),
                                icon: const Icon(Icons.add),
                                label: const Text('开始新对话'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : searching && filtered.isEmpty
                        ? Center(
                            child: Text(
                              '没有匹配的对话\n可搜：标题、最后一条消息',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadConversations,
                            child: ListView.builder(
                              itemCount: grouped.length,
                              itemBuilder: (_, i) {
                                final item = grouped[i];
                                if (item is String) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                    child: Text(item, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                  );
                                }
                                return _conversationTile(item);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
