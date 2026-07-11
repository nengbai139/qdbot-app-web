import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/circle_api.dart';
import '../../util/media_url.dart';
import '../../util/tab_data_cache.dart';
import '../../util/video_preload.dart';
import '../../util/vod_url.dart';
import '../../util/video_viewer.dart';
import 'circle_navigation.dart';
import 'circle_models.dart';
import 'video_compose_page.dart';
import 'video_meeting_page.dart';
import 'widgets/circle_comments.dart';
import 'widgets/circle_ui.dart';
import 'widgets/circle_vod_player.dart';

class VideoPage extends StatefulWidget {
  final String token;
  final String userId;
  final String? initialPostId;

  const VideoPage({super.key, required this.token, required this.userId, this.initialPostId});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final CircleApi _api = CircleApi(widget.token);
  final _items = <CirclePost>[];
  final _pageCtrl = PageController();
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  String _cursor = '';
  bool _hasMore = false;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    TabDataCache.bindToken(widget.token);
    if (TabDataCache.hasVideoFeed) {
      _items.addAll(TabDataCache.videoFeed!);
      _cursor = TabDataCache.videoFeedCursor;
      _hasMore = TabDataCache.videoFeedHasMore;
      _loading = false;
      _reload(silent: true);
    } else {
      _reload();
    }
    _pageCtrl.addListener(_onPage);
  }

  @override
  void dispose() {
    _pageCtrl.removeListener(_onPage);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPage() {
    final page = _pageCtrl.page?.round() ?? 0;
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      _preloadAround(page);
    }
    if (!_hasMore || _loadingMore) return;
    if (page >= _items.length - 2) _loadMore();
  }

  void _preloadAround(int page) {
    for (final i in [page + 1, page - 1]) {
      if (i < 0 || i >= _items.length) continue;
      final url = _items[i].videoUrl;
      if (url.isNotEmpty && isPlayableCircleVodUrl(url)) preloadVideoUrl(url);
    }
  }

  Future<void> _reload({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (silent && _items.isNotEmpty) {
      setState(() {});
    } else if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _api.feedVideo();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
      TabDataCache.putVideoFeed(page.items, cursor: page.cursor, hasMore: page.hasMore);
      _preloadAround(_currentPage);
      if (widget.initialPostId != null && widget.initialPostId!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitialPost());
      }
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
      if (mounted && silent && _items.isNotEmpty) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.feedVideo(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
      TabDataCache.putVideoFeed(List<CirclePost>.from(_items), cursor: _cursor, hasMore: _hasMore);
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _focusInitialPost() async {
    final id = widget.initialPostId;
    if (id == null || id.isEmpty) return;
    for (var i = 0; i < 10; i++) {
      final idx = _items.indexWhere((p) => p.postId == id);
      if (idx >= 0) {
        if (!mounted) return;
        setState(() => _currentPage = idx);
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(idx);
        return;
      }
      if (!_hasMore) break;
      await _loadMore();
      if (!mounted) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未在视频圈找到该录像，请稍后在视频 Tab 查看')),
    );
  }

  Future<void> _compose() async {
    final created = await Navigator.push<CirclePost>(
      context,
      MaterialPageRoute(builder: (_) => VideoComposePage(token: widget.token, userId: widget.userId)),
    );
    if (created != null && mounted) {
      setState(() => _items.insert(0, created));
      _pageCtrl.jumpToPage(0);
      TabDataCache.putVideoFeed(List<CirclePost>.from(_items), cursor: _cursor, hasMore: _hasMore);
    }
  }

  Future<void> _openMeeting() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoMeetingPage(token: widget.token, userId: widget.userId)),
    );
  }

  Future<void> _toggleLike(int index) async {
    final post = _items[index];
    try {
      final r = await _api.toggleLike(post.postId);
      if (!mounted) return;
      setState(() {
        _items[index] = post.copyWith(likeCount: r.likeCount, liked: r.liked);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _comment(int index) async {
    final post = _items[index];
    final choice = await showCircleCommentActions(context);
    if (choice == CircleCommentAction.view) {
      try {
        final items = await _api.listComments(post.postId);
        if (!mounted) return;
        await showCircleCommentsSheet(context, items);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (choice != CircleCommentAction.write) return;
    final text = await promptCircleCommentText(context);
    if (text == null || text.isEmpty) return;
    try {
      await _api.addComment(post.postId, text);
      if (!mounted) return;
      setState(() {
        _items[index] = post.copyWith(commentCount: post.commentCount + 1);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _download(int index) async {
    final post = _items[index];
    if (post.videoUrl.isEmpty) return;
    try {
      await downloadVideo(post.videoUrl, name: post.text.isNotEmpty ? post.text : 'video.mp4');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始下载')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
    }
  }

  Future<void> _share(int index) async {
    final post = _items[index];
    final url = publicMediaUrl(post.videoUrl);
    final lines = <String>[
      if (post.text.isNotEmpty) post.text,
      if (url.isNotEmpty) url,
    ];
    if (lines.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: circleSubAppBar(
        context,
        title: '视频圈',
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : () => _reload(silent: _items.isNotEmpty),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: kMeetingAccent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: _openMeeting,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_rounded, color: kMeetingAccent, size: 18),
                      SizedBox(width: 4),
                      Text('会议', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _compose,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.add_outlined, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white54))
          else if (_error != null)
            Center(
              child: CircleEmptyBox(
                icon: Icons.cloud_off_outlined,
                title: '加载失败',
                subtitle: _error!,
                actionLabel: '重试',
                onAction: () => _reload(),
                onDark: true,
              ),
            )
          else if (_items.isEmpty)
            Center(
              child: CircleEmptyBox(
                icon: Icons.ondemand_video_outlined,
                title: '还没有视频',
                subtitle: '竖滑浏览，点右上角发布',
                actionLabel: '发视频',
                onAction: _compose,
                onDark: true,
              ),
            )
          else
            PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: _items.length,
              itemBuilder: (_, i) => _VideoSlide(
                post: _items[i],
                active: i == _currentPage,
                inRange: (i - _currentPage).abs() <= 1,
                onLike: () => _toggleLike(i),
                onComment: () => _comment(i),
                onAuthor: () => openUserCircleFromPost(
                  context,
                  token: widget.token,
                  viewerId: widget.userId,
                  post: _items[i],
                ),
                onFullscreen: () => showVideoViewer(context, _items[i].videoUrl, name: _items[i].text),
                onShare: () => _share(i),
                onDownload: () => _download(i),
                pageLabel: '${i + 1} / ${_items.length}',
              ),
            ),
          if (_refreshing && _items.isNotEmpty)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2, color: Colors.white38, backgroundColor: Colors.transparent),
            ),
        ],
      ),
    );
  }
}

class _VideoSlide extends StatefulWidget {
  final CirclePost post;
  final bool active;
  final bool inRange;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onAuthor;
  final VoidCallback onFullscreen;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final String pageLabel;

  const _VideoSlide({
    required this.post,
    required this.active,
    required this.inRange,
    required this.onLike,
    required this.onComment,
    required this.onAuthor,
    required this.onFullscreen,
    required this.onShare,
    required this.onDownload,
    required this.pageLabel,
  });

  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> with SingleTickerProviderStateMixin {
  bool _playing = true;
  bool _textExpanded = false;
  DateTime? _lastTap;
  late final AnimationController _heartCtrl;
  late final Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.15), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));
    _heartCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _heartCtrl.reverse();
    });
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_VideoSlide old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) {
      _playing = true;
      _textExpanded = false;
    }
  }

  void _burstHeart() {
    _heartCtrl.forward(from: 0);
  }

  void _onVideoTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 280)) {
      widget.onLike();
      _burstHeart();
      _lastTap = null;
      return;
    }
    _lastTap = now;
    setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasVideo = isPlayableCircleVodUrl(post.videoUrl);
    final brokenReplay = isBrokenReplayPost(text: post.text, videoUrl: post.videoUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: hasVideo && widget.inRange ? _onVideoTap : null,
          behavior: HitTestBehavior.opaque,
          child: _buildMedia(post, hasVideo, brokenReplay: brokenReplay),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
        ),
        if (hasVideo && widget.active && !_playing)
          const Center(
            child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white54),
          ),
        if (widget.active)
          IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: Tween<double>(begin: 1, end: 0).animate(_heartCtrl),
                child: ScaleTransition(
                  scale: _heartScale,
                  child: const Icon(Icons.favorite_rounded, size: 96, color: Color(0xFFE5484D)),
                ),
              ),
            ),
          ),
        if (widget.active)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
                child: Text(widget.pageLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 88,
          child: Column(
            children: [
              _SideAction(
                icon: post.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: '${post.likeCount}',
                active: post.liked,
                onTap: widget.onLike,
              ),
              const SizedBox(height: 16),
              _SideAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${post.commentCount}',
                onTap: widget.onComment,
              ),
              if (hasVideo) ...[
                const SizedBox(height: 16),
                _SideAction(
                  icon: Icons.share_rounded,
                  label: '分享',
                  onTap: widget.onShare,
                ),
                const SizedBox(height: 16),
                _SideAction(
                  icon: Icons.download_rounded,
                  label: '下载',
                  onTap: widget.onDownload,
                ),
                const SizedBox(height: 16),
                _SideAction(
                  icon: Icons.fullscreen_rounded,
                  label: '全屏',
                  onTap: widget.onFullscreen,
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 72,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: widget.onAuthor,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      backgroundImage: post.authorAvatar.isNotEmpty ? NetworkImage(post.authorAvatar) : null,
                      child: post.authorAvatar.isEmpty
                          ? Text(
                              post.authorDisplay.isNotEmpty ? post.authorDisplay[0] : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.authorDisplay,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _textExpanded = !_textExpanded),
                    child: Text(
                      post.text,
                      maxLines: _textExpanded ? null : 2,
                      overflow: _textExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedia(CirclePost post, bool hasVideo, {bool brokenReplay = false}) {
    if (!widget.inRange) {
      if (post.posterUrl.isNotEmpty) {
        return Image.network(post.posterUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _VideoPlaceholder());
      }
      return brokenReplay ? const _ReplayUnavailable() : const _VideoPlaceholder();
    }
    if (hasVideo) {
      return CircleVodPlayer(
        key: ValueKey(post.videoUrl),
        url: post.videoUrl,
        posterUrl: post.posterUrl,
        active: widget.active,
        playing: _playing,
      );
    }
    if (post.posterUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            post.posterUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => brokenReplay ? const _ReplayUnavailable() : const _VideoPlaceholder(),
          ),
          if (brokenReplay) const _ReplayUnavailable(overlay: true),
        ],
      );
    }
    return brokenReplay ? const _ReplayUnavailable() : const _VideoPlaceholder();
  }
}

class _ReplayUnavailable extends StatelessWidget {
  final bool overlay;
  const _ReplayUnavailable({this.overlay = false});

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_rounded, size: overlay ? 40 : 48, color: Colors.white38),
        const SizedBox(height: 8),
        Text(
          '回放暂不可用',
          style: TextStyle(color: Colors.white.withValues(alpha: overlay ? 0.9 : 0.7), fontSize: overlay ? 14 : 15, fontWeight: FontWeight.w500),
        ),
        if (!overlay)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('该场次未成功录制', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          ),
      ],
    );
    if (overlay) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(child: child),
      );
    }
    return ColoredBox(
      color: const Color(0xFF1A1A1A),
      child: Center(child: child),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1A1A1A),
      child: Center(
        child: Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white24),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
            child: Icon(icon, color: active ? const Color(0xFFE5484D) : Colors.white, size: 26),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
