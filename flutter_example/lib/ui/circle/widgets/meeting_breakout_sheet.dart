import 'package:flutter/material.dart';

import '../circle_models.dart';
import 'circle_ui.dart';

/// ponytail: 主持拖拽分配分组；返回 userId -> 组号(1..count)
Future<({int count, Map<String, int> assignments})?> showMeetingBreakoutPlanner({
  required BuildContext context,
  required List<LiveParticipant> participants,
  required String hostId,
  bool editing = false,
  int initialCount = 3,
  Map<String, int>? initialAssignments,
}) {
  return showModalBottomSheet<({int count, Map<String, int> assignments})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kMeetingSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _BreakoutPlannerSheet(
      participants: participants,
      hostId: hostId,
      editing: editing,
      initialCount: initialCount,
      initialAssignments: initialAssignments,
    ),
  );
}

class _BreakoutPlannerSheet extends StatefulWidget {
  final List<LiveParticipant> participants;
  final String hostId;
  final bool editing;
  final int initialCount;
  final Map<String, int>? initialAssignments;

  const _BreakoutPlannerSheet({
    required this.participants,
    required this.hostId,
    required this.editing,
    required this.initialCount,
    this.initialAssignments,
  });

  @override
  State<_BreakoutPlannerSheet> createState() => _BreakoutPlannerSheetState();
}

class _BreakoutPlannerSheetState extends State<_BreakoutPlannerSheet> {
  late int _count = widget.initialCount.clamp(2, 4);
  late final Map<String, int> _assign = {};

  List<LiveParticipant> get _assignable =>
      widget.participants.where((p) => p.userId != widget.hostId && p.userId.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _seedAssignments();
  }

  void _seedAssignments() {
    _assign.clear();
    if (widget.initialAssignments != null && widget.initialAssignments!.isNotEmpty) {
      _assign.addAll(widget.initialAssignments!);
      return;
    }
    var i = 0;
    for (final p in _assignable) {
      _assign[p.userId] = i % _count + 1;
      i++;
    }
  }

  void _setCount(int n) {
    setState(() {
      _count = n;
      for (final p in _assignable) {
        final g = _assign[p.userId] ?? 1;
        _assign[p.userId] = ((g - 1) % _count) + 1;
      }
    });
  }

  void _moveUser(String userId, int group) {
    setState(() => _assign[userId] = group.clamp(1, _count));
  }

  List<String> _usersInGroup(int group) {
    return _assignable.where((p) => (_assign[p.userId] ?? 0) == group).map((p) => p.userId).toList();
  }

  LiveParticipant? _find(String id) {
    for (final p in _assignable) {
      if (p.userId == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.editing ? '调整分组' : '分组讨论',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Text('拖拽成员到各讨论组', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          if (!widget.editing)
            Row(
              children: [2, 3, 4].map((n) {
                final sel = _count == n;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$n 组'),
                    selected: sel,
                    onSelected: (_) => _setCount(n),
                    selectedColor: kMeetingAccent.withValues(alpha: 0.35),
                    labelStyle: TextStyle(color: sel ? Colors.white : Colors.white70),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var g = 1; g <= _count; g++) _groupColumn(g),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, (count: _count, assignments: Map<String, int>.from(_assign))),
            child: Text(widget.editing ? '保存调整' : '开始分组'),
          ),
        ],
      ),
    );
  }

  Widget _groupColumn(int group) {
    final ids = _usersInGroup(group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _moveUser(d.data, group),
        builder: (ctx, candidate, _) {
          final highlight = candidate.isNotEmpty;
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlight ? kMeetingAccent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: highlight ? kMeetingAccent : Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('讨论组 $group', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in ids) _userChip(id),
                    if (ids.isEmpty)
                      Text('拖入参会者', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _userChip(String userId) {
    final p = _find(userId);
    final name = p?.userName ?? userId;
    return LongPressDraggable<String>(
      data: userId,
      feedback: Material(
        color: Colors.transparent,
        child: _chipLabel(name, dragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _chipLabel(name)),
      child: _chipLabel(name),
    );
  }

  Widget _chipLabel(String name, {bool dragging = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dragging ? kMeetingAccent : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }
}

/// 从 livekit 房间名解析组号，如 lr123_br2 -> 2
int? breakoutGroupFromLivekitRoom(String roomId, String livekitRoom) {
  final prefix = '${roomId}_br';
  if (!livekitRoom.startsWith(prefix)) return null;
  return int.tryParse(livekitRoom.substring(prefix.length));
}

Map<String, int> breakoutAssignmentsToGroups(String roomId, Map<String, String> assignments) {
  final out = <String, int>{};
  assignments.forEach((uid, lk) {
    final g = breakoutGroupFromLivekitRoom(roomId, lk);
    if (g != null) out[uid] = g;
  });
  return out;
}
