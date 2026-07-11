import 'package:flutter/material.dart';

import '../../../api/circle_api.dart';
import '../circle_models.dart';
import 'moment_card.dart';

/// 单条朋友圈：按需拉评论，供列表内联展示（微信式灰框）
class MomentFeedTile extends StatefulWidget {
  final CirclePost post;
  final String viewerId;
  final CircleApi api;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onDelete;
  final ValueChanged<CirclePost>? onPostUpdated;

  const MomentFeedTile({
    super.key,
    required this.post,
    required this.viewerId,
    required this.api,
    this.onLike,
    this.onComment,
    this.onAuthorTap,
    this.onDelete,
    this.onPostUpdated,
  });

  @override
  State<MomentFeedTile> createState() => _MomentFeedTileState();
}

class _MomentFeedTileState extends State<MomentFeedTile> {
  List<CircleComment>? _comments;
  bool _loadingComments = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadComments();
  }

  @override
  void didUpdateWidget(covariant MomentFeedTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.commentCount != widget.post.commentCount) {
      _comments = null;
      _maybeLoadComments();
    }
  }

  Future<void> _maybeLoadComments() async {
    if (widget.post.commentCount <= 0 || _comments != null || _loadingComments) return;
    _loadingComments = true;
    try {
      final items = await widget.api.listComments(widget.post.postId);
      if (mounted) setState(() => _comments = items);
    } catch (_) {
    } finally {
      _loadingComments = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MomentCard(
      post: widget.post,
      comments: _comments ?? const [],
      viewerId: widget.viewerId,
      onAuthorTap: widget.onAuthorTap,
      onDelete: widget.onDelete,
      onLike: widget.onLike,
      onComment: widget.onComment,
    );
  }
}
