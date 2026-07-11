import 'package:flutter/material.dart';
import '../api/ai_api.dart';
import 'user_skill_templates.dart';

class UserSkillEditPage extends StatefulWidget {
  final String token;
  final UserSkill? existing;
  const UserSkillEditPage({super.key, required this.token, this.existing});

  @override
  State<UserSkillEditPage> createState() => _UserSkillEditPageState();
}

class _UserSkillEditPageState extends State<UserSkillEditPage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _prompt = TextEditingController();
  bool _saving = false;
  bool _tipsExpanded = false;
  late final AiApi _ai = AiApi(widget.token);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _desc.text = e.description;
      _prompt.text = e.systemPrompt;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _applyTemplate(UserSkillTemplate t, {bool replacePromptOnly = false}) {
    if (!replacePromptOnly) {
      if (_name.text.trim().isEmpty) _name.text = t.suggestedName;
      if (_desc.text.trim().isEmpty) _desc.text = t.suggestedDesc;
    }
    _prompt.text = t.systemPrompt;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已套用「${t.title}」，请替换 [方括号] 占位符'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickTemplate() async {
    final chosen = await showModalBottomSheet<UserSkillTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('选用模版', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '模版符合 LLM 指令结构，填好占位符后一次即可达到稳定效果。',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in userSkillTemplates)
                        ListTile(
                          leading: Icon(
                            t.id == 'example_lfp'
                                ? Icons.menu_book_outlined
                                : t.id == 'best_practice'
                                    ? Icons.star_outline
                                    : Icons.description_outlined,
                            color: t.id == 'example_lfp'
                                ? Colors.teal.shade700
                                : t.id == 'best_practice'
                                    ? Colors.amber.shade800
                                    : null,
                          ),
                          title: Text(t.title),
                          subtitle: Text(t.subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(ctx, t),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    if (_prompt.text.trim().isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('套用模版'),
          content: const Text('当前指令将被替换为模版内容，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('替换')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _applyTemplate(chosen);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    if (name.isEmpty || prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名称和专有指令')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await _ai.createUserSkillParsed(name: name, systemPrompt: prompt, description: _desc.text.trim());
      } else {
        final resp = await _ai.updateUserSkill(
          widget.existing!.skillId,
          name: name,
          systemPrompt: prompt,
          description: _desc.text.trim(),
        );
        if (resp.statusCode != 200) throw Exception(resp.body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final promptEmpty = _prompt.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑专有 Skill' : '新建专有 Skill'),
        actions: [
          TextButton(onPressed: _saving ? null : _pickTemplate, child: const Text('模版')),
          TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? '…' : '保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '专有 Skill 仅对你生效。新手建议点「使用完整示例」，改产线/产品名后保存。',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
          ),
          if (!editing && promptEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.deepPurple.shade50,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('推荐：从完整示例开始', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.deepPurple.shade900)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _applyTemplate(kUserSkillFilledExample),
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('使用完整示例（LFP 涂布）'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _applyTemplate(kUserSkillBestPracticeTemplate),
                      child: const Text('或用空白模版（自行填写）'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _pickTemplate, child: const Text('更多场景模版…')),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder(), hintText: '如：LFP 工艺问答'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: '简介（可选）', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('专有技术指令', style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: _pickTemplate,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('选用模版'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _prompt,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText: '建议五段式：角色 / 范围 / 规则 / 格式 / 约束',
            ),
            maxLines: 16,
            minLines: 8,
          ),
          const SizedBox(height: 8),
          Text('最多约 8000 字 · 占位符 [方括号] 请改成你的实际场景', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ExpansionTile(
              initiallyExpanded: _tipsExpanded,
              onExpansionChanged: (v) => setState(() => _tipsExpanded = v),
              title: const Text('编写要点（资深 AI 建议）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              children: [
                for (final tip in userSkillWritingTips)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.check_circle_outline, size: 18, color: Colors.teal.shade600),
                    title: Text(tip, style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
