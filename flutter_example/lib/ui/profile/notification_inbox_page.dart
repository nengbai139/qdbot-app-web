import 'package:flutter/material.dart';

import '../../util/notify_inbox.dart';
import '../app_theme.dart';
import '../circle/circle_notify_page.dart';
import '../ai_chat_page.dart';
import '../chat_page.dart';
import '../group_chat_page.dart';
import 'payment/ai_subscription_pay_page.dart';
import '../circle/widgets/circle_ui.dart';

/// 通知中心：按会话聚合未读，点进聊天；不在此逐条展示通知内容。
class NotificationInboxPage extends StatefulWidget {
  final String token;
  final String userId;
  final String userCode;

  const NotificationInboxPage({
    super.key,
    required this.token,
    required this.userId,
    this.userCode = '',
  });

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  List<InboxSessionTarget> _targets = [];
  int _totalUnread = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final targets = await NotifyInbox.loadSessionTargets(widget.token);
    final total = targets.fold<int>(0, (s, t) => s + t.unread);
    if (mounted) {
      setState(() {
        _targets = targets;
        _totalUnread = total;
        _loading = false;
      });
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'ai':
        return Icons.smart_toy_outlined;
      case 'subscription':
        return Icons.event_busy_outlined;
      case 'circle':
        return Icons.hub_outlined;
      case 'im_group':
        return Icons.group_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Color _accent(String kind) {
    switch (kind) {
      case 'ai':
        return AppTheme.brandBlue;
      case 'subscription':
        return Colors.orange.shade700;
      case 'circle':
        return const Color(0xFF6366F1);
      case 'im_group':
        return Colors.teal.shade700;
      default:
        return AppTheme.brandBlue;
    }
  }

  Future<void> _open(InboxSessionTarget t) async {
    if (t.kind == 'im_single' && (t.peerId ?? '').isNotEmpty) {
      await NotifyInbox.markImSessionRead(token: widget.token, peerId: t.peerId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            token: widget.token,
            userId: widget.userId,
            peerId: t.peerId!,
            peerName: t.peerName ?? t.peerId!,
            userCode: widget.userCode,
          ),
        ),
      );
    } else if (t.kind == 'im_group' && (t.groupId ?? '').isNotEmpty) {
      await NotifyInbox.markImSessionRead(token: widget.token, groupId: t.groupId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            token: widget.token,
            userId: widget.userId,
            groupId: t.groupId!,
            groupName: t.groupName ?? '群聊',
          ),
        ),
      );
    } else if (t.kind == 'ai' && (t.convId ?? '').isNotEmpty) {
      await NotifyInbox.markAiConvRead(token: widget.token, convId: t.convId!);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AIChatPage(
            token: widget.token,
            userId: widget.userId,
            convId: t.convId!,
            title: 'AI 对话',
          ),
        ),
      );
    } else if (t.kind == 'circle') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CircleNotifyPage(token: widget.token, userId: widget.userId),
        ),
      );
    } else if (t.kind == 'subscription') {
      await NotifyInbox.markKindRead(token: widget.token, kind: 'subscription');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiSubscriptionPayPage(token: widget.token, userId: widget.userId),
        ),
      );
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: circleSubAppBar(
        context,
        title: '通知中心',
        subtitle: _totalUnread > 0 ? '$_totalUnread 条未读' : '暂无未读',
        actions: [
          if (_totalUnread > 0)
            TextButton(
              onPressed: () async {
                await NotifyInbox.markAllRead(token: widget.token);
                if (mounted) _load();
              },
              child: const Text('全部已读'),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _targets.isEmpty
              ? ListView(
                  children: const [
                    CircleEmptyBox(
                      icon: Icons.notifications_none_outlined,
                      title: '暂无未读',
                      subtitle: '新的消息和提醒会出现在这里',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _targets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = _targets[i];
                    final color = _accent(t.kind);
                    return Material(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: color.withValues(alpha: 0.12),
                                child: Icon(_icon(t.kind), color: color, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('${t.unread} 条未读', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Badge(label: Text('${t.unread}')),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, color: scheme.outline),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
