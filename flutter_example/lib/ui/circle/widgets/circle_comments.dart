import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../circle_models.dart';
import 'circle_ui.dart';
import 'moment_card.dart';

enum CircleCommentAction { view, write, cancel }

Future<CircleCommentAction?> showCircleCommentActions(BuildContext context) {
  return showModalBottomSheet<CircleCommentAction>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circleSheetHandle(ctx),
              _ActionTile(
                icon: Icons.chat_bubble_outline_rounded,
                label: '写评论',
                onTap: () => Navigator.pop(ctx, CircleCommentAction.write),
              ),
              _ActionTile(
                icon: Icons.forum_outlined,
                label: '查看评论',
                onTap: () => Navigator.pop(ctx, CircleCommentAction.view),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, CircleCommentAction.cancel),
                child: Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.brandBlue),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

Future<String?> promptCircleCommentText(BuildContext context) async {
  final ctrl = TextEditingController();
  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            circleSheetHandle(ctx),
            Text('写评论', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: '说点什么…',
                filled: true,
                fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                Navigator.pop(ctx, t.isEmpty ? null : t);
              },
              child: const Text('发送'),
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  return text;
}

Future<void> showCircleCommentsSheet(BuildContext context, List<CircleComment> items) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scroll) {
        final scheme = Theme.of(ctx).colorScheme;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('评论', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${items.length} 条', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('暂无评论', style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
                      itemBuilder: (_, i) {
                        final c = items[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(c.authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  const Spacer(),
                                  Text(
                                    formatRelativeTime(c.createdAt),
                                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(c.text, style: const TextStyle(height: 1.4)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
