import 'package:flutter/material.dart';

import '../circle_navigation.dart';
import '../circle_models.dart';
import 'circle_ui.dart';

/// 圈子 Tab 进行中的会议（与直播横条分开展示）
class CircleMeetingStrip extends StatelessWidget {
  final List<LiveRoom> rooms;
  final String token;
  final String userId;
  final VoidCallback? onViewAll;

  const CircleMeetingStrip({
    super.key,
    required this.rooms,
    required this.token,
    required this.userId,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final meetings = rooms.where((r) => r.meetingJoinable).toList();
    if (meetings.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              circleMeetingBadge(compact: true),
              const SizedBox(width: 8),
              Text('进行中的会议', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: kMeetingAccent,
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
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final r = meetings[i];
              return _MeetingChip(
                room: r,
                onTap: () => openMeetingRoom(context, token: token, userId: userId, room: r),
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

class _MeetingChip extends StatelessWidget {
  final LiveRoom room;
  final VoidCallback onTap;

  const _MeetingChip({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kMeetingAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 148,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups_rounded, size: 14, color: kMeetingAccent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        room.title.isNotEmpty ? room.title : '会议',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '主持人 ${room.hostName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Text(
                  room.roomId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: kMeetingAccent.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
