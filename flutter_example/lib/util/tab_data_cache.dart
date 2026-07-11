import 'dart:convert';

import '../api/ai_api.dart';
import '../api/user_api.dart';
import '../session.dart';
import '../ui/circle/circle_models.dart';

/// ponytail: HomePage 偶发重建 / Safari 整页重载时复用近期列表，跳过重复 API
class TabDataCache {
  static DateTime? _at;
  static String? _token;
  static const _ttl = Duration(minutes: 30);

  static List<dynamic>? sessions;
  static List<dynamic>? groups;
  static List<dynamic>? conversations;
  static AiSubscription? aiSub;
  static UserProfile? profile;
  static List<CirclePost>? circlePreview;
  static List<LiveRoom>? liveRooms;
  static List<CirclePost>? videoFeed;
  static String videoFeedCursor = '';
  static bool videoFeedHasMore = false;

  static bool get isFresh => _at != null && DateTime.now().difference(_at!) < _ttl;

  static bool get hasSessions => isFresh && sessions != null;

  static bool get hasConversations => isFresh && conversations != null;

  static bool get hasProfile => isFresh && profile != null;

  static bool get hasCircle => isFresh && (circlePreview != null || liveRooms != null);

  static bool get hasVideoFeed => isFresh && videoFeed != null && videoFeed!.isNotEmpty;

  @Deprecated('use hasSessions / hasConversations')
  static bool get warm => hasSessions || hasConversations;

  static Future<void> restore(String token) async {
    _token = token;
    final snap = await SessionStore.loadTabCache(token);
    if (snap == null) return;
    try {
      if (snap['sessions'] != null) {
        sessions = List<dynamic>.from(jsonDecode(snap['sessions']!) as List);
      }
      if (snap['groups'] != null) {
        groups = List<dynamic>.from(jsonDecode(snap['groups']!) as List);
      }
      if (snap['conversations'] != null) {
        conversations = List<dynamic>.from(jsonDecode(snap['conversations']!) as List);
      }
      if (snap['profile'] != null) {
        profile = UserProfile.fromJson(Map<String, dynamic>.from(jsonDecode(snap['profile']!) as Map));
      }
      if (snap['videoFeed'] != null) {
        final raw = jsonDecode(snap['videoFeed']!) as Map;
        videoFeed = (raw['items'] as List? ?? [])
            .map((e) => CirclePost.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        videoFeedCursor = (raw['cursor'] ?? '').toString();
        videoFeedHasMore = raw['hasMore'] == true;
      }
      _at = DateTime.now();
    } catch (_) {}
  }

  static void bindToken(String token) => _token = token;

  static void putSessions(List<dynamic> list) {
    sessions = list;
    _touch();
    _persist(sessionsJson: jsonEncode(list));
  }

  static void putGroups(List<dynamic> list) {
    groups = list;
    _touch();
    _persist(groupsJson: jsonEncode(list));
  }

  static void putConversations(List<dynamic> list) {
    conversations = list;
    _touch();
    _persist(conversationsJson: jsonEncode(list));
  }

  static void putAiSub(AiSubscription? sub) {
    aiSub = sub;
    _touch();
  }

  static void putCirclePreview(List<CirclePost> list) {
    circlePreview = list;
    _touch();
  }

  static void putLiveRooms(List<LiveRoom> list) {
    liveRooms = list;
    _touch();
  }

  static void putVideoFeed(List<CirclePost> items, {String cursor = '', bool hasMore = false}) {
    videoFeed = items;
    videoFeedCursor = cursor;
    videoFeedHasMore = hasMore;
    _touch();
    _persist(videoFeedJson: jsonEncode({
      'items': items.map((e) => e.toJson()).toList(),
      'cursor': cursor,
      'hasMore': hasMore,
    }));
  }

  static void putProfile(UserProfile? p) {
    profile = p;
    _touch();
    if (p != null) {
      _persist(profileJson: jsonEncode({
        'userId': p.userId,
        'userCode': p.userCode,
        'nickname': p.nickname,
        'avatarUrl': p.avatarUrl,
        'email': p.email,
        'phone': p.phone,
        'tenantId': p.tenantId,
        'workspaceId': p.workspaceId,
        'platform': p.platform,
        'premium': p.premium,
        'levelName': p.levelName,
        'levelDesc': p.levelDesc,
      }));
    }
  }

  static void clear() {
    sessions = null;
    groups = null;
    conversations = null;
    aiSub = null;
    profile = null;
    circlePreview = null;
    liveRooms = null;
    videoFeed = null;
    videoFeedCursor = '';
    videoFeedHasMore = false;
    _at = null;
    _token = null;
    SessionStore.clearTabCache();
  }

  static void _touch() => _at = DateTime.now();

  static void _persist({
    String? sessionsJson,
    String? groupsJson,
    String? conversationsJson,
    String? profileJson,
    String? videoFeedJson,
  }) {
    final t = _token;
    if (t == null || t.isEmpty) return;
    SessionStore.saveTabCache(
      token: t,
      sessionsJson: sessionsJson,
      groupsJson: groupsJson,
      conversationsJson: conversationsJson,
      profileJson: profileJson,
      videoFeedJson: videoFeedJson,
    );
  }
}
