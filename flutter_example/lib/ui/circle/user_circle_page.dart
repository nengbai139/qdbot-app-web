import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../app_theme.dart';
import '../chat_page.dart';
import '../premium/user_code_display.dart';
import '../../util/video_viewer.dart';
import 'circle_models.dart';
import 'moment_detail_page.dart';
import 'widgets/circle_comments.dart';
import 'widgets/circle_ui.dart';
import 'widgets/moment_card.dart';

class UserCirclePage extends StatefulWidget {
  final String token;
  final String viewerId;
  final String authorId;
  final String authorName;
  final String authorCode;
  final String authorEmail;
  final String authorAvatar;

  const UserCirclePage({
    super.key,
    required this.token,
    required this.viewerId,
    required this.authorId,
    this.authorName = '',
    this.authorCode = '',
    this.authorEmail = '',
    this.authorAvatar = '',
  });

  @override
  State<UserCirclePage> createState() => _UserCirclePageState();
}

class _UserCirclePageState extends State<UserCirclePage> {
  late final CircleApi _api = CircleApi(widget.token);
  final _items = <CirclePost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _following = false;
  bool _isSelf = false;
  String _cursor = '';
  bool _hasMore = false;
  String? _error;

  String get _displayName {
    if (widget.authorName.isNotEmpty && widget.authorName != widget.authorId) return widget.authorName;
    if (widget.authorCode.isNotEmpty && widget.authorCode != widget.authorId) return widget.authorCode;
    if (widget.authorEmail.isNotEmpty) return widget.authorEmail;
    return widget.authorId;
  }

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
      final page = await _api.userPosts(widget.authorId);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _following = page.following;
        _isSelf = page.isSelf;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.userPosts(widget.authorId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow() async {
    try {
      if (_following) {
        await _api.unfollow(widget.authorId);
      } else {
        await _api.follow(widget.authorId);
      }
      if (!mounted) return;
      setState(() => _following = !_following);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          token: widget.token,
          userId: widget.viewerId,
          peerId: widget.authorId,
          peerName: _displayName,
          peerUserCode: widget.authorCode,
        ),
      ),
    );
  }

  Future<void> _toggleLike(int index) async {
    final post = _items[index];
    try {
      final r = await _api.toggleLike(post.postId);
      if (!mounted) return;
      setState(() => _items[index] = _copyPost(post, likeCount: r.likeCount, liked: r.liked));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _comment(int index) async {
    final post = _items[index];
    final text = await promptCircleCommentText(context);
    if (text == null || text.isEmpty) return;
    try {
      await _api.addComment(post.postId, text);
      if (!mounted) return;
      setState(() => _items[index] = _copyPost(post, commentCount: post.commentCount + 1));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  CirclePost _copyPost(CirclePost post, {int? likeCount, int? commentCount, bool? liked}) => CirclePost(
        postId: post.postId,
        authorId: post.authorId,
        authorName: post.authorName,
        authorCode: post.authorCode,
        authorEmail: post.authorEmail,
        authorAvatar: post.authorAvatar,
        text: post.text,
        images: post.images,
        videoUrl: post.videoUrl,
        posterUrl: post.posterUrl,
        circleType: post.circleType,
        likeCount: likeCount ?? post.likeCount,
        commentCount: commentCount ?? post.commentCount,
        liked: liked ?? post.liked,
        visibility: post.visibility,
        createdAt: post.createdAt,
      );

  void _openPost(int index) {
    final post = _items[index];
    if (post.circleType == 'video' && post.videoUrl.isNotEmpty) {
      showVideoViewer(context, post.videoUrl, name: post.text);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MomentDetailPage(token: widget.token, userId: widget.viewerId, post: post),
      ),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _deletePost(int index) async {
    final post = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('删除后无法恢复，确定删除这条朋友圈吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deletePost(post.postId);
      if (!mounted) return;
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  Widget _buildPost(int index) {
    final post = _items[index];
    if (post.circleType == 'video') {
      return _VideoRow(
        post: post,
        onTap: () => _openPost(index),
        onLike: () => _toggleLike(index),
        onComment: () => _comment(index),
      );
    }
    return GestureDetector(
      onTap: () => _openPost(index),
      child: MomentCard(
        post: post,
        viewerId: widget.viewerId,
        onLike: () => _toggleLike(index),
        onComment: () => _comment(index),
        onDelete: _isSelf ? () => _deletePost(index) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: circleSubAppBar(
        context,
        title: _isSelf ? '我的圈子' : 'TA 的圈子',
        subtitle: _displayName,
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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: AppTheme.brandBlue.withValues(alpha: 0.12),
                                backgroundImage: widget.authorAvatar.isNotEmpty ? NetworkImage(widget.authorAvatar) : null,
                                child: widget.authorAvatar.isEmpty
                                    ? Text(
                                        _displayName.isNotEmpty ? _displayName[0] : '?',
                                        style: const TextStyle(color: AppTheme.brandBlue, fontWeight: FontWeight.w700, fontSize: 28),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              Text(_displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                              if (widget.authorCode.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                UserCodeRow(userCode: widget.authorCode),
                              ],
                              if (!_isSelf) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _openChat,
                                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                        label: const Text('发消息'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _toggleFollow,
                                        icon: Icon(_following ? Icons.check_rounded : Icons.person_add_outlined, size: 18),
                                        label: Text(_following ? '已关注' : '关注'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_items.isEmpty)
                        CircleEmptyBox(
                          icon: Icons.photo_library_outlined,
                          title: _isSelf ? '还没有发布内容' : '暂无可见动态',
                          subtitle: _isSelf ? '去朋友圈或视频圈发布吧' : '可能设置了仅好友可见，关注后可查看更多',
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text('全部动态', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        for (var i = 0; i < _items.length; i++) ...[
                          if (i > 0) circleFeedDivider(context),
                          _buildPost(i),
                        ],
                        if (_hasMore) ...[
                          circleFeedDivider(context),
                          Builder(
                            builder: (_) {
                              _loadMore();
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _VideoRow extends StatelessWidget {
  final CirclePost post;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _VideoRow({
    required this.post,
    required this.onTap,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final poster = post.posterUrl.isNotEmpty ? post.posterUrl : post.videoUrl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.network(poster, width: 120, height: 68, fit: BoxFit.cover),
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x44000000),
                        child: Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 32)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.text.isNotEmpty ? post.text : '视频',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(formatRelativeTime(post.createdAt), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        InkWell(
                          onTap: onLike,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  post.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  size: 16,
                                  color: post.liked ? const Color(0xFFE5484D) : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text('${post.likeCount}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: onComment,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text('${post.commentCount}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
