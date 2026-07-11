import 'package:flutter/material.dart';

import '../circle_models.dart';
import '../video_page.dart';
import 'circle_ui.dart';

class CircleVideoStrip extends StatelessWidget {
  final List<CirclePost> items;
  final String token;
  final String userId;
  final VoidCallback? onViewAll;

  const CircleVideoStrip({
    super.key,
    required this.items,
    required this.token,
    required this.userId,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.ondemand_video_rounded, size: 18, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Text('热门视频', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('全部'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _VideoChip(
              post: items[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VideoPage(token: token, userId: userId)),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ],
    );
  }
}

class _VideoChip extends StatelessWidget {
  final CirclePost post;
  final VoidCallback onTap;

  const _VideoChip({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = post.posterUrl.isNotEmpty ? post.posterUrl : null;
    return Material(
      color: const Color(0xFF6366F1).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 108,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null)
                Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _ThumbFallback())
              else
                const _ThumbFallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
              const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 36)),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  post.text.isNotEmpty ? post.text : post.authorDisplay,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2A2A35),
      child: Center(child: Icon(Icons.videocam_outlined, color: Colors.white24, size: 28)),
    );
  }
}
