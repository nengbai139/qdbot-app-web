import 'dart:convert';
import '../api/im_api.dart';
import '../api/inbox_api.dart';
import '../session.dart';
import '../ui/chat_helpers.dart';

/// 通知中心里的一条「有未读的会话」
class InboxSessionTarget {
  final String kind;
  final String title;
  final int unread;
  final String? peerId;
  final String? peerName;
  final String? groupId;
  final String? groupName;
  final String? convId;

  const InboxSessionTarget({
    required this.kind,
    required this.title,
    required this.unread,
    this.peerId,
    this.peerName,
    this.groupId,
    this.groupName,
    this.convId,
  });
}

class NotifyEntry {
  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime at;
  final Map<String, String> data;
  final bool read;

  const NotifyEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.data = const {},
    this.read = false,
  });

  NotifyEntry copyWith({bool? read}) => NotifyEntry(
        id: id,
        kind: kind,
        title: title,
        body: body,
        at: at,
        data: data,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'at': at.toIso8601String(),
        'data': data,
        'read': read,
      };

  factory NotifyEntry.fromJson(Map<String, dynamic> j) {
    DateTime at = DateTime.tryParse((j['at'] ?? j['createdAt'] ?? '').toString()) ?? DateTime.now();
    return NotifyEntry(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      at: at,
      read: j['read'] == true,
      data: Map<String, String>.from((j['data'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {}),
    );
  }
}

typedef ImNotifyLookup = Map<String, String>? Function(Map<String, dynamic> msg);

class InboxSyncResult {
  final List<NotifyEntry> items;
  final int uploaded;
  final int unread;
  final int conflicts;
  final InboxMergeStrategy strategy;
  final DateTime syncedAt;

  const InboxSyncResult({
    required this.items,
    this.uploaded = 0,
    this.unread = 0,
    this.conflicts = 0,
    this.strategy = InboxMergeStrategy.smart,
    required this.syncedAt,
  });
}

/// 冲突合并策略：smart=时间戳合并，server=同 id 以服务端为准，local=以本地为准
enum InboxMergeStrategy { smart, server, local }

extension InboxMergeStrategyLabel on InboxMergeStrategy {
  String get label {
    switch (this) {
      case InboxMergeStrategy.smart:
        return '智能合并';
      case InboxMergeStrategy.server:
        return '服务端优先';
      case InboxMergeStrategy.local:
        return '本地优先';
    }
  }
}

/// 本地 + 服务端 /app/user/inbox 同步
class NotifyInbox {
  static const _max = 30;

  static Future<List<NotifyEntry>> load() async {
    final raw = await SessionStore.loadNotifyInboxRaw();
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => NotifyEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveLocal(List<NotifyEntry> list) async {
    final trimmed = list.length > _max ? list.sublist(0, _max) : list;
    await SessionStore.saveNotifyInboxRaw(jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  static Future<bool> record({
    String? id,
    required String kind,
    required String title,
    required String body,
    Map<String, String>? data,
    String? token,
  }) async {
    final entryId = (id != null && id.isNotEmpty) ? id : '${DateTime.now().microsecondsSinceEpoch}';
    final list = await load();
    if (list.any((e) => e.id == entryId)) return false;
    final entry = NotifyEntry(
      id: entryId,
      kind: kind,
      title: title,
      body: body,
      at: DateTime.now(),
      data: data ?? const {},
    );
    list.insert(0, entry);
    await _saveLocal(list);
    if (token != null && token.isNotEmpty) {
      final deviceId = await SessionStore.loadOrCreateDeviceId();
      InboxApi(token)
          .append(
            id: entryId,
            kind: kind,
            title: title,
            body: body,
            data: data,
            at: entry.at,
            sourceDeviceId: deviceId,
          )
          .catchError((_) {});
    }
    return true;
  }

  static String inboxIdForIm(Map<String, dynamic> msg) {
    final msgId = (msg['msgId'] ?? msg['ext']?['msgId'] ?? '').toString();
    return msgId.isNotEmpty ? 'im_$msgId' : '';
  }

  static String inboxIdForAi(Map<String, dynamic> msg) {
    final msgId = (msg['msgId'] ?? msg['ext']?['msgId'] ?? '').toString();
    return msgId.isNotEmpty ? 'ai_$msgId' : '';
  }

  static String inboxIdForSubscription(DateTime day) =>
      'sub_${day.toIso8601String().substring(0, 10)}';

  static List<NotifyEntry> mergeEntries(List<NotifyEntry> local, List<NotifyEntry> server) {
    final byId = <String, NotifyEntry>{};
    for (final e in local) {
      if (e.id.isNotEmpty) byId[e.id] = e;
    }
    for (final e in server) {
      if (e.id.isEmpty) continue;
      final prev = byId[e.id];
      if (prev == null) {
        byId[e.id] = e;
        continue;
      }
      final useServerBody = e.at.isAfter(prev.at) || e.at == prev.at;
      byId[e.id] = NotifyEntry(
        id: e.id,
        kind: e.kind.isNotEmpty ? e.kind : prev.kind,
        title: e.title.isNotEmpty ? e.title : prev.title,
        body: useServerBody ? e.body : prev.body,
        at: e.at.isAfter(prev.at) ? e.at : prev.at,
        data: e.data.isNotEmpty ? e.data : prev.data,
        read: e.read || prev.read,
      );
    }
    return _trimSorted(byId.values.toList());
  }

  static List<NotifyEntry> mergeServerWins(List<NotifyEntry> local, List<NotifyEntry> server) {
    final serverIds = server.map((e) => e.id).where((id) => id.isNotEmpty).toSet();
    final localOnly = local.where((e) => e.id.isNotEmpty && !serverIds.contains(e.id));
    return _trimSorted([...server, ...localOnly]);
  }

  static List<NotifyEntry> mergeLocalWins(List<NotifyEntry> local, List<NotifyEntry> server) {
    final localIds = local.map((e) => e.id).where((id) => id.isNotEmpty).toSet();
    final serverOnly = server.where((e) => e.id.isNotEmpty && !localIds.contains(e.id));
    return _trimSorted([...local, ...serverOnly]);
  }

  static List<NotifyEntry> _trimSorted(List<NotifyEntry> list) {
    list.sort((a, b) => b.at.compareTo(a.at));
    return list.length > _max ? list.sublist(0, _max) : list;
  }

  static int countConflicts(List<NotifyEntry> local, List<NotifyEntry> server) {
    final byId = {for (final e in server) e.id: e};
    var n = 0;
    for (final l in local) {
      if (l.id.isEmpty) continue;
      final s = byId[l.id];
      if (s == null) continue;
      if (l.body != s.body || l.read != s.read) n++;
    }
    return n;
  }

  static List<NotifyEntry> mergeWithStrategy(
    List<NotifyEntry> local,
    List<NotifyEntry> server,
    InboxMergeStrategy strategy,
  ) {
    switch (strategy) {
      case InboxMergeStrategy.server:
        return mergeServerWins(local, server);
      case InboxMergeStrategy.local:
        return mergeLocalWins(local, server);
      case InboxMergeStrategy.smart:
        return mergeEntries(local, server);
    }
  }

  static Future<InboxMergeStrategy> loadInboxMergeStrategy() async {
    final v = await SessionStore.loadInboxMergeStrategyRaw();
    return InboxMergeStrategy.values.firstWhere(
      (e) => e.name == v,
      orElse: () => InboxMergeStrategy.smart,
    );
  }

  static Future<void> saveInboxMergeStrategy(InboxMergeStrategy s) =>
      SessionStore.saveInboxMergeStrategyRaw(s.name);

  /// 合并本地与服务端；上传仅本地有的条目
  static Future<InboxSyncResult> mergeSync(
    String token, {
    String? kind,
    String? q,
    InboxMergeStrategy? strategy,
  }) async {
    final local = await load();
    final deviceId = await SessionStore.loadOrCreateDeviceId();
    final mergeStrategy = strategy ?? await loadInboxMergeStrategy();
    try {
      final data = await InboxApi(token).list(kind: kind, q: q);
      final server = parseInboxItems(data).map(NotifyEntry.fromJson).toList();
      final conflicts = countConflicts(local, server);
      var uploaded = 0;
      if (kind == null && (q == null || q.isEmpty)) {
        final serverIds = server.map((e) => e.id).where((id) => id.isNotEmpty).toSet();
        for (final e in local) {
          if (e.id.isEmpty || serverIds.contains(e.id)) continue;
          try {
            await InboxApi(token).append(
              id: e.id,
              kind: e.kind,
              title: e.title,
              body: e.body,
              data: e.data,
              at: e.at,
              sourceDeviceId: deviceId,
            );
            uploaded++;
          } catch (_) {}
        }
        final merged = mergeWithStrategy(local, server, mergeStrategy);
        await _saveLocal(merged);
        final readAt = data['readAt'];
        if (readAt != null) {
          final t = DateTime.tryParse(readAt.toString());
          if (t != null) await SessionStore.saveInboxReadAt(t);
        }
        final syncedAt = DateTime.now();
        await SessionStore.saveInboxSyncedAt(syncedAt);
        return InboxSyncResult(
          items: merged,
          uploaded: uploaded,
          unread: merged.where((e) => !e.read).length,
          conflicts: conflicts,
          strategy: mergeStrategy,
          syncedAt: syncedAt,
        );
      }
      return InboxSyncResult(
        items: server.isNotEmpty ? server : local,
        unread: server.isNotEmpty ? parseUnreadCount(data) : local.where((e) => !e.read).length,
        conflicts: conflicts,
        strategy: mergeStrategy,
        syncedAt: DateTime.now(),
      );
    } catch (_) {
      return InboxSyncResult(
        items: local,
        unread: local.where((e) => !e.read).length,
        strategy: mergeStrategy,
        syncedAt: DateTime.now(),
      );
    }
  }

  static Future<List<NotifyEntry>> syncFromServer(String token, {String? kind, String? q}) async {
    final r = await mergeSync(token, kind: kind, q: q);
    return r.items;
  }

  /// 角标用：只拉 /app/user/inbox，勿连带 sessions+groups（WS 重连时曾一秒打 13 个 API）
  static Future<int> unreadCount({String? token}) async {
    if (token != null && token.isNotEmpty) {
      try {
        final data = await InboxApi(token).list();
        return parseUnreadCount(data);
      } catch (_) {}
    }
    final list = await load();
    return list.where((e) => !e.read).length;
  }

  /// IM 会话 + AI/订阅通知的未读汇总（与通知中心列表一致）
  static Future<int> aggregatedUnreadCount(String token) async {
    final targets = await loadSessionTargets(token);
    return targets.fold<int>(0, (s, t) => s + t.unread);
  }

  static Future<List<InboxSessionTarget>> loadSessionTargets(String token) async {
    final im = ImApi(token);
    final targets = <InboxSessionTarget>[];

    try {
      final sResp = await im.sessions();
      if (sResp.statusCode == 200) {
        final list = (jsonDecode(sResp.body)['sessions'] as List<dynamic>?) ?? [];
        for (final raw in list) {
          final s = raw as Map<String, dynamic>;
          final unread = sessionUnread(s);
          if (unread <= 0) continue;
          final peerId = (s['peerUserId'] ?? s['peerId'] ?? s['userId'] ?? '').toString();
          final name = (s['peerName'] ?? peerId).toString();
          targets.add(InboxSessionTarget(kind: 'im_single', title: name, unread: unread, peerId: peerId, peerName: name));
        }
      }
      final gResp = await im.groups();
      if (gResp.statusCode == 200) {
        final list = (jsonDecode(gResp.body)['groups'] as List<dynamic>?) ?? [];
        for (final raw in list) {
          final g = raw as Map<String, dynamic>;
          final unread = sessionUnread(g, group: true);
          if (unread <= 0) continue;
          final gid = (g['groupId'] ?? '').toString();
          final name = (g['name'] ?? '群聊').toString();
          targets.add(InboxSessionTarget(kind: 'im_group', title: name, unread: unread, groupId: gid, groupName: name));
        }
      }
    } catch (_) {}

    try {
      final inbox = await mergeSync(token);
      final aiByConv = <String, int>{};
      var subUnread = 0;
      var circleUnread = 0;
      for (final e in inbox.items) {
        if (e.read) continue;
        if (e.kind == 'ai') {
          final c = (e.data['convId'] ?? '').toString();
          if (c.isNotEmpty) aiByConv[c] = (aiByConv[c] ?? 0) + 1;
        } else if (e.kind == 'subscription') {
          subUnread++;
        } else if (e.kind == 'circle') {
          circleUnread++;
        }
      }
      for (final e in aiByConv.entries) {
        targets.add(InboxSessionTarget(kind: 'ai', title: 'AI 对话', unread: e.value, convId: e.key));
      }
      if (subUnread > 0) {
        targets.add(InboxSessionTarget(kind: 'subscription', title: '订阅提醒', unread: subUnread));
      }
      if (circleUnread > 0) {
        targets.add(InboxSessionTarget(kind: 'circle', title: '圈子互动', unread: circleUnread));
      }
    } catch (_) {}

    targets.sort((a, b) => b.unread.compareTo(a.unread));
    return targets;
  }

  static Future<void> markItemRead(String id, {String? token}) async {
    final list = await load();
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      list[i] = list[i].copyWith(read: true);
      await _saveLocal(list);
    }
    if (token != null && token.isNotEmpty) {
      try {
        await InboxApi(token).markItemRead(id);
      } catch (_) {}
    }
  }

  static Future<void> markImSessionRead({required String? token, String? peerId, String? groupId}) async {
    final list = await load();
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e.kind != 'im' || e.read) continue;
      if (groupId != null && groupId.isNotEmpty && e.data['groupId'] == groupId) {
        list[i] = e.copyWith(read: true);
        changed = true;
      } else if (peerId != null && peerId.isNotEmpty && e.data['peerId'] == peerId) {
        list[i] = e.copyWith(read: true);
        changed = true;
      }
    }
    if (changed) await _saveLocal(list);
  }

  static Future<void> markAiConvRead({required String? token, required String convId}) async {
    final list = await load();
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e.kind == 'ai' && !e.read && e.data['convId'] == convId) {
        list[i] = e.copyWith(read: true);
        changed = true;
      }
    }
    if (changed) await _saveLocal(list);
  }

  static Future<void> markKindRead({required String? token, required String kind}) async {
    final list = await load();
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].kind == kind && !list[i].read) {
        list[i] = list[i].copyWith(read: true);
        changed = true;
      }
    }
    if (changed) await _saveLocal(list);
  }

  static Future<void> markAllRead({String? token}) async {
    final list = (await load()).map((e) => e.copyWith(read: true)).toList();
    await _saveLocal(list);
    await SessionStore.saveInboxReadAt(DateTime.now());
    if (token != null && token.isNotEmpty) {
      try {
        await InboxApi(token).markRead();
      } catch (_) {}
    }
  }

  static Future<void> clear({String? token}) async {
    await SessionStore.saveNotifyInboxRaw('[]');
    if (token != null && token.isNotEmpty) {
      InboxApi(token).clear().catchError((_) {});
    }
  }

  static Future<void> deleteItem(String id, {String? token}) async {
    final list = await load();
    list.removeWhere((e) => e.id == id);
    await _saveLocal(list);
    if (token != null && token.isNotEmpty) {
      try {
        await InboxApi(token).deleteItem(id);
      } catch (_) {}
    }
  }

  static Future<void> deleteItems(List<String> ids, {String? token}) async {
    if (ids.isEmpty) return;
    final set = ids.toSet();
    final list = await load();
    list.removeWhere((e) => set.contains(e.id));
    await _saveLocal(list);
    if (token != null && token.isNotEmpty) {
      try {
        await InboxApi(token).batchDelete(ids);
      } catch (_) {}
    }
  }

  static NotifyEntry? imFromMessage(Map<String, dynamic> msg, ImNotifyLookup? lookup) {
    final lu = lookup?.call(msg);
    final from = (msg['fromName'] ?? msg['ext']?['fromName'] ?? msg['fromUserId'] ?? msg['ext']?['fromUserId'] ?? '新消息').toString();
    final gid = (msg['groupId'] ?? msg['ext']?['groupId'] ?? '').toString();
    final gname = (lu?['groupName'] ?? msg['groupName'] ?? msg['ext']?['groupName'] ?? '').toString();
    final peerName = (lu?['peerName'] ?? lu?['title'] ?? '').toString();
    final title = gid.isNotEmpty ? (gname.isNotEmpty ? gname : '群聊') : (peerName.isNotEmpty ? peerName : from);
    final preview = imNotifyPreview(msg);
    final sender = (msg['senderName'] ?? msg['ext']?['senderName'] ?? from).toString();
    final body = gid.isNotEmpty && sender.isNotEmpty && sender != '新消息'
        ? '$sender: ${preview.length > 60 ? '${preview.substring(0, 60)}…' : preview}'
        : preview;
    final data = <String, String>{'kind': 'im'};
    final msgId = (msg['msgId'] ?? msg['ext']?['msgId'] ?? '').toString();
    if (msgId.isNotEmpty) data['msgId'] = msgId;
    if (gid.isNotEmpty) {
      data['groupId'] = gid;
      if (gname.isNotEmpty) data['groupName'] = gname;
    } else {
      final peerId = (lu?['peerId'] ?? from).toString();
      if (peerId.isNotEmpty) data['peerId'] = peerId;
      if (peerName.isNotEmpty) data['peerName'] = peerName;
    }
    return NotifyEntry(
      id: inboxIdForIm(msg),
      kind: 'im',
      title: title,
      body: body,
      at: DateTime.now(),
      data: data,
    );
  }

  static NotifyEntry aiFromMessage(Map<String, dynamic> msg) {
    final content = (msg['content'] ?? '').toString();
    final body = content.length > 80 ? '${content.substring(0, 80)}…' : content;
    final convId = aiConvIdFromWs(msg);
    final msgId = (msg['msgId'] ?? msg['ext']?['msgId'] ?? '').toString();
    return NotifyEntry(
      id: inboxIdForAi(msg),
      kind: 'ai',
      title: 'AI 助手',
      body: body.isEmpty ? '收到新回复' : body,
      at: DateTime.now(),
      data: {'kind': 'ai', if (convId.isNotEmpty) 'convId': convId, if (msgId.isNotEmpty) 'msgId': msgId},
    );
  }

  static NotifyEntry? circleFromMessage(Map<String, dynamic> msg) {
    if ((msg['type'] ?? '').toString() != 'circle') return null;
    final event = (msg['event'] ?? '').toString();
    final payload = Map<String, dynamic>.from((msg['payload'] as Map?) ?? {});
    final from = (payload['fromUserName'] ?? payload['fromUserId'] ?? '圈子').toString();
    final postId = (payload['postId'] ?? '').toString();
    final roomId = (payload['roomId'] ?? '').toString();
    final title = switch (event) {
      'moment.new' => '圈子动态',
      'video.new' => '视频圈',
      'live.start' => '直播开播',
      'moment.like' => '收到点赞',
      'moment.comment' => '收到评论',
      _ => '圈子',
    };
    var body = event;
    if (event == 'moment.new') {
      body = '$from 发布了新动态';
    } else if (event == 'video.new') {
      body = '$from 发布了新视频';
    } else if (event == 'live.start') {
      final t = (payload['title'] ?? '').toString();
      body = t.isNotEmpty ? '$from 开播：$t' : '$from 开始直播了';
    } else if (event == 'moment.like') {
      body = '$from 赞了你的动态';
    } else if (event == 'moment.comment') {
      final t = (payload['text'] ?? '').toString();
      body = '$from：${t.length > 40 ? '${t.substring(0, 40)}…' : t}';
    }
    return NotifyEntry(
      id: (roomId.isNotEmpty && event == 'live.start')
          ? 'circle:$event:$roomId:${DateTime.now().millisecondsSinceEpoch}'
          : postId.isNotEmpty
              ? 'circle:$event:$postId:${DateTime.now().millisecondsSinceEpoch}'
              : 'circle:$event:${DateTime.now().millisecondsSinceEpoch}',
      kind: 'circle',
      title: title,
      body: body,
      at: DateTime.now(),
      data: {
        'kind': 'circle',
        'event': event,
        if (postId.isNotEmpty) 'postId': postId,
        if (roomId.isNotEmpty) 'roomId': roomId,
        if (payload['fromUserId'] != null) 'fromUserId': payload['fromUserId'].toString(),
      },
    );
  }
}
