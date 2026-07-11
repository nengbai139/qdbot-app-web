import 'dart:convert';

import '../api/ai_api.dart';

const circleCaptionMaxChars = 100;

String _cleanAiLine(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  final fenced = RegExp(r'^```(?:\w+)?\s*\n([\s\S]*?)\n```\s*$');
  final m = fenced.firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  t = t.replaceAll(RegExp(r'^["「『]|["」』]$'), '');
  t = t.replaceFirst(RegExp(r'^#+\s*'), '');
  t = t.replaceFirst(RegExp(r'^[-*•]\s+'), '');
  final runes = t.runes.toList();
  if (runes.length > circleCaptionMaxChars) {
    t = String.fromCharCodes(runes.take(circleCaptionMaxChars));
  }
  return t.trim();
}

bool _looksLikeAgentProgress(String content) {
  final t = content.trim();
  if (t.isEmpty) return false;
  if (t.contains('█') && t.contains('░')) return true;
  if (RegExp(r'\d+\s*%').hasMatch(t)) return true;
  if (RegExp(r'^\p{Extended_Pictographic}', unicode: true).hasMatch(t) && t.length < 160) {
    const progressEmojis = ['🎯', '🛠', '📋', '🏗', '📝', '💻', '⚙', '✅', '📦', '🔄'];
    for (final e in progressEmojis) {
      if (t.startsWith(e)) return true;
    }
  }
  const stages = ['意图识别', '技能选择', '需求分析', '架构设计', '任务规划', '开发执行', '工具执行', '验证检查', 'Loop Engineering', 'QDBotClaw', '已收到您的请求', '移交 QDBotClaw'];
  for (final s in stages) {
    if (t.contains(s)) return true;
  }
  return false;
}

String _extractCaption(String raw) {
  if (raw.trim().isEmpty) return '';
  final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !_looksLikeAgentProgress(l));
  final first = lines.isNotEmpty ? lines.first : raw.trim();
  if (_looksLikeAgentProgress(first)) return '';
  return _cleanAiLine(first);
}

int _lastUserIndex(List<dynamic> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if ((messages[i]['role'] ?? '').toString() == 'user') return i;
  }
  return -1;
}

String? _finalAssistantReply(List<dynamic> messages) {
  final start = _lastUserIndex(messages);
  if (start < 0) return null;
  for (var i = messages.length - 1; i > start; i--) {
    final m = messages[i];
    if (m is! Map || (m['role'] ?? '').toString() != 'assistant') continue;
    final caption = _extractCaption((m['content'] ?? '').toString());
    if (caption.isEmpty) return null;
    return caption;
  }
  return null;
}

/// 圈子 AI 配文：走 /app/ai/skill 入队（session_key 由后端规范为 skill_{userId}_*）
Future<String> suggestCircleCopy({
  required String token,
  required String userId,
  required String draft,
  required bool forVideo,
}) async {
  final uid = userId.trim();
  if (uid.isEmpty) throw Exception('请先登录');

  final kind = forVideo ? '短视频标题' : '朋友圈配文';
  final hint = draft.trim().isEmpty ? '（暂无草稿，请写一句轻松积极的短句）' : draft.trim();
  final sessionKey = forVideo ? 'circle_video_title' : 'circle_moment_caption';
  final ai = AiApi(token);
  final resp = await ai.sendSkill(
    message: '请写一条中文$kind，不超过${circleCaptionMaxChars}字，只输出正文一行，不要引号、标签或说明。\n用户想法：$hint',
    sessionKey: sessionKey,
  );
  if (resp.statusCode == 429) {
    throw Exception('今日 AI 配额已用完');
  }
  if (resp.statusCode != 200) {
    throw Exception('AI 生成失败 (${resp.statusCode})');
  }
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final direct = _extractCaption((j['content'] ?? j['reply'] ?? '').toString());
  if (direct.isNotEmpty) return direct;

  final pending = j['pending'] == true;
  final convId = (j['convId'] ?? '').toString();
  if (!pending || convId.isEmpty) throw Exception('AI 未返回会话 ID');

  for (var i = 0; i < 45; i++) {
    await Future.delayed(const Duration(seconds: 2));
    final mResp = await ai.messages(convId);
    if (mResp.statusCode != 200) continue;
    final data = jsonDecode(mResp.body) as Map<String, dynamic>;
    final list = (data['messages'] as List?) ?? [];
    final reply = _finalAssistantReply(list);
    if (reply != null) return reply;
  }
  throw Exception('AI 生成超时，请稍后重试');
}
