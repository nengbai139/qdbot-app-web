import 'api_client.dart';

class InboxApi {
  final ApiClient _c;
  InboxApi(String token) : _c = ApiClient(token: token);

  Future<Map<String, dynamic>> list({String? kind, String? q}) async {
    final query = <String, String>{};
    if (kind != null && kind.isNotEmpty) query['kind'] = kind;
    if (q != null && q.isNotEmpty) query['q'] = q;
    final resp = await _c.get('/app/user/inbox', query: query.isEmpty ? null : query);
    if (resp.statusCode != 200) throw Exception(resp.body);
    return ApiClient.decode(resp);
  }

  Future<void> append({
    required String id,
    required String kind,
    required String title,
    required String body,
    Map<String, String>? data,
    DateTime? at,
    String? sourceDeviceId,
  }) async {
    final resp = await _c.post('/app/user/inbox', body: {
      'id': id,
      'kind': kind,
      'title': title,
      'body': body,
      'data': data ?? {},
      if (at != null) 'at': at.toUtc().toIso8601String(),
      if (sourceDeviceId != null && sourceDeviceId.isNotEmpty) 'sourceDeviceId': sourceDeviceId,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> markRead() async {
    final resp = await _c.put('/app/user/inbox/read');
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> markItemRead(String id) async {
    final resp = await _c.put('/app/user/inbox/$id/read');
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> deleteItem(String id) async {
    final resp = await _c.delete('/app/user/inbox/$id');
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> batchDelete(List<String> ids) async {
    final resp = await _c.post('/app/user/inbox/batch-delete', body: {'ids': ids});
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> clear() async {
    final resp = await _c.delete('/app/user/inbox');
    if (resp.statusCode != 200) throw Exception(resp.body);
  }
}

int parseUnreadCount(Map<String, dynamic> data) {
  final v = data['unreadCount'];
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> parseInboxItems(Map<String, dynamic> data) {
  final list = data['items'] as List<dynamic>? ?? [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
