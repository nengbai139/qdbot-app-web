import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/im_api.dart';
import 'contacts_page.dart';
import 'premium/user_code_display.dart';

/// 用户搜索选择（单选或多选）。返回 userId 列表，取消返回 null。
Future<List<String>?> showUserPickSheet(
  BuildContext context, {
  required ImApi im,
  required String title,
  bool multiSelect = false,
  String confirmLabel = '确定',
  Set<String> excludeUserIds = const {},
  List<Map<String, String>> recentUsers = const [],
  String? currentUserId,
  bool showContactsBrowse = false,
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      var filter = '';
      List<dynamic> apiResults = [];
      bool apiLoading = false;
      final selected = <String, String>{}; // userId -> displayName
      Timer? debounce;

      return StatefulBuilder(
        builder: (ctx, setSheet) {
          void scheduleSearch(String text) {
            debounce?.cancel();
            final trimmed = text.trim();
            if (trimmed.length < 2) {
              setSheet(() {
                apiResults = [];
                apiLoading = false;
              });
              return;
            }
            debounce = Timer(const Duration(milliseconds: 350), () async {
              setSheet(() => apiLoading = true);
              try {
                final resp = await im.searchUsers(trimmed);
                if (resp.statusCode == 200) {
                  final data = jsonDecode(resp.body);
                  setSheet(() {
                    apiResults = (data['users'] as List<dynamic>? ?? [])
                        .where((u) => !excludeUserIds.contains((u['userId'] ?? '').toString()))
                        .toList();
                    apiLoading = false;
                  });
                } else {
                  setSheet(() => apiLoading = false);
                }
              } catch (_) {
                setSheet(() => apiLoading = false);
              }
            });
          }

          void pickUser(String userId, String name) {
            if (multiSelect) {
              setSheet(() {
                if (selected.containsKey(userId)) {
                  selected.remove(userId);
                } else {
                  selected[userId] = name;
                }
              });
            } else {
              debounce?.cancel();
              Navigator.pop(sheetCtx, [userId]);
            }
          }

          void confirm() {
            debounce?.cancel();
            if (multiSelect) {
              final manual = controller.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty && !excludeUserIds.contains(e))
                  .toList();
              final ids = {...selected.keys, ...manual}.toList();
              if (ids.isEmpty) return;
              Navigator.pop(sheetCtx, ids);
            } else {
              final id = controller.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(sheetCtx, [id]);
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: multiSelect ? '搜索或输入邮箱/靓号/ID，多个用逗号分隔' : '搜索邮箱 / 昵称 / 靓号 / 用户 ID',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setSheet(() => filter = v);
                        scheduleSearch(v);
                      },
                    ),
                  ),
                  if (multiSelect && selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selected.entries.map((e) {
                          return InputChip(
                            label: Text(e.value, style: const TextStyle(fontSize: 12)),
                            onDeleted: () => setSheet(() => selected.remove(e.key)),
                          );
                        }).toList(),
                      ),
                    ),
                  if (apiLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  else if (apiResults.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('搜索结果', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.35),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: apiResults.length,
                        itemBuilder: (_, i) {
                          final u = apiResults[i];
                          final peerId = (u['userId'] ?? '').toString();
                          final name = (u['displayName'] ?? u['nickname'] ?? u['email'] ?? peerId).toString();
                          final code = (u['userCode'] ?? '').toString();
                          final levelName = (u['levelName'] ?? '').toString();
                          final premium = u['premium'] == true;
                          final picked = selected.containsKey(peerId);
                          final subtitle = code.isNotEmpty
                              ? (premium ? '$code · $levelName' : code)
                              : (u['email'] ?? peerId).toString();
                          return ListTile(
                            leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                            title: Row(
                              children: [
                                Expanded(child: Text(name)),
                                if (premium) PremiumLevelChip(levelName: levelName, compact: true),
                              ],
                            ),
                            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
                            trailing: multiSelect ? Icon(picked ? Icons.check_circle : Icons.circle_outlined, color: picked ? Colors.blue : null) : null,
                            onTap: () => pickUser(peerId, name),
                          );
                        },
                      ),
                    ),
                  ]                   else if (filter.trim().length >= 2 && !apiLoading)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('无匹配用户', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
                    ),
                  if (showContactsBrowse && currentUserId != null && currentUserId.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await Navigator.push<Map<String, String>>(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => ContactsPage(
                                im: im,
                                currentUserId: currentUserId,
                                recentUsers: recentUsers,
                              ),
                            ),
                          );
                          if (picked == null) return;
                          final peerId = (picked['userId'] ?? '').trim();
                          if (peerId.isEmpty || excludeUserIds.contains(peerId)) return;
                          final name = (picked['displayName'] ?? peerId).toString();
                          if (multiSelect) {
                            setSheet(() => selected[peerId] = name);
                          } else {
                            debounce?.cancel();
                            Navigator.pop(sheetCtx, [peerId]);
                          }
                        },
                        icon: const Icon(Icons.contacts_outlined, size: 18),
                        label: const Text('打开通讯录'),
                      ),
                    ),
                  ],
                  if (recentUsers.isNotEmpty && filter.trim().length < 2) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('最近单聊', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.25),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: recentUsers.length,
                        itemBuilder: (_, i) {
                          final u = recentUsers[i];
                          final peerId = u['userId'] ?? '';
                          final name = u['displayName'] ?? peerId;
                          return ListTile(
                            leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                            title: Text(name),
                            subtitle: Text(peerId, style: const TextStyle(fontSize: 11)),
                            onTap: () => pickUser(peerId, name),
                          );
                        },
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(onPressed: confirm, child: Text(confirmLabel)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}
