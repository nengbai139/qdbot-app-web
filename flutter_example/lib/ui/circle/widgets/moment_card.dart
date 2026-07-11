import 'package:flutter/material.dart';

import '../../im_media.dart';
import '../circle_models.dart';
import 'circle_ui.dart';

/// 微信链接色
const kWxLinkBlue = Color(0xFF576B95);

class MomentCard extends StatelessWidget {
  final CirclePost post;
  final List<CircleComment> comments;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onDelete;
  final String? viewerId;

  const MomentCard({
    super.key,
    required this.post,
    this.comments = const [],
    this.onLike,
    this.onComment,
    this.onAuthorTap,
    this.onDelete,
    this.viewerId,
  });

  bool get _isOwner => viewerId != null && post.isOwnedBy(viewerId!);

  Future<void> _showWxActions(BuildContext context, TapDownDetails details) async {
    final showLike = onLike != null;
    final showComment = onComment != null;
    final showDelete = onDelete != null;
    if (!showLike && !showComment && !showDelete) return;

    final pos = details.globalPosition;
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) {
        const bubbleH = 44.0;
        final left = (pos.dx - 220).clamp(8.0, MediaQuery.sizeOf(ctx).width - 228);
        final top = (pos.dy - bubbleH - 10).clamp(MediaQuery.paddingOf(ctx).top + 8, pos.dy - bubbleH);
        return Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(ctx))),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: const Color(0xFF4C4C4C),
                borderRadius: BorderRadius.circular(6),
                elevation: 6,
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showLike)
                        _WxActionChip(
                          icon: post.liked ? Icons.favorite : Icons.favorite_border,
                          label: post.liked ? '取消' : '赞',
                          onTap: () => Navigator.pop(ctx, 'like'),
                        ),
                      if (showLike && (showComment || showDelete))
                        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF666666)),
                      if (showComment)
                        _WxActionChip(
                          icon: Icons.chat_bubble_outline,
                          label: '评论',
                          onTap: () => Navigator.pop(ctx, 'comment'),
                        ),
                      if (showDelete && showComment)
                        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF666666)),
                      if (showDelete)
                        _WxActionChip(
                          icon: Icons.delete_outline,
                          label: '删除',
                          muted: true,
                          onTap: () => Navigator.pop(ctx, 'delete'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    switch (action) {
      case 'like':
        onLike?.call();
      case 'comment':
        onComment?.call();
      case 'delete':
        onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _WxAvatar(name: post.authorDisplay, url: post.authorAvatar, size: 42),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onAuthorTap,
                  child: Text(
                    post.authorDisplay,
                    style: const TextStyle(color: kWxLinkBlue, fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
                if (post.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(post.text, style: TextStyle(fontSize: 15, height: 1.45, color: scheme.onSurface)),
                ],
                if (post.images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _WxImageGrid(urls: post.images),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            formatRelativeTime(post.createdAt),
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.85)),
                          ),
                          if (_isOwner && post.visibility != 'friends') ...[
                            const SizedBox(width: 6),
                            Text(
                              circleVisibilityLabel(post.visibility),
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onLike != null || onComment != null || onDelete != null)
                      GestureDetector(
                        onTapDown: (d) => _showWxActions(context, d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(Icons.more_horiz, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                        ),
                      ),
                  ],
                ),
                if (post.likeCount > 0 || comments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _WxInteractionBox(post: post, comments: comments),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WxAvatar extends StatelessWidget {
  final String name;
  final String url;
  final double size;

  const _WxAvatar({required this.name, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return Image.network(url, width: size, height: size, fit: BoxFit.cover);
    }
    return Container(
      width: size,
      height: size,
      color: kWxLinkBlue.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0] : '?',
        style: const TextStyle(color: kWxLinkBlue, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _WxInteractionBox extends StatelessWidget {
  final CirclePost post;
  final List<CircleComment> comments;

  const _WxInteractionBox({required this.post, required this.comments});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.likeCount > 0)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.favorite, size: 14, color: kWxLinkBlue.withValues(alpha: 0.9)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    post.liked && post.likeCount == 1
                        ? '你觉得很赞'
                        : post.liked
                            ? '你和其他 ${post.likeCount - 1} 人觉得很赞'
                            : '${post.likeCount} 人觉得很赞',
                    style: const TextStyle(fontSize: 13, color: kWxLinkBlue, height: 1.35),
                  ),
                ),
              ],
            ),
          if (post.likeCount > 0 && comments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.08)),
            ),
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurface),
                  children: [
                    TextSpan(
                      text: '${c.authorName}：',
                      style: const TextStyle(color: kWxLinkBlue, fontWeight: FontWeight.w500),
                    ),
                    TextSpan(text: c.text),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WxActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  const _WxActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? Colors.white70 : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _WxImageGrid extends StatelessWidget {
  final List<String> urls;

  const _WxImageGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    final list = urls.take(9).toList();
    if (list.length == 1) {
      return GestureDetector(
        onTap: () => showImageViewer(context, list.first, urls: list),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
            child: Image.network(list.first, fit: BoxFit.cover),
          ),
        ),
      );
    }
    const gap = 4.0;
    const cell = 88.0;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: list.asMap().entries.map((e) {
        final i = e.key;
        final u = e.value;
        return GestureDetector(
          onTap: () => showImageViewer(context, u, urls: list, initialIndex: i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(u, width: cell, height: cell, fit: BoxFit.cover),
          ),
        );
      }).toList(),
    );
  }
}

String formatRelativeTime(String iso) {
  if (iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}月${dt.day}日';
  } catch (_) {
    return iso;
  }
}
