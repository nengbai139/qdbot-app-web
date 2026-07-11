import 'media_url.dart';

/// 可内联播放的圈子 VOD（排除 HLS 与无效的直播回放占位 mp4）
bool isPlayableCircleVodUrl(String url) {
  final u = publicMediaUrl(url.trim());
  if (u.isEmpty) return false;
  final lower = u.toLowerCase();
  if (lower.endsWith('.m3u8')) return false;
  if (lower.contains('/live/') && (lower.endsWith('.mp4') || lower.contains('.mp4?'))) {
    return false;
  }
  if (lower.startsWith('live/') && lower.endsWith('.mp4')) return false;
  return lower.contains('/images/');
}

/// 直播/会议停播后发帖，但 videoUrl 无效（历史假链或 DVR 归档失败）
bool isBrokenReplayPost({required String text, required String videoUrl}) {
  if (!text.contains('回放')) return false;
  return !isPlayableCircleVodUrl(videoUrl);
}
