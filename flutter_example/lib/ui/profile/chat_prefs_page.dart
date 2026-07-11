import 'package:flutter/material.dart';
import '../../api/ai_api.dart';
import '../../session.dart';
import '../ai_skill_chips.dart';
import '../app_theme_controller.dart';
import 'profile_section.dart';

class ChatPrefsPage extends StatefulWidget {
  const ChatPrefsPage({super.key});

  @override
  State<ChatPrefsPage> createState() => _ChatPrefsPageState();
}

class _ChatPrefsPageState extends State<ChatPrefsPage> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _enterToSend = true;
  bool _showReadBadge = true;
  String? _defaultAiSkillId;
  List<UserSkill> _userSkills = [];
  String? _token;
  bool _loading = true;

  String get _defaultAiModeLabel {
    if (_defaultAiSkillId == null) return '自由对话';
    for (final s in _userSkills) {
      if (s.skillId == _defaultAiSkillId) return s.name;
    }
    return '专有 Skill（已失效，将按自由对话）';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await loadSavedThemeMode();
    final enter = await SessionStore.loadEnterToSend();
    final read = await SessionStore.loadShowReadBadge();
    final defaultSkill = await SessionStore.loadDefaultAiUserSkillId();
    final session = await SessionStore.load();
    var skills = <UserSkill>[];
    if (session != null) {
      try {
        skills = await AiApi(session.token).fetchUserSkills();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _enterToSend = enter;
        _showReadBadge = read;
        _defaultAiSkillId = defaultSkill;
        _userSkills = skills;
        _token = session?.token;
        _loading = false;
      });
    }
  }

  Future<void> _pickTheme() async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('外观模式', style: TextStyle(fontWeight: FontWeight.w600))),
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                title: Text(themeModeLabel(mode)),
                value: mode,
                groupValue: _themeMode,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await AppThemeController.setThemeModeOf(context, picked);
    setState(() => _themeMode = picked);
  }

  Future<void> _pickDefaultAiMode() async {
    if (_token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    await showAiSkillPickerSheet(
      context: context,
      title: '新对话默认模式',
      mode: _defaultAiSkillId != null ? AiSkillMode.user : AiSkillMode.free,
      selectedUserSkillId: _defaultAiSkillId,
      userSkills: _userSkills,
      onManageUserSkills: () {},
      onSelected: (userSkillId) async {
        await SessionStore.saveDefaultAiUserSkillId(userSkillId);
        if (mounted) {
          setState(() => _defaultAiSkillId = userSkillId);
          final label = userSkillId == null ? '自由对话' : _defaultAiModeLabel;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已设为默认：$label'), duration: const Duration(seconds: 1)),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('聊天偏好')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ProfileSection(
                  title: '助手',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('新对话默认模式'),
                      subtitle: Text(_defaultAiModeLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDefaultAiMode,
                    ),
                  ],
                ),
                ProfileSection(
                  title: '外观',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('主题模式'),
                      subtitle: Text(themeModeLabel(_themeMode)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickTheme,
                    ),
                  ],
                ),
                ProfileSection(
                  title: '输入与阅读',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.keyboard_return),
                      title: const Text('回车发送'),
                      subtitle: const Text('关闭后回车换行，需点发送按钮'),
                      value: _enterToSend,
                      onChanged: (v) async {
                        await SessionStore.saveEnterToSend(v);
                        if (mounted) setState(() => _enterToSend = v);
                      },
                    ),
                    const ProfileDivider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.done_all_outlined),
                      title: const Text('显示已读状态'),
                      subtitle: const Text('单聊消息下方显示已读/未读'),
                      value: _showReadBadge,
                      onChanged: (v) async {
                        await SessionStore.saveShowReadBadge(v);
                        if (mounted) setState(() => _showReadBadge = v);
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
