import 'dart:convert';

import '../api/ai_api.dart';
import 'media_url.dart';

/// ponytail: 内存缓存，刷新后重转；升级路径可落库 msgId→text
class VoiceTranscriptCache {
  static final _map = <String, String>{};

  static String? get(String url) => _map[publicMediaUrl(url)];

  static void put(String url, String text) {
    final k = publicMediaUrl(url);
    if (k.isEmpty || text.trim().isEmpty) return;
    _map[k] = text.trim();
  }
}

String cleanVoiceTranscript(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  final fenced = RegExp(r'^```(?:\w+)?\s*\n([\s\S]*?)\n```\s*$');
  final fm = fenced.firstMatch(t);
  if (fm != null) t = fm.group(1)!.trim();
  t = t.replaceFirst(RegExp(r'^(转写|识别|内容)[：:]\s*', caseSensitive: false), '');
  return t.trim();
}

Future<String> transcribeVoiceUrl(String token, String url) async {
  final src = publicMediaUrl(url);
  if (src.isEmpty) throw Exception('语音地址无效');

  final cached = VoiceTranscriptCache.get(src);
  if (cached != null && cached.isNotEmpty) return cached;

  final resp = await AiApi(token).sendSkill(
    message: '请将以下语音转写为中文，只输出转写正文，不要摘要、标题或说明。\n$url: $src',
    sessionKey: 'im_voice_stt',
  );
  if (resp.statusCode == 429) {
    throw Exception('今日 AI 配额已用完，请明天再试或开通 Pro');
  }
  if (resp.statusCode != 200) {
    throw Exception('转写失败: ${resp.body}');
  }
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final text = cleanVoiceTranscript((j['reply'] ?? j['content'] ?? '').toString());
  if (text.isEmpty) throw Exception('未识别到文字内容');
  VoiceTranscriptCache.put(src, text);
  return text;
}
