import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/im_api.dart';
import 'premium/user_code_display.dart';

/// 通讯录（飞书/微信式独立页）
class ContactsPage extends StatefulWidget {
  final ImApi im;
  final String currentUserId;
  final List<Map<String, String>> recentUsers;

  const ContactsPage({
    super.key,
    required this.im,
    required this.currentUserId,
    this.recentUsers = const [],
  });

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final resp = await widget.im.searchUsers(q);
        if (!mounted) return;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          setState(() {
            _results = (data['users'] as List<dynamic>? ?? [])
                .where((u) => (u['userId'] ?? '').toString() != widget.currentUserId)
                .toList();
            _loading = false;
          });
        } else {
          setState(() => _loading = false);
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _pick(String userId, String name) {
    Navigator.pop(context, {'userId': userId, 'displayName': name});
  }

  Widget _userTile({required String userId, required String name, String? userCode, String? levelName, String? subtitle}) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (userCode != null && userCode.isNotEmpty) UserCodeRow(userCode: userCode, levelName: levelName ?? ''),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(userId, name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = widget.recentUsers.where((u) => u['userId']?.isNotEmpty == true).toList();
    final q = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('通讯录')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '搜索展示码、邮箱或昵称',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                isDense: true,
              ),
              onChanged: _scheduleSearch,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: q.length >= 2
                ? (_results.isEmpty && !_loading
                    ? Center(child: Text('未找到用户', style: TextStyle(color: Colors.grey.shade600)))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: Colors.grey.shade200),
                        itemBuilder: (_, i) {
                          final u = _results[i] as Map;
                          final userId = (u['userId'] ?? '').toString();
                          final name = (u['nickname'] ?? u['displayName'] ?? userId).toString();
                          return _userTile(
                            userId: userId,
                            name: name,
                            userCode: (u['userCode'] ?? '').toString(),
                            levelName: (u['levelName'] ?? '').toString(),
                            subtitle: (u['email'] ?? '').toString(),
                          );
                        },
                      ))
                : ListView(
                    children: [
                      if (recent.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('最近联系', style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                        ),
                        ...recent.map((u) {
                          final userId = u['userId']!;
                          final name = u['displayName'] ?? userId;
                          return _userTile(userId: userId, name: name, subtitle: '发消息');
                        }),
                        const SizedBox(height: 16),
                      ],
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.person_search_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('输入至少 2 个字符搜索同事', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
