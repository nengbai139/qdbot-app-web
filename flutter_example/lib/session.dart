import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 登录会话
class StoredSession {
  final String token;
  final String userId;
  final String userCode;

  const StoredSession({
    required this.token,
    required this.userId,
    this.userCode = '',
  });
}

/// 登录 token 与用户标识持久化
class SessionStore {
  static const _tokenKey = 'qdbot_token';
  static const _userIdKey = 'qdbot_user_id';
  static const _userCodeKey = 'qdbot_user_code';
  static const _emailKey = 'qdbot_last_email';
  static const _platformKey = 'qdbot_last_platform';
  static const _imGroupsExpandedKey = 'qdbot_im_groups_expanded';
  static const _imSinglesExpandedKey = 'qdbot_im_singles_expanded';
  static const _onboardingDoneKey = 'qdbot_onboarding_done';
  static const _pinnedSessionsKey = 'qdbot_pinned_sessions';
  static const _mutedSessionsKey = 'qdbot_muted_sessions';
  static const _hiddenSessionsKey = 'qdbot_hidden_sessions';
  static const _deviceIdKey = 'qdbot_device_id';
  static const _pushTokenKey = 'qdbot_push_token';
  static const _webNotifyKey = 'qdbot_web_notify';
  static const _expiryNotifyDateKey = 'qdbot_expiry_notify_date';
  static const _notifyInboxKey = 'qdbot_notify_inbox';
  static const _inboxSyncedAtKey = 'qdbot_inbox_synced_at';
  static const _pendingUserCodeKey = 'qdbot_pending_user_code';
  static const _pendingMeetingRoomKey = 'qdbot_pending_meeting_room';
  static const _pendingMeetingPasscodeKey = 'qdbot_pending_meeting_passcode';
  static const _themeModeKey = 'qdbot_theme_mode';
  static const _enterToSendKey = 'qdbot_enter_to_send';
  static const _showReadBadgeKey = 'qdbot_show_read_badge';
  static const _allowSearchKey = 'qdbot_allow_search';
  static const _webNotifyPromptKey = 'qdbot_web_notify_prompt_done';
  static const _defaultAiSkillKey = 'qdbot_default_ai_skill';
  static const _bootstrapAtKey = 'qdbot_bootstrap_at';
  static const _bootstrapTokenKey = 'qdbot_bootstrap_token';
  static const _tabCacheAtKey = 'qdbot_tab_cache_at';
  static const _tabCacheTokenKey = 'qdbot_tab_cache_token';
  static const _tabCacheSessionsKey = 'qdbot_tab_cache_sessions';
  static const _tabCacheGroupsKey = 'qdbot_tab_cache_groups';
  static const _tabCacheConversationsKey = 'qdbot_tab_cache_conversations';
  static const _tabCacheProfileKey = 'qdbot_tab_cache_profile';
  static const _tabCacheVideoFeedKey = 'qdbot_tab_cache_video_feed';
  static const _meetingMinutesKey = 'qdbot_meeting_minutes';
  static const _storage = FlutterSecureStorage();

  static const platforms = ['ios', 'android', 'web', 'pad'];

  static Future<void> save({
    required String token,
    required String userId,
    String userCode = '',
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _userCodeKey, value: userCode);
  }

  static Future<void> saveLastEmail(String email) async {
    if (email.contains('@')) {
      await _storage.write(key: _emailKey, value: email);
    }
  }

  static Future<void> saveLastPlatform(String platform) async {
    if (platforms.contains(platform)) {
      await _storage.write(key: _platformKey, value: platform);
    }
  }

  static Future<String?> loadLastEmail() => _storage.read(key: _emailKey);

  static Future<String?> loadLastPlatform() => _storage.read(key: _platformKey);

  /// IM 列表分区展开状态（默认展开）
  static Future<bool> loadImGroupsExpanded() async {
    final v = await _storage.read(key: _imGroupsExpandedKey);
    return v != 'false';
  }

  static Future<bool> loadImSinglesExpanded() async {
    final v = await _storage.read(key: _imSinglesExpandedKey);
    return v != 'false';
  }

  static Future<void> saveImGroupsExpanded(bool expanded) =>
      _storage.write(key: _imGroupsExpandedKey, value: expanded ? 'true' : 'false');

  static Future<void> saveImSinglesExpanded(bool expanded) =>
      _storage.write(key: _imSinglesExpandedKey, value: expanded ? 'true' : 'false');

