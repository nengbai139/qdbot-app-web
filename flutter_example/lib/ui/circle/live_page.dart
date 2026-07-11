import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../app_theme.dart';
import 'circle_navigation.dart';
import 'circle_models.dart';
import 'live_host_page.dart';
import 'live_room_page.dart';
import 'widgets/circle_room_shell.dart';
import 'widgets/circle_ui.dart';
import 'widgets/live_backdrop.dart';

class LivePage extends StatefulWidget {
  final String token;
  final String userId;

  const LivePage({super.key, required this.token, required this.userId});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  late final CircleApi _api = CircleApi(widget.token);
  List<LiveRoom> _rooms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await _api.listLiveRooms(status: 'live');
      if (!mounted) return;
      setState(() {
        _rooms = rooms.where((r) => !r.isMeeting).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openHost() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LiveHostPage(token: widget.token, userId: widget.userId),
      ),
    );
    if (created == true) _reload();
  }

  void _watch(LiveRoom room) {
    if (!room.isLiveBroadcast) return;
    openLiveBroadcastRoom(context, token: widget.token, userId: widget.userId, room: room).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: circleSubAppBar(
        context,
        title: '直播圈',
        subtitle: '打赏 · PK · 互动直播',
        meetingMode: false,
        backgroundColor: kLiveSurface,
        foregroundColor: Colors.white,
        actions: [
          circleIconAction(icon: Icons.videocam_outlined, tooltip: '我要开播', onTap: _openHost, color: kLiveAccent),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.brandBlue,
        onRefresh: _reload,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))])
            : _error != null
                ? ListView(
                    children: [
                      CircleEmptyBox(
                        icon: Icons.cloud_off_outlined,
                        title: '加载失败',
                        subtitle: _error!,
                        actionLabel: '重试',
                        onAction: _reload,
                      ),
                    ],
                  )
                : _rooms.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                            child: Column(
                              children: [
                                CircleRoomEntryButton(
                                  meeting: false,
                                  icon: Icons.sensors,
                                  label: '我要开播',
                                  subtitle: '成为第一个开播的人',
                                  primary: true,
                                  onTap: _openHost,
                                ),
                                const SizedBox(height: 24),
                                Text('暂无进行中的直播', style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: _rooms.length + 1,
                        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : 12),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return CircleRoomEntryButton(
                              meeting: false,
                              icon: Icons.sensors,
                              label: '我要开播',
                              subtitle: '互动打赏 · PK · 福袋',
                              primary: true,
                              onTap: _openHost,
                            );
                          }
                          final room = _rooms[i - 1];
                          return _LiveRoomTile(
                            room: room,
                          onTap: () => _watch(room),
                          onHostTap: () => openUserCircleFromLiveHost(
                            context,
                            token: widget.token,
                            viewerId: widget.userId,
                            room: room,
                          ),
                        );
                        },
                      ),
      ),
    );
  }
}

class _LiveRoomTile extends StatelessWidget {
  final LiveRoom room;
  final VoidCallback onTap;
  final VoidCallback? onHostTap;

  const _LiveRoomTile({required this.room, required this.onTap, this.onHostTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: kLiveAccent.withValues(alpha: 0.2))),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (room.coverUrl.isNotEmpty)
                    LiveBackdrop(coverUrl: room.coverUrl, dimmed: false)
                  else
                    liveListCoverFallback(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                      ),
                    ),
                  ),
                  Center(child: Icon(Icons.play_arrow_rounded, size: 48, color: scheme.onSurface.withValues(alpha: 0.35))),
                  Positioned(left: 10, top: 10, child: circleLiveBadge()),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_outlined, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('进入', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onHostTap,
                    behavior: HitTestBehavior.opaque,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE5484D).withValues(alpha: 0.12),
                      backgroundImage: room.hostAvatar.isNotEmpty ? NetworkImage(room.hostAvatar) : null,
                      child: room.hostAvatar.isEmpty
                          ? Text(
                              room.hostName.isNotEmpty ? room.hostName[0] : '?',
                              style: const TextStyle(color: Color(0xFFE5484D), fontWeight: FontWeight.w600),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: onHostTap,
                          child: Text(room.hostName, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.outline),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
