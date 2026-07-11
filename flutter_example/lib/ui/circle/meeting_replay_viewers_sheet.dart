import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../../api/im_api.dart';
import '../user_pick_sheet.dart';
import 'circle_models.dart';
import 'widgets/circle_ui.dart';

/// 主持人管理会议录像可见成员
Future<void> showMeetingReplayViewersSheet(
  BuildContext context, {
  required String token,
  required String userId,
  required String roomId,
}) {
  final api = CircleApi(token);
  final im = ImApi(token);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kMeetingSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _ReplayViewersBody(api: api, im: im, userId: userId, roomId: roomId),
  );
}

class _ReplayViewersBody extends StatefulWidget {
  final CircleApi api;
  final ImApi im;
  final String userId;
  final String roomId;

  const _ReplayViewersBody({
    required this.api,
    required this.im,
    required this.userId,
    required this.roomId,
  });

  @override
  State<_ReplayViewersBody> createState() => _ReplayViewersBodyState();
}

class _ReplayViewersBodyState extends State<_ReplayViewersBody> {
  List<ReplayViewer> _items = const [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listReplayViewers(widget.roomId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final picked = await showUserPickSheet(
      context,
      im: widget.im,
      title: '添加可见成员',
      multiSelect: true,
      confirmLabel: '添加',
      excludeUserIds: {widget.userId, ..._items.map((e) => e.userId)},
      currentUserId: widget.userId,
      showContactsBrowse: true,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final id in picked) {
        await widget.api.addReplayViewer(widget.roomId, userId: id);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加 ${picked.length} 人')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ReplayViewer v) async {
    if (v.isHost) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: kMeetingSurface,
        title: const Text('移除可见成员', style: TextStyle(color: Colors.white)),
        content: Text('确定移除 ${v.userName.isNotEmpty ? v.userName : v.userId}？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('移除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.removeReplayViewer(widget.roomId, v.userId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移除失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.people_outline, color: kMeetingAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('录像可见成员', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 4),
            Text('仅列表中的成员可在视频圈查看本场会议录像', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: kMeetingAccent)))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final v = _items[i];
                    final label = v.userName.isNotEmpty ? v.userName : v.userId;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: kMeetingAccent.withValues(alpha: 0.25),
                        child: Text(label.isNotEmpty ? label.characters.first : '?', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(label, style: const TextStyle(color: Colors.white)),
                      subtitle: v.isHost ? const Text('主持人', style: TextStyle(color: Colors.white38, fontSize: 11)) : null,
                      trailing: v.isHost || _busy
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              onPressed: () => _remove(v),
                            ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('添加成员'),
              style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
            ),
          ],
        ),
      ),
    );
  }
}
