import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import 'circle_navigation.dart';
import 'circle_models.dart';
import 'widgets/circle_comments.dart';
import 'widgets/circle_ui.dart';
import 'widgets/moment_card.dart';

class MomentDetailPage extends StatefulWidget {
  final String token;
  final String userId;
  final CirclePost post;

  const MomentDetailPage({
    super.key,
    required this.token,
    required this.userId,
    required this.post,
  });

  @override
  State<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends State<MomentDetailPage> {
  late final CircleApi _api = CircleApi(widget.token);
  late CirclePost _post;
  List<CircleComment> _comments = const [];

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
  }

  Future<void> _loadComments() async {
    if (_post.commentCount <= 0) {
      if (mounted) setState(() => _comments = const []);
      return;
    }
    try {
      final items = await _api.listComments(_post.postId);
      if (mounted) setState(() => _comments = items);
    } catch (_) {}
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

  Future<void> _toggleLike() async {
    try {
      final r = await _api.toggleLike(_post.postId);
      if (!mounted) return;
      setState(() => _post = _copyPost(_post, likeCount: r.likeCount, liked: r.liked));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _comment() async {
    final text = await promptCircleCommentText(context);
    if (text == null || text.isEmpty) return;
    try {
      await _api.addComment(_post.postId, text);
      if (!mounted) return;
      setState(() => _post = _copyPost(_post, commentCount: _post.commentCount + 1));
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openAuthor() {
    openUserCircleFromPost(
      context,
      token: widget.token,
      viewerId: widget.userId,
      post: _post,
    );
  }

  Future<void> _deletePost() async {
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
      await _api.deletePost(_post.postId);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = _post.isOwnedBy(widget.userId);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: circleSubAppBar(context, title: '详情'),
      body: ListView(
        children: [
          MomentCard(
            post: _post,
            comments: _comments,
            viewerId: widget.userId,
            onDelete: isOwner ? _deletePost : null,
            onLike: _toggleLike,
            onComment: _comment,
            onAuthorTap: _openAuthor,
          ),
        ],
      ),
    );
  }
}
