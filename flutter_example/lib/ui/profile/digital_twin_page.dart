import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api/ai_api.dart';
import '../../api/bot_api.dart';
import '../user_skills_page.dart';

class DigitalTwinPage extends StatefulWidget {
  final String token;
  final String userId;

  const DigitalTwinPage({super.key, required this.token, required this.userId});

  @override
  State<DigitalTwinPage> createState() => _DigitalTwinPageState();
}

class _DigitalTwinPageState extends State<DigitalTwinPage> {
  final _persona = TextEditingController();
  bool _enabled = false;
  String? _defaultSkillId;
  List<UserSkill> _skills = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ai = AiApi(widget.token);
      final skills = await ai.fetchUserSkills();
      final r = await BotApi(widget.token).getConfig();
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        _enabled = d['enabled'] == true;
        _persona.text = (d['persona'] ?? '').toString();
        final sid = (d['defaultSkillId'] ?? '').toString();
        _defaultSkillId = sid.isEmpty ? null : sid;
      }
      if (mounted) {
        setState(() {
          _skills = skills;
          if (_defaultSkillId != null && !_skills.any((s) => s.skillId == _defaultSkillId)) {
            _defaultSkillId = null;
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BotApi(widget.token).updateConfig({
        'enabled': _enabled,
        'persona': _persona.text,
        'defaultSkillId': _defaultSkillId ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_enabled ? '数字分身已开启' : '数字分身已关闭')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openSkillsManager() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => UserSkillsPage(token: widget.token, userId: widget.userId),
        ))
        .then((_) => _load());
  }

  @override
  void dispose() {
    _persona.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 数字分身'),
        actions: [
          TextButton(
            onPressed: (_loading || _saving) ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用数字分身'),
                  subtitle: const Text('被 @ 或单聊时代答：无 Skill 同助手自由对话，有 Skill 同助手 L2（仅发最终结果）'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _persona,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '人设',
                    hintText: '例如：你是一个幽默的工程师，回复简洁专业',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '默认专有 Skill（可选）',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _defaultSkillId,
                      hint: const Text('无 — 仅用人设'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('无 — 仅用人设')),
                        ..._skills.map((s) => DropdownMenuItem(value: s.skillId, child: Text(s.name))),
                      ],
                      onChanged: (v) => setState(() => _defaultSkillId = v),
                    ),
                  ),
                ),
                if (_skills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(onPressed: _openSkillsManager, child: const Text('去创建专有 Skill')),
                  ),
              ],
            ),
    );
  }
}
