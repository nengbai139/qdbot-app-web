import 'dart:convert';

import '../api/ai_api.dart';

String _cleanTranslation(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  final fenced = RegExp(r'^```(?:\w+)?\s*\n([\s\S]*?)\n```\s*$');
  final m = fenced.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  return t.replaceAll(RegExp(r'^["「『]|["」』]$'), '').trim();
}

/// 会议聊天单行翻译（走 /app/ai/skill）
Future<String?> translateMeetingLine({
  required String token,
  required String text,
  String targetLang = '简体中文',
}) async {
  final line = text.trim();
  if (line.isEmpty) return null;
  final ai = AiApi(token);
  final resp = await ai.sendSkill(
    message: '将下面会议聊天内容翻译成$targetLang，只输出译文一行，不要引号、标签或说明：\n$line',
    sessionKey: 'meeting_chat_translate',
  );
  if (resp.statusCode == 429) throw Exception('今日 AI 配额已用完');
  if (resp.statusCode != 200) return null;
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final direct = _cleanTranslation((j['content'] ?? j['reply'] ?? '').toString());
  if (direct.isNotEmpty) return direct;
  final convId = (j['convId'] ?? '').toString();
  if (j['pending'] != true || convId.isEmpty) return null;
  for (var i = 0; i < 20; i++) {
    await Future.delayed(const Duration(seconds: 2));
    final mResp = await ai.messages(convId);
    if (mResp.statusCode != 200) continue;
    final data = jsonDecode(mResp.body) as Map<String, dynamic>;
    final list = (data['messages'] as List?) ?? [];
    for (var k = list.length - 1; k >= 0; k--) {
      final m = list[k];
      if (m is! Map || (m['role'] ?? '').toString() != 'assistant') continue;
      final out = _cleanTranslation((m['content'] ?? '').toString());
      if (out.isNotEmpty) return out;
    }
  }
  return null;
}
