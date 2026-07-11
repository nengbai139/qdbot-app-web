import 'package:flutter/material.dart';
import '../api/ai_api.dart';
import 'ai_chat_page.dart';
import 'user_skill_edit_page.dart';
import 'user_skill_templates.dart';

class UserSkillsPage extends StatefulWidget {
  final String token;
  final String userId;
  final Stream<Map<String, dynamic>>? msgStream;
  const UserSkillsPage({super.key, required this.token, required this.userId, this.msgStream});

  @override
  State<UserSkillsPage> createState() => _UserSkillsPageState();
}

class _UserSkillsPageState extends State<UserSkillsPage> {
  List<UserSkill> _skills = [];
  bool _loading = true;
  late final AiApi _ai = AiApi(widget.token);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _ai.fetchUserSkills();
      if (mounted) setState(() {
        _skills = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _openEdit([UserSkill? skill]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UserSkillEditPage(token: widget.token, existing: skill)),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(UserSkill skill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除专有 Skill'),
        content: Text('确定删除「${skill.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final resp = await _ai.deleteUserSkill(skill.skillId);
      if (resp.statusCode == 200) {
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.body)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _tryExample(UserSkill skill) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatPage(
          token: widget.token,
          userId: widget.userId,
          convId: '',
          title: skill.name,
          initialUserSkillId: skill.skillId,
          initialMessage: kUserSkillLfpExampleQuestion,
          msgStream: widget.msgStream,
        ),
      ),
    );
  }

  void _openChat(UserSkill skill) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatPage(
          token: widget.token,
          userId: widget.userId,
          convId: '',
          title: skill.name,
          initialUserSkillId: skill.skillId,
          msgStream: widget.msgStream,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的专有 Skill'),
        actions: [
          IconButton(tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEdit(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skills.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('还没有专有 Skill', style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Text(
                          '建议先点「完整示例：LFP 涂布工艺」，全文可直接改名词使用。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _openEdit(),
                          icon: const Icon(Icons.add),
                          label: const Text('创建第一个'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _skills.length,
                    itemBuilder: (_, i) {
                      final s = _skills[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade50,
                          child: Icon(Icons.person_pin, color: Colors.teal.shade700, size: 22),
                        ),
                        title: Text(s.name),
                        subtitle: Text(
                          s.description.isNotEmpty
                              ? s.description
                              : (s.systemPrompt.length > 48 ? '${s.systemPrompt.substring(0, 48)}…' : s.systemPrompt),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'try') _tryExample(s);
                            if (v == 'edit') _openEdit(s);
                            if (v == 'delete') _delete(s);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'try', child: Text('试用示例问题')),
                            const PopupMenuItem(value: 'edit', child: Text('编辑')),
                            const PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                        onTap: () => _openChat(s),
                      );
                    },
                  ),
                ),
    );
  }
}
