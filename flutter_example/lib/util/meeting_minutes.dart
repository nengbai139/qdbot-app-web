import 'dart:convert';

import '../api/ai_api.dart';

String _cleanMinutes(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  final fenced = RegExp(r'^```(?:\w+)?\s*\n([\s\S]*?)\n```\s*$');
  final m = fenced.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  return t;
}

/// 根据会议聊天 + 字幕生成纪要（走 /app/ai/skill）
Future<String?> generateMeetingMinutes({
  required String token,
  required String title,
  required List<({String speaker, String text})> lines,
}) async {
  if (lines.isEmpty) return null;
  final buf = StringBuffer('会议：${title.trim().isEmpty ? '未命名' : title.trim()}\n\n');
  for (final line in lines.take(80)) {
    final who = line.speaker.trim().isEmpty ? '参会者' : line.speaker.trim();
    final text = line.text.trim();
    if (text.isEmpty) continue;
    buf.writeln('$who：$text');
  }
  final ai = AiApi(token);
  final resp = await ai.sendSkill(
    message:
        '根据以下视频会议记录，生成结构化会议纪要（含：会议概要、主要讨论点、结论与待办）。使用 Markdown，简洁中文：\n\n${buf.toString()}',
    sessionKey: 'meeting_minutes',
  );
  if (resp.statusCode == 429) throw Exception('今日 AI 配额已用完');
  if (resp.statusCode != 200) return null;
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final direct = _cleanMinutes((j['content'] ?? j['reply'] ?? '').toString());
  if (direct.isNotEmpty) return direct;
  final convId = (j['convId'] ?? '').toString();
  if (j['pending'] != true || convId.isEmpty) return null;
  for (var i = 0; i < 25; i++) {
    await Future.delayed(const Duration(seconds: 2));
    final mResp = await ai.messages(convId);
    if (mResp.statusCode != 200) continue;
    final data = jsonDecode(mResp.body) as Map<String, dynamic>;
    final list = (data['messages'] as List?) ?? [];
    for (var k = list.length - 1; k >= 0; k--) {
      final m = list[k];
      if (m is! Map || (m['role'] ?? '').toString() != 'assistant') continue;
      final out = _cleanMinutes((m['content'] ?? '').toString());
      if (out.isNotEmpty) return out;
    }
  }
  return null;
}
