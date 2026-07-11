import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../circle_navigation.dart';
import '../circle_navigation.dart';
import '../circle_models.dart';
import '../live_room_page.dart';
import 'circle_ui.dart';

class CircleLiveStrip extends StatelessWidget {
  final List<LiveRoom> rooms;
  final String token;
  final String userId;
  final VoidCallback? onViewAll;

  const CircleLiveStrip({
    super.key,
    required this.rooms,
    required this.token,
    required this.userId,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final liveOnly = rooms.where((r) => !r.isMeeting).toList();
    if (liveOnly.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              circleLiveBadge(compact: true),
              const SizedBox(width: 8),
              const Icon(Icons.live_tv_rounded, size: 18, color: kLiveAccent),
              const SizedBox(width: 6),
              Text('正在直播', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: kLiveAccent,
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
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: liveOnly.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final r = liveOnly[i];
              return _LiveChip(
                room: r,
                onTap: () => openLiveBroadcastRoom(context, token: token, userId: userId, room: r),
                onHostTap: () => openUserCircleFromLiveHost(
                  context,
                  token: token,
                  viewerId: userId,
                  room: r,
                ),
              );
            },
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

class _LiveChip extends StatelessWidget {
  final LiveRoom room;
  final VoidCallback onTap;
  final VoidCallback? onHostTap;

  const _LiveChip({required this.room, required this.onTap, this.onHostTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kLiveAccent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    circleLiveBadge(compact: true),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        room.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onHostTap,
                  child: Text(
                    room.hostName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
