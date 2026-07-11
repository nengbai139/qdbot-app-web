import 'package:flutter/material.dart';

import '../../util/notify_inbox.dart';
import '../app_theme.dart';
import 'circle_navigation.dart';
import 'moments_page.dart';
import 'video_page.dart';
import 'widgets/circle_ui.dart';

class CircleNotifyPage extends StatefulWidget {
  final String token;
  final String userId;

  const CircleNotifyPage({super.key, required this.token, required this.userId});

  @override
  State<CircleNotifyPage> createState() => _CircleNotifyPageState();
}

class _CircleNotifyPageState extends State<CircleNotifyPage> {
  List<NotifyEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final inbox = await NotifyInbox.mergeSync(widget.token);
      final items = inbox.items.where((e) => e.kind == 'circle').toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _eventIcon(String event) => switch (event) {
        'live.start' => Icons.sensors,
        'video.new' => Icons.ondemand_video_outlined,
        'moment.like' => Icons.favorite_outline,
        'moment.comment' => Icons.chat_bubble_outline,
        _ => Icons.photo_library_outlined,
      };

  Color _eventColor(String event) => switch (event) {
        'live.start' => const Color(0xFFE5484D),
        'video.new' => const Color(0xFF6366F1),
        'moment.like' => const Color(0xFFE5484D),
        _ => AppTheme.brandBlue,
      };

  Future<void> _open(NotifyEntry e) async {
    await NotifyInbox.markItemRead(e.id, token: widget.token);
    if (!mounted) return;
    setState(() {
      final i = _items.indexWhere((x) => x.id == e.id);
      if (i >= 0) _items[i] = e.copyWith(read: true);
    });

    final event = e.data['event'] ?? '';
    final roomId = e.data['roomId'] ?? '';
    if (event == 'live.start' && roomId.isNotEmpty) {
      await openCircleRoomById(context, token: widget.token, userId: widget.userId, roomId: roomId);
    } else if (event == 'video.new') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPage(token: widget.token, userId: widget.userId)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MomentsPage(token: widget.token, userId: widget.userId)),
      );
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _items.where((e) => !e.read).length;
    return Scaffold(
      appBar: circleSubAppBar(
        context,
        title: '圈子通知',
        subtitle: unread > 0 ? '$unread 条未读' : '全部已读',
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                await NotifyInbox.markKindRead(token: widget.token, kind: 'circle');
                if (mounted) _load();
              },
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? ListView(
                  children: const [
                    CircleEmptyBox(
                      icon: Icons.notifications_none_outlined,
                      title: '暂无圈子通知',
                      subtitle: '点赞、评论、开播提醒会出现在这里',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: scheme.outlineVariant.withValues(alpha: 0.35)),
                  itemBuilder: (_, i) {
                    final e = _items[i];
                    final event = e.data['event'] ?? '';
                    final color = _eventColor(event);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(_eventIcon(event), color: color, size: 22),
                      ),
                      title: Text(
                        e.title,
                        style: TextStyle(fontWeight: e.read ? FontWeight.normal : FontWeight.w600),
                      ),
                      subtitle: Text(e.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: e.read ? null : Badge(smallSize: 8),
                      onTap: () => _open(e),
                    );
                  },
                ),
    );
  }
}
