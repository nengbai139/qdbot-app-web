import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/im_api.dart';
import 'user_pick_sheet.dart';

/// 选择转发目标：单聊 userId 或群聊 groupId
Future<({String kind, String id})?> pickForwardTarget(BuildContext context, ImApi im) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('发给联系人'),
            onTap: () => Navigator.pop(ctx, 'user'),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('发到群聊'),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return null;

  if (choice == 'user') {
    final ids = await showUserPickSheet(context, im: im, title: '选择联系人', confirmLabel: '发送');
    if (ids == null || ids.isEmpty) return null;
    return (kind: 'user', id: ids.first);
  }

  final groupId = await _pickGroup(context, im);
  if (groupId == null) return null;
  return (kind: 'group', id: groupId);
}

Future<String?> _pickGroup(BuildContext context, ImApi im) async {
  List<dynamic> groups = [];
  try {
    final resp = await im.groups();
    if (resp.statusCode == 200) {
      groups = (jsonDecode(resp.body)['groups'] as List<dynamic>?) ?? [];
    }
  } catch (_) {}

  if (!context.mounted) return null;
  if (groups.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无群聊')));
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择群聊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final g = groups[i];
                final id = (g['groupId'] ?? '').toString();
                final name = (g['groupName'] ?? g['name'] ?? '群聊').toString();
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.group, size: 18)),
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
