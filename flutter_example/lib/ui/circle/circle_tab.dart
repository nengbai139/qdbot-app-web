import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../../util/tab_data_cache.dart';
import '../app_theme.dart';
import 'circle_models.dart';
import 'circle_navigation.dart';
import 'moment_detail_page.dart';
import 'moments_page.dart';
import 'video_page.dart';
import 'live_page.dart';
import 'widgets/circle_entry_grid.dart';
import 'widgets/circle_live_strip.dart';
import 'widgets/circle_meeting_strip.dart';
import 'video_meeting_page.dart';
import 'widgets/circle_video_strip.dart';
import 'widgets/circle_ui.dart';
import 'widgets/moment_card.dart';

class CircleTab extends StatefulWidget {
  final String token;
  final String userId;

  const CircleTab({super.key, required this.token, required this.userId});

  @override
  State<CircleTab> createState() => CircleTabState();
}

class CircleTabState extends State<CircleTab> with AutomaticKeepAliveClientMixin {
  late final CircleApi _api = CircleApi(widget.token);
  List<CirclePost> _preview = [];
  List<CirclePost> _videoPreview = [];
  List<LiveRoom> _liveRooms = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshDebounce;
  bool _refreshing = false;
  DateTime? _lastFetch;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    TabDataCache.bindToken(widget.token);
    if (TabDataCache.hasCircle) {
      _preview = List<CirclePost>.from(TabDataCache.circlePreview ?? const []);
      _liveRooms = List<LiveRoom>.from(TabDataCache.liveRooms ?? const []);
      _videoPreview = List<CirclePost>.from((TabDataCache.videoFeed ?? const <CirclePost>[]).take(8));
      _loading = false;
      _lastFetch = DateTime.now();
      refresh(silent: true);
    } else {
      refresh();
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) refresh(silent: _preview.isNotEmpty);
    });
  }

  void refreshIfStale({Duration maxAge = const Duration(seconds: 30)}) {
    final now = DateTime.now();
    if (_lastFetch != null && now.difference(_lastFetch!) < maxAge) return;
    refresh(silent: _preview.isNotEmpty || _liveRooms.isNotEmpty);
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        _api.feedMoments(limit: 5),
        _api.listLiveRooms(status: 'live', limit: 8),
      ]);
      if (!mounted) return;
      final preview = (results[0] as CircleFeedPage).items;
      final rooms = results[1] as List<LiveRoom>;
      TabDataCache.putCirclePreview(preview);
      TabDataCache.putLiveRooms(rooms);
      setState(() {
        _preview = preview;
        _liveRooms = rooms;
        _loading = false;
        _error = null;
      });
      _lastFetch = DateTime.now();
      _prefetchVideoFeed();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent || _preview.isEmpty) _error = '$e';
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  void _openKind(CircleKind kind) {
    if (!kind.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${kind.label} 即将开放')));
      return;
    }
    if (kind == CircleKind.video && !TabDataCache.hasVideoFeed) {
      _prefetchVideoFeed();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => switch (kind) {
          CircleKind.video => VideoPage(token: widget.token, userId: widget.userId),
          CircleKind.live => LivePage(token: widget.token, userId: widget.userId),
          _ => MomentsPage(token: widget.token, userId: widget.userId),
        },
      ),
    ).then((_) => refresh());
  }

  Future<void> _prefetchVideoFeed() async {
    if (TabDataCache.hasVideoFeed) {
      if (mounted && _videoPreview.isEmpty) {
        setState(() => _videoPreview = List<CirclePost>.from(TabDataCache.videoFeed!.take(8)));
      }
      return;
    }
    try {
      final page = await _api.feedVideo(limit: 8);
      TabDataCache.bindToken(widget.token);
      TabDataCache.putVideoFeed(page.items, cursor: page.cursor, hasMore: page.hasMore);
      if (!mounted) return;
      setState(() => _videoPreview = page.items);
    } catch (_) {}
  }

  void openLiveRoom(String roomId) {
    openCircleRoomById(context, token: widget.token, userId: widget.userId, roomId: roomId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.brandBlue,
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '圈子',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '动态 · 视频 · 直播',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: AppTheme.brandBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _openKind(CircleKind.moments),
                          borderRadius: BorderRadius.circular(14),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.edit_outlined, color: AppTheme.brandBlue, size: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: CircleEntryGrid(onTap: _openKind)),
            SliverToBoxAdapter(
              child: CircleLiveStrip(
                rooms: _liveRooms,
                token: widget.token,
                userId: widget.userId,
                onViewAll: () => _openKind(CircleKind.live),
              ),
            ),
            SliverToBoxAdapter(
              child: CircleMeetingStrip(
                rooms: _liveRooms,
                token: widget.token,
                userId: widget.userId,
                onViewAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoMeetingPage(token: widget.token, userId: widget.userId),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CircleVideoStrip(
                items: _videoPreview,
                token: widget.token,
                userId: widget.userId,
                onViewAll: () => _openKind(CircleKind.video),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Text(
                      '最新动态',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _openKind(CircleKind.moments),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.brandBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('查看全部'),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading && _preview.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: CircleEmptyBox(
                  icon: Icons.cloud_off_outlined,
                  title: '加载失败',
                  subtitle: _error!,
                  actionLabel: '重试',
                  onAction: refresh,
                ),
              )
            else if (_preview.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: CircleEmptyBox(
                  icon: Icons.photo_library_outlined,
                  title: '还没有动态',
                  subtitle: '去朋友圈发布第一条吧',
                  actionLabel: '发朋友圈',
                  onAction: () => _openKind(CircleKind.moments),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i.isOdd) return circleFeedDivider(context);
                    final post = _preview[i ~/ 2];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MomentDetailPage(
                            token: widget.token,
                            userId: widget.userId,
                            post: post,
                          ),
                        ),
                      ).then((_) => refresh()),
                      child: MomentCard(
                        post: post,
                        onAuthorTap: () => openUserCircleFromPost(
                          context,
                          token: widget.token,
                          viewerId: widget.userId,
                          post: post,
                        ),
                      ),
                    );
                  },
                  childCount: _preview.length * 2 - 1,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
