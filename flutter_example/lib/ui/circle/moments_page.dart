import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../../api/user_api.dart';
import '../app_theme.dart';
import 'circle_navigation.dart';
import 'circle_models.dart';
import 'moment_compose_page.dart';
import 'widgets/circle_comments.dart';
import 'widgets/circle_ui.dart';
import 'widgets/moment_feed_tile.dart';
import 'widgets/moments_wx_header.dart';

class MomentsPage extends StatefulWidget {
  final String token;
  final String userId;

  const MomentsPage({super.key, required this.token, required this.userId});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  late final CircleApi _api = CircleApi(widget.token);
  late final UserApi _userApi = UserApi(widget.token);
  final _items = <CirclePost>[];
  UserProfile? _profile;
  bool _loading = true;
  bool _loadingMore = false;
  String _cursor = '';
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _reload();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _userApi.getProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.feedMoments();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
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

  Future<void> _refreshAll() async {
    await Future.wait([_reload(), _loadProfile()]);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.feedMoments(cursor: _cursor);
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

  Future<void> _compose() async {
    final created = await Navigator.push<CirclePost>(
      context,
      MaterialPageRoute(
        builder: (_) => MomentComposePage(token: widget.token, userId: widget.userId),
      ),
    );
    if (created != null && mounted) {
      setState(() => _items.insert(0, created));
    }
  }

  CirclePost _copyPost(CirclePost post, {int? likeCount, int? commentCount, bool? liked}) {
    return CirclePost(
      postId: post.postId,
      authorId: post.authorId,
      authorName: post.authorName,
      authorCode: post.authorCode,
      authorEmail: post.authorEmail,
      authorAvatar: post.authorAvatar,
      text: post.text,
      images: post.images,
      likeCount: likeCount ?? post.likeCount,
      commentCount: commentCount ?? post.commentCount,
      liked: liked ?? post.liked,
      visibility: post.visibility,
      createdAt: post.createdAt,
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

  void _openAuthor(CirclePost post) {
    openUserCircleFromPost(
      context,
      token: widget.token,
      viewerId: widget.userId,
      post: post,
    );
  }

  bool _isMyPost(CirclePost post) => post.isOwnedBy(widget.userId, altViewerId: _profile?.userId);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: AppTheme.brandBlue,
        onRefresh: _refreshAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: MomentsWxHeader(
                profile: _profile,
                onCompose: _compose,
                onBack: Navigator.canPop(context) ? () => Navigator.pop(context) : null,
              ),
            ),
            if (_loading)
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
                  onAction: _reload,
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: CircleEmptyBox(
                  icon: Icons.photo_library_outlined,
                  title: '还没有动态',
                  subtitle: '点击右上角相机，发第一条朋友圈',
                  actionLabel: '去发表',
                  onAction: _compose,
                ),
              )
            else ...[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i >= _items.length) {
                      _loadMore();
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final post = _items[i];
                    return Column(
                      children: [
                        if (i > 0) circleFeedDivider(context),
                        MomentFeedTile(
                          post: post,
                          viewerId: widget.userId,
                          api: _api,
                          onDelete: _isMyPost(post) ? () => _deletePost(i) : null,
                          onLike: () => _toggleLike(i),
                          onComment: () => _comment(i),
                          onAuthorTap: () => _openAuthor(post),
                        ),
                      ],
                    );
                  },
                  childCount: _items.length + (_hasMore ? 1 : 0),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }
}
