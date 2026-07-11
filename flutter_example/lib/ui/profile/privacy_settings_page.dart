import 'package:flutter/material.dart';
import '../../session.dart';
import 'profile_section.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _allowSearch = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allow = await SessionStore.loadAllowSearch();
    if (mounted) setState(() {
      _allowSearch = allow;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ProfileSection(
                  title: '发现与搜索',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.person_search_outlined),
                      title: const Text('允许他人搜索到我'),
                      subtitle: const Text('关闭后他人无法通过展示码或邮箱找到你'),
                      value: _allowSearch,
                      onChanged: (v) async {
                        await SessionStore.saveAllowSearch(v);
                        if (mounted) setState(() => _allowSearch = v);
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Text(
                    '会话隐藏、免打扰等可在消息列表长按会话设置。',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }
}
