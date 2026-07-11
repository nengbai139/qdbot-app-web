import 'dart:convert';
import 'api_client.dart';

class UserProfile {
  final String userId;
  final String userCode;
  final String nickname;
  final String avatarUrl;
  final String email;
  final String phone;
  final String tenantId;
  final String workspaceId;
  final String platform;
  final bool premium;
  final String levelName;
  final String levelDesc;

  const UserProfile({
    this.userId = '',
    this.userCode = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.email = '',
    this.phone = '',
    this.tenantId = '',
    this.workspaceId = '',
    this.platform = '',
    this.premium = false,
    this.levelName = '',
    this.levelDesc = '',
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: (j['userId'] ?? '').toString(),
        userCode: (j['userCode'] ?? '').toString(),
        nickname: (j['nickname'] ?? '').toString(),
        avatarUrl: (j['avatarUrl'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        tenantId: (j['tenantId'] ?? '').toString(),
        workspaceId: (j['workspaceId'] ?? '').toString(),
        platform: (j['platform'] ?? '').toString(),
        premium: j['premium'] == true,
        levelName: (j['levelName'] ?? '').toString(),
        levelDesc: (j['levelDesc'] ?? '').toString(),
      );

  String get displayName {
    if (nickname.isNotEmpty && nickname != userId) return nickname;
    if (userCode.isNotEmpty && userCode != userId) return userCode;
    if (email.isNotEmpty) return email;
    return userId;
  }
}

class NotificationPrefs {
  final bool webNotify;
  final bool imNotify;
  final bool mentionNotify;
  final bool aiNotify;

  const NotificationPrefs({
    this.webNotify = true,
    this.imNotify = true,
    this.mentionNotify = true,
    this.aiNotify = true,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
        webNotify: j['webNotify'] != false,
        imNotify: j['imNotify'] != false,
        mentionNotify: j['mentionNotify'] != false,
        aiNotify: j['aiNotify'] != false,
      );
}

class AppDeviceInfo {
  final String deviceId;
  final String platform;
  final String osVersion;
  final String appVersion;
  final String pushToken;
  final DateTime? lastLoginAt;

  const AppDeviceInfo({
    this.deviceId = '',
    this.platform = '',
    this.osVersion = '',
    this.appVersion = '',
    this.pushToken = '',
    this.lastLoginAt,
  });

  factory AppDeviceInfo.fromJson(Map<String, dynamic> j) {
    DateTime? last;
    final raw = j['lastLoginAt'];
    if (raw != null) last = DateTime.tryParse(raw.toString());
    return AppDeviceInfo(
      deviceId: (j['deviceId'] ?? '').toString(),
      platform: (j['platform'] ?? '').toString(),
      osVersion: (j['osVersion'] ?? '').toString(),
      appVersion: (j['appVersion'] ?? '').toString(),
      pushToken: (j['pushToken'] ?? '').toString(),
      lastLoginAt: last,
    );
  }
}

class UserApi {
  final ApiClient _c;
  UserApi(String token) : _c = ApiClient(token: token);

  Future<UserProfile> getProfile() async {
    final resp = await _c.get('/app/user/profile');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return UserProfile.fromJson(ApiClient.decode(resp));
  }

  Future<void> updateSettings({
    String? nickname,
    String? avatarUrl,
    String? email,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    final resp = await _c.put('/app/user/settings', body: body);
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<List<AppDeviceInfo>> getDevices() async {
    final resp = await _c.get('/app/user/devices');
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['devices'] as List<dynamic>? ?? [];
    return list.map((e) => AppDeviceInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<NotificationPrefs> getNotifications() async {
    final resp = await _c.get('/app/user/notifications');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return NotificationPrefs.fromJson(ApiClient.decode(resp));
  }

  Future<NotificationPrefs> updateNotifications(NotificationPrefs prefs) async {
    final resp = await _c.put('/app/user/notifications', body: {
      'webNotify': prefs.webNotify,
      'imNotify': prefs.imNotify,
      'mentionNotify': prefs.mentionNotify,
      'aiNotify': prefs.aiNotify,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
    return NotificationPrefs.fromJson(ApiClient.decode(resp));
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    final resp = await _c.put('/app/user/password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? resp.body);
    }
  }
}
