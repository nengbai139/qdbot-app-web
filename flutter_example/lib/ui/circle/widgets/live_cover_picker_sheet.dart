import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../live_cover_presets.dart';
import 'live_backdrop.dart';

/// 选择/更换直播背景墙（准备页与演播室共用）
Future<String?> showLiveCoverPickerSheet(
  BuildContext context, {
  required String currentUrl,
  bool studio = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: studio ? const Color(0xFF1A1A22) : null,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final title = studio ? '更换背景墙' : '选择直播背景';
      final hint = studio
          ? '观众在等待推流或画面加载时将看到此背景'
          : '等待推流时，观众将看到此背景';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: studio ? Colors.white : null),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(fontSize: 12, color: studio ? Colors.white54 : scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                ),
                itemCount: liveCoverPresets.length,
                itemBuilder: (_, i) {
                  final p = liveCoverPresets[i];
                  final selected = currentUrl == p.url;
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, p.url),
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(p.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => liveListCoverFallback()),
                                if (selected)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppTheme.brandBlue, width: 3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: studio ? Colors.white70 : null,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, '__upload__'),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册上传'),
                style: studio
                    ? OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24))
                    : null,
              ),
            ],
          ),
        ),
      );
    },
  );
}
