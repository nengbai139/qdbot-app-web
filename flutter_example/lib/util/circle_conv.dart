import '../ui/chat_helpers.dart';

bool isCircleUtilityConvId(String convId) {
  final c = convId.trim();
  if (c.isEmpty) return false;
  if (c.contains('_circle_')) return true;
  if (c.contains('circle_moment_caption') || c.contains('circle_video_title')) return true;
  return false;
}

bool isCircleUtilityWs(Map<String, dynamic> m) {
  if (isCircleUtilityConvId(aiConvIdFromWs(m))) return true;
  final su = (m['skillUsed'] ?? m['skill_used'] ?? '').toString();
  if (su == 'circle_caption' || su.startsWith('user:circle')) return true;
  final sk = (m['sessionId'] ?? m['sessionID'] ?? m['sessionKey'] ?? '').toString();
  if (isCircleUtilityConvId(sk)) return true;
  final ext = m['ext'];
  if (ext is Map) {
    final e = Map<String, dynamic>.from(ext);
    if (isCircleUtilityConvId((e['convId'] ?? e['sessionId'] ?? '').toString())) return true;
  }
  return false;
}
