import 'package:flutter/material.dart';
import '../api/ai_api.dart';

/// 助手：自由对话 vs 专有 Skill（L2）
enum AiSkillMode { free, user }

/// 输入框左侧图标：点击切换 Skill
Widget aiSkillPickerIcon({
  required AiSkillMode mode,
  required String? userSkillName,
  required VoidCallback onTap,
}) {
  final isUser = mode == AiSkillMode.user;
  final color = isUser ? Colors.teal.shade700 : Colors.grey.shade600;
  final icon = isUser ? Icons.person_pin : Icons.auto_awesome_outlined;
  final tip = isUser ? '专有：${userSkillName ?? '已选'}' : '自由对话 · 点选专有 Skill';
  return Tooltip(
    message: tip,
    child: IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        backgroundColor: isUser ? color.withValues(alpha: 0.12) : null,
      ),
      icon: Badge(
        isLabelVisible: isUser,
        smallSize: 8,
        backgroundColor: color,
        child: Icon(icon, color: color, size: 22),
      ),
    ),
  );
}

Future<void> showAiSkillPickerSheet({
  required BuildContext context,
  required AiSkillMode mode,
  required String? selectedUserSkillId,
  required List<UserSkill> userSkills,
  required VoidCallback onManageUserSkills,
  required void Function(String? userSkillId) onSelected,
  String title = '对话模式',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.38,
          minChildSize: 0.25,
          maxChildSize: 0.65,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                ),
                _pickerTile(
                  ctx,
                  selected: mode == AiSkillMode.free,
                  icon: Icons.chat_bubble_outline,
                  color: Colors.grey.shade700,
                  title: '自由对话',
                  subtitle: '通用助手，由 AI 自动理解意图',
                  onTap: () {
                    onSelected(null);
                    Navigator.pop(ctx);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '专有 Skill',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  ),
                ),
                if (userSkills.isEmpty)
                  ListTile(
                    leading: Icon(Icons.add, color: Colors.teal.shade700),
                    title: const Text('创建专有 Skill'),
                    subtitle: const Text('自定义领域指令，仅对你生效'),
                    onTap: () {
                      Navigator.pop(ctx);
                      onManageUserSkills();
                    },
                  )
                else
                  ...userSkills.map((s) {
                    final sel = mode == AiSkillMode.user && selectedUserSkillId == s.skillId;
                    return _pickerTile(
                      ctx,
                      selected: sel,
                      icon: Icons.person_pin,
                      color: Colors.teal.shade700,
                      title: s.name,
                      subtitle: s.description.isNotEmpty ? s.description : '专有指令',
                      onTap: () {
                        onSelected(s.skillId);
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ListTile(
                  leading: Icon(Icons.settings_outlined, color: Colors.grey.shade600),
                  title: const Text('管理专有 Skill'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onManageUserSkills();
                  },
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Widget _pickerTile(
  BuildContext context, {
  required bool selected,
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    selected: selected,
    leading: CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, size: 18, color: color),
    ),
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    trailing: selected ? Icon(Icons.check_circle, color: color) : null,
    onTap: onTap,
  );
}
