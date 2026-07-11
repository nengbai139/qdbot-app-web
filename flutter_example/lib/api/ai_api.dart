import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class AiPlan {
  final String planId;
  final String name;
  final double price;
  final int days;
  final String desc;

  const AiPlan({
    required this.planId,
    required this.name,
    required this.price,
    required this.days,
    this.desc = '',
  });

  factory AiPlan.fromJson(Map<String, dynamic> j) => AiPlan(
        planId: (j['planId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        days: (j['days'] as num?)?.toInt() ?? 30,
        desc: (j['desc'] ?? '').toString(),
      );
}

class AiSubscription {
  final bool active;
  final String planId;
  final String planName;
  final String status;
  final DateTime? expiresAt;
  final int daysLeft;
  final bool expiringSoon;

  const AiSubscription({
    this.active = false,
    this.planId = '',
    this.planName = '',
    this.status = '',
    this.expiresAt,
    this.daysLeft = 0,
    this.expiringSoon = false,
  });

  factory AiSubscription.fromJson(Map<String, dynamic> j) {
    DateTime? exp;
    final v = j['expiresAt'];
    if (v != null) exp = DateTime.tryParse(v.toString());
    return AiSubscription(
      active: j['active'] == true,
      planId: (j['planId'] ?? '').toString(),
      planName: (j['planName'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      expiresAt: exp,
      daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
      expiringSoon: j['expiringSoon'] == true,
    );
  }
}

class AiQuota {
  final int used;
  final int limit;
  final int remaining;
  final bool isPro;
  final DateTime? resetsAt;

  const AiQuota({
    this.used = 0,
    this.limit = 10,
    this.remaining = 10,
    this.isPro = false,
    this.resetsAt,
  });

  factory AiQuota.fromJson(Map<String, dynamic> j) {
    DateTime? reset;
    final v = j['resetsAt'];
    if (v != null) reset = DateTime.tryParse(v.toString());
    return AiQuota(
      used: (j['used'] as num?)?.toInt() ?? 0,
      limit: (j['limit'] as num?)?.toInt() ?? 10,
      remaining: (j['remaining'] as num?)?.toInt() ?? 0,
      isPro: j['isPro'] == true,
      resetsAt: reset,
    );
  }

  bool get exhausted => remaining <= 0;

  String resetCountdown([DateTime? now]) {
    final at = resetsAt;
    if (at == null) return '';
    now ??= DateTime.now();
    var diff = at.toLocal().difference(now);
    if (diff.isNegative) diff = Duration.zero;
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}小时${m}分后重置';
    if (m > 0) return '${m}分钟后重置';
    return '即将重置';
  }
}

/// L2 用户专有 Skill（存 qdbot_system，enterprise 执行）
class UserSkill {
  final String skillId;
  final String name;
  final String description;
  final String systemPrompt;
  final int version;

  const UserSkill({
    required this.skillId,
    required this.name,
    this.description = '',
    required this.systemPrompt,
    this.version = 1,
  });

  factory UserSkill.fromJson(Map<String, dynamic> j) => UserSkill(
        skillId: (j['skillId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        systemPrompt: (j['systemPrompt'] ?? '').toString(),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}

class AiApi {
  final ApiClient _c;
  AiApi(String token) : _c = ApiClient(token: token);

  Future<http.Response> conversations({String status = 'active', int limit = 50}) =>
      _c.get('/app/ai/conversations', query: {'status': status, 'limit': '$limit'});

  Future<http.Response> messages(String convId, {int since = 0, int limit = 200}) =>
      _c.get('/app/ai/conversations/$convId/messages', query: {
        if (since > 0) 'since': '$since',
        if (limit != 200) 'limit': '$limit',
      });

  Future<http.Response> send({String? convId, required String content, String contentType = 'text'}) =>
      _c.post('/app/ai/send', body: {
        'convId': convId?.isEmpty == true ? null : convId,
        'content': content,
        'contentType': contentType,
      });

  Future<http.Response> sendSkill({
    required String message,
    String contentType = 'text',
    String? skillHint,
    String? sessionKey,
    String? userSkillId,
  }) =>
      _c.post('/app/ai/skill', body: {
        'message': message,
        'contentType': contentType,
        if (skillHint != null && skillHint.isNotEmpty) 'skill_hint': skillHint,
        if (sessionKey != null && sessionKey.isNotEmpty) 'session_key': sessionKey,
        if (userSkillId != null && userSkillId.isNotEmpty) 'user_skill_id': userSkillId,
      });

  Future<http.Response> listUserSkills() => _c.get('/app/ai/user-skills');

  Future<http.Response> createUserSkill({
    required String name,
    required String systemPrompt,
    String description = '',
  }) =>
      _c.post('/app/ai/user-skills', body: {
        'name': name,
        'systemPrompt': systemPrompt,
        if (description.isNotEmpty) 'description': description,
      });

  Future<http.Response> updateUserSkill(
    String skillId, {
    required String name,
    required String systemPrompt,
    String description = '',
  }) =>
      _c.put('/app/ai/user-skills/$skillId', body: {
        'name': name,
        'systemPrompt': systemPrompt,
        if (description.isNotEmpty) 'description': description,
      });

  Future<http.Response> deleteUserSkill(String skillId) =>
      _c.delete('/app/ai/user-skills/$skillId');

  Future<List<UserSkill>> fetchUserSkills() async {
    final resp = await listUserSkills();
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['skills'] as List<dynamic>?) ?? [];
    return list.map((e) => UserSkill.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<UserSkill> createUserSkillParsed({
    required String name,
    required String systemPrompt,
    String description = '',
  }) async {
    final resp = await createUserSkill(name: name, systemPrompt: systemPrompt, description: description);
    if (resp.statusCode != 200) throw Exception(resp.body);
    return UserSkill.fromJson(Map<String, dynamic>.from(jsonDecode(resp.body) as Map));
  }

  Future<List<AiPlan>> getPlans() async {
    final resp = await _c.get('/app/ai/plans');
    if (resp.statusCode != 200) throw Exception(resp.body);
    final list = jsonDecode(resp.body)['plans'] as List<dynamic>? ?? [];
    return list.map((e) => AiPlan.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<AiSubscription> getSubscription() async {
    final resp = await _c.get('/app/ai/subscription');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return AiSubscription.fromJson(ApiClient.decode(resp));
  }

  Future<AiQuota> getQuota() async {
    final resp = await _c.get('/app/ai/quota');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return AiQuota.fromJson(ApiClient.decode(resp));
  }

  Future<http.Response> deleteConversation(String convId) =>
      _c.delete('/app/ai/conversations/$convId');

  Future<http.Response> updateTitle(String convId, String title) =>
      _c.put('/app/ai/conversations/$convId/title', body: {'title': title});

  Future<http.Response> setStatus(String convId, String status) =>
      _c.put('/app/ai/conversations/$convId/status', body: {'status': status});
}
