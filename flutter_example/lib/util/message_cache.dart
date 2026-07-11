import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ponytail: 最近消息 JSON 缓存（每会话最多 80 条）；升级路径 → sqflite
class MessageCache {
  static const _key = 'qdbot_msg_cache_v1';
  static const maxPerBucket = 80;
  static const _storage = FlutterSecureStorage();

  static String imSingleKey(String peerId) => 's:$peerId';
  static String imGroupKey(String groupId) => 'g:$groupId';
  static String aiKey(String convId) => 'ai:$convId';

  static Future<Map<String, List<dynamic>>> _loadAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, List<dynamic>.from(v as List)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveAll(Map<String, List<dynamic>> all) async {
    await _storage.write(key: _key, value: jsonEncode(all));
  }

  static List<dynamic> _trim(List<dynamic> list) {
    if (list.length <= maxPerBucket) return list;
    // ponytail: AI 按时间正序，保留最新 N 条；取头部会丢掉刚发生的进度/终稿
    return list.sublist(list.length - maxPerBucket);
  }

  static Future<List<dynamic>> load(String bucket) async {
    if (bucket.isEmpty) return [];
    final all = await _loadAll();
    return List<dynamic>.from(all[bucket] ?? []);
  }

  static Future<void> save(String bucket, List<dynamic> messages) async {
    if (bucket.isEmpty || messages.isEmpty) return;
    final all = await _loadAll();
    all[bucket] = _trim(List<dynamic>.from(messages));
    await _saveAll(all);
  }

  /// IM：新消息在 index 0；合并去重后保留最新 maxPerBucket 条
  static Future<void> mergeIm(String bucket, List<dynamic> incoming, {bool prepend = false}) async {
    if (bucket.isEmpty || incoming.isEmpty) return;
    final existing = await load(bucket);
    final byId = <String, dynamic>{};
    for (final m in existing) {
      if (m is! Map) continue;
      final id = (m['msgId'] ?? m['id'] ?? '').toString();
      if (id.isNotEmpty) byId[id] = m;
    }
    for (final m in incoming) {
      if (m is! Map) continue;
      final id = (m['msgId'] ?? m['id'] ?? '').toString();
      if (id.isNotEmpty) {
        byId[id] = m;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final ta = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
    await save(bucket, merged);
  }

  /// AI：按时间正序，直接覆盖
  static Future<void> mergeAi(String bucket, List<dynamic> messages) async {
    await save(bucket, messages);
  }
}