  static Future<bool> loadOnboardingDone() async =>
      (await _storage.read(key: _onboardingDoneKey)) == 'true';

  static Future<void> saveOnboardingDone() =>
      _storage.write(key: _onboardingDoneKey, value: 'true');

  static Future<void> clearOnboardingDone() => _storage.delete(key: _onboardingDoneKey);

  /// Local cache of /app/im/session pin flags; refreshed from GET /app/im/sessions
  static Future<Set<String>> loadPinnedSessions() async {
    final v = await _storage.read(key: _pinnedSessionsKey);
    if (v == null || v.isEmpty) return {};
    return v.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Future<void> savePinnedSessions(Set<String> keys) =>
      _storage.write(key: _pinnedSessionsKey, value: keys.join(','));

  /// Local cache of /app/im/session mute flags; refreshed from GET /app/im/sessions
  static Future<Set<String>> loadMutedSessions() async {
    final v = await _storage.read(key: _mutedSessionsKey);
    if (v == null || v.isEmpty) return {};
    return v.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Future<void> saveMutedSessions(Set<String> keys) =>
      _storage.write(key: _mutedSessionsKey, value: keys.join(','));

  /// ponytail: hidden synced via /app/im/session/:id/hide; local cache for offline UX
  static Future<Set<String>> loadHiddenSessions() async {
    final v = await _storage.read(key: _hiddenSessionsKey);
    if (v == null || v.isEmpty) return {};
    return v.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Future<void> saveHiddenSessions(Set<String> keys) =>
      _storage.write(key: _hiddenSessionsKey, value: keys.join(','));

  static Future<String> loadOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = 'd${DateTime.now().microsecondsSinceEpoch}';
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  static Future<String?> loadPushToken() => _storage.read(key: _pushTokenKey);

  static Future<void> savePushToken(String token) => _storage.write(key: _pushTokenKey, value: token);

  static Future<void> clearPushToken() => _storage.delete(key: _pushTokenKey);

  static String _noticeKey(String groupId) => 'qdbot_notice_$groupId';

  static Future<String?> loadGroupNoticeSeen(String groupId) => _storage.read(key: _noticeKey(groupId));

  static Future<void> saveGroupNoticeSeen(String groupId, String hash) =>
      _storage.write(key: _noticeKey(groupId), value: hash);

  static Future<bool> loadWebNotifyEnabled() async {
    final v = await _storage.read(key: _webNotifyKey);
    return v != 'false';
  }

  static Future<void> saveWebNotifyEnabled(bool enabled) =>
      _storage.write(key: _webNotifyKey, value: enabled ? 'true' : 'false');

  /// ponytail: 订阅到期 Web 通知每日最多一次
  static Future<String?> loadExpiryNotifyDate() => _storage.read(key: _expiryNotifyDateKey);

  static Future<void> saveExpiryNotifyDate(String ymd) =>
      _storage.write(key: _expiryNotifyDateKey, value: ymd);

  static Future<String?> loadNotifyInboxRaw() => _storage.read(key: _notifyInboxKey);

  static Future<void> saveNotifyInboxRaw(String json) =>
      _storage.write(key: _notifyInboxKey, value: json);

  static const _inboxReadAtKey = 'qdbot_inbox_read_at';

  static Future<DateTime?> loadInboxReadAt() async {
    final v = await _storage.read(key: _inboxReadAtKey);
    if (v == null || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  static Future<void> saveInboxReadAt(DateTime t) =>
      _storage.write(key: _inboxReadAtKey, value: t.toIso8601String());

  static String _aiReadKey(String convId) => 'qdbot_ai_read_$convId';

  static Future<int> loadAiLastReadMsgId(String convId) async {
    if (convId.isEmpty) return 0;
    final v = await _storage.read(key: _aiReadKey(convId));
    return int.tryParse(v ?? '') ?? 0;
  }

  static Future<void> saveAiLastReadMsgId(String convId, int msgId) async {
    if (convId.isEmpty || msgId <= 0) return;
    await _storage.write(key: _aiReadKey(convId), value: '$msgId');
  }

  static Future<DateTime?> loadInboxSyncedAt() async {
    final v = await _storage.read(key: _inboxSyncedAtKey);
    if (v == null || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  static Future<void> saveInboxSyncedAt(DateTime t) =>
      _storage.write(key: _inboxSyncedAtKey, value: t.toIso8601String());

  static const _inboxMergeStrategyKey = 'qdbot_inbox_merge_strategy';

  static Future<String> loadInboxMergeStrategyRaw() async =>
      await _storage.read(key: _inboxMergeStrategyKey) ?? 'smart';

  static Future<void> saveInboxMergeStrategyRaw(String name) =>
      _storage.write(key: _inboxMergeStrategyKey, value: name);

  static Future<StoredSession?> load() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    return StoredSession(
      token: token,
      userId: await _storage.read(key: _userIdKey) ?? '',
      userCode: await _storage.read(key: _userCodeKey) ?? '',
    );
  }

  static Future<void> savePendingUserCode(String code) async {
    final c = code.trim();
    if (c.length >= 2) await _storage.write(key: _pendingUserCodeKey, value: c);
  }

  static Future<String?> takePendingUserCode() async {
    final c = await _storage.read(key: _pendingUserCodeKey);
    await _storage.delete(key: _pendingUserCodeKey);
    return (c != null && c.trim().length >= 2) ? c.trim() : null;
  }

  static Future<void> savePendingMeetingRoom(String roomId) async {
    final id = roomId.trim();
    if (id.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      await _storage.write(key: _pendingMeetingRoomKey, value: id);
    }
  }

  static Future<String?> takePendingMeetingRoom() async {
    final id = await _storage.read(key: _pendingMeetingRoomKey);
    await _storage.delete(key: _pendingMeetingRoomKey);
    if (id == null || id.trim().isEmpty) return null;
    final t = id.trim();
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(t) ? t : null;
  }

  static Future<void> savePendingMeetingPasscode(String? passcode) async {
    final p = (passcode ?? '').trim();
    if (p.isEmpty) {
      await _storage.delete(key: _pendingMeetingPasscodeKey);
      return;
    }
    await _storage.write(key: _pendingMeetingPasscodeKey, value: p);
  }

  static Future<String?> takePendingMeetingPasscode() async {
    final p = await _storage.read(key: _pendingMeetingPasscodeKey);
    await _storage.delete(key: _pendingMeetingPasscodeKey);
    final t = (p ?? '').trim();
    return t.isEmpty ? null : t;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userCodeKey);
  }

  /// light | dark | system
  static Future<String> loadThemeModeRaw() async =>
      await _storage.read(key: _themeModeKey) ?? 'system';

  static Future<void> saveThemeModeRaw(String mode) =>
      _storage.write(key: _themeModeKey, value: mode);

  /// 回车发送（默认开启，微信习惯）
  static Future<bool> loadEnterToSend() async {
    final v = await _storage.read(key: _enterToSendKey);
    return v != 'false';
  }

  static Future<void> saveEnterToSend(bool enabled) =>
      _storage.write(key: _enterToSendKey, value: enabled ? 'true' : 'false');

  static Future<bool> loadShowReadBadge() async {
    final v = await _storage.read(key: _showReadBadgeKey);
    return v != 'false';
  }

  static Future<void> saveShowReadBadge(bool enabled) =>
      _storage.write(key: _showReadBadgeKey, value: enabled ? 'true' : 'false');

  /// 允许他人通过展示码/邮箱搜索到我
  static Future<bool> loadAllowSearch() async {
    final v = await _storage.read(key: _allowSearchKey);
    return v != 'false';
  }

  static Future<void> saveAllowSearch(bool enabled) =>
      _storage.write(key: _allowSearchKey, value: enabled ? 'true' : 'false');

  static Future<bool> loadWebNotifyPromptDone() async =>
      (await _storage.read(key: _webNotifyPromptKey)) == 'true';

  static Future<void> saveWebNotifyPromptDone() =>
      _storage.write(key: _webNotifyPromptKey, value: 'true');

  /// 助手新对话默认模式：null/空 = 自由对话；否则为专有 Skill ID
  static Future<String?> loadDefaultAiUserSkillId() async {
    final v = (await _storage.read(key: _defaultAiSkillKey))?.trim();
    if (v == null || v.isEmpty || v == 'free') return null;
    return v;
  }

  static Future<void> saveDefaultAiUserSkillId(String? skillId) async {
    final id = skillId?.trim() ?? '';
    if (id.isEmpty) {
      await _storage.write(key: _defaultAiSkillKey, value: 'free');
    } else {
      await _storage.write(key: _defaultAiSkillKey, value: id);
    }
  }

  /// ponytail: Safari 整页重载后仍跳过 2 分钟内 HomePage 级 bootstrap API
  static Future<bool> shouldSkipHomeBootstrap(String token) async {
    final atRaw = await _storage.read(key: _bootstrapAtKey);
    final t = await _storage.read(key: _bootstrapTokenKey);
    if (atRaw == null || t != token) return false;
    final at = DateTime.tryParse(atRaw);
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(minutes: 2);
  }

  static Future<void> markHomeBootstrapped(String token) async {
    await _storage.write(key: _bootstrapAtKey, value: DateTime.now().toIso8601String());
    await _storage.write(key: _bootstrapTokenKey, value: token);
  }

  static Future<void> clearHomeBootstrap() async {
    await _storage.delete(key: _bootstrapAtKey);
    await _storage.delete(key: _bootstrapTokenKey);
  }

  static Future<void> saveTabCache({
    required String token,
    String? sessionsJson,
    String? groupsJson,
    String? conversationsJson,
    String? profileJson,
    String? videoFeedJson,
  }) async {
    await _storage.write(key: _tabCacheTokenKey, value: token);
    await _storage.write(key: _tabCacheAtKey, value: DateTime.now().toIso8601String());
    if (sessionsJson != null) await _storage.write(key: _tabCacheSessionsKey, value: sessionsJson);
    if (groupsJson != null) await _storage.write(key: _tabCacheGroupsKey, value: groupsJson);
    if (conversationsJson != null) await _storage.write(key: _tabCacheConversationsKey, value: conversationsJson);
    if (profileJson != null) await _storage.write(key: _tabCacheProfileKey, value: profileJson);
    if (videoFeedJson != null) await _storage.write(key: _tabCacheVideoFeedKey, value: videoFeedJson);
  }

  static Future<Map<String, String>?> loadTabCache(String token) async {
    final t = await _storage.read(key: _tabCacheTokenKey);
    final atRaw = await _storage.read(key: _tabCacheAtKey);
    if (t != token || atRaw == null) return null;
    final at = DateTime.tryParse(atRaw);
    if (at == null || DateTime.now().difference(at) > const Duration(minutes: 30)) return null;
    final out = <String, String>{};
    final s = await _storage.read(key: _tabCacheSessionsKey);
    if (s != null) out['sessions'] = s;
    final g = await _storage.read(key: _tabCacheGroupsKey);
    if (g != null) out['groups'] = g;
    final c = await _storage.read(key: _tabCacheConversationsKey);
    if (c != null) out['conversations'] = c;
    final p = await _storage.read(key: _tabCacheProfileKey);
    if (p != null) out['profile'] = p;
    final v = await _storage.read(key: _tabCacheVideoFeedKey);
    if (v != null) out['videoFeed'] = v;
    return out.isEmpty ? null : out;
  }


  static Future<void> saveMeetingMinutes({
    required String roomId,
    required String title,
    required String content,
    String? replayPostId,
  }) async {
    final raw = await _storage.read(key: _meetingMinutesKey);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is List) {
          for (final e in j) {
            if (e is Map) list.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (_) {}
    }
    list.removeWhere((e) => (e['roomId'] ?? '').toString() == roomId);
    list.insert(0, {
      'roomId': roomId,
      'title': title,
      'content': content,
      'savedAt': DateTime.now().toIso8601String(),
      if (replayPostId != null && replayPostId.isNotEmpty) 'replayPostId': replayPostId,
    });
    while (list.length > 8) list.removeLast();
    await _storage.write(key: _meetingMinutesKey, value: jsonEncode(list));
  }

  static Future<List<Map<String, String>>> loadMeetingMinutes() async {
    final raw = await _storage.read(key: _meetingMinutesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return j.whereType<Map>().map((e) => {
        'roomId': (e['roomId'] ?? '').toString(),
        'title': (e['title'] ?? '').toString(),
        'content': (e['content'] ?? '').toString(),
        'savedAt': (e['savedAt'] ?? '').toString(),
        'replayPostId': (e['replayPostId'] ?? '').toString(),
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearTabCache() async {
    for (final k in [
      _tabCacheAtKey,
      _tabCacheTokenKey,
      _tabCacheSessionsKey,
      _tabCacheGroupsKey,
      _tabCacheConversationsKey,
      _tabCacheProfileKey,
      _tabCacheVideoFeedKey,
    ]) {
      await _storage.delete(key: k);
    }
  }
}
