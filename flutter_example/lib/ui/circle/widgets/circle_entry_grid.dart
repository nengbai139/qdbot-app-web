import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../circle_models.dart';

class CircleEntryGrid extends StatelessWidget {
  final void Function(CircleKind kind) onTap;

  const CircleEntryGrid({super.key, required this.onTap});

  static const _mainKinds = [CircleKind.moments, CircleKind.video, CircleKind.live];
  static const _soonKinds = [CircleKind.shop, CircleKind.game];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < _mainKinds.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _MainEntry(kind: _mainKinds[i], onTap: () => onTap(_mainKinds[i]))),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _soonKinds.map((k) => _SoonChip(kind: k, onTap: () => onTap(k))).toList(),
          ),
          const SizedBox(height: 4),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}

class _MainEntry extends StatelessWidget {
  final CircleKind kind;
  final VoidCallback onTap;

  const _MainEntry({required this.kind, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      CircleKind.moments => (AppTheme.brandBlue.withValues(alpha: 0.08), AppTheme.brandBlue),
      CircleKind.video => (const Color(0xFF6366F1).withValues(alpha: 0.08), const Color(0xFF6366F1)),
      CircleKind.live => (const Color(0xFFE5484D).withValues(alpha: 0.08), const Color(0xFFE5484D)),
      _ => (Colors.grey.shade100, Colors.grey.shade600),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Icon(kind.icon, size: 26, color: fg),
              const SizedBox(height: 8),
              Text(
                kind.label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  final CircleKind kind;
  final VoidCallback onTap;

  const _SoonChip({required this.kind, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kind.icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(kind.label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 4),
              Text('敬请期待', style: TextStyle(fontSize: 10, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
