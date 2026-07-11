// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../ui/chat_helpers.dart';
import 'circle_conv.dart';

typedef WebNotifyTap = void Function(String kind, Map<String, String> data);
typedef ImNotifyLookup = Map<String, String>? Function(Map<String, dynamic> msg);

WebNotifyTap? _tapHandler;
ImNotifyLookup? _imLookup;

void setupWebNotifyHandler(WebNotifyTap? handler) => _tapHandler = handler;

void setupImNotifyLookup(ImNotifyLookup? lookup) => _imLookup = lookup;

Future<bool> requestWebNotifyPermission() async {
  if (html.Notification.permission == 'granted') return true;
  if (html.Notification.permission == 'denied') return false;
  final p = await html.Notification.requestPermission();
  return p == 'granted';
}

void _showNotification(String title, String body, {Map<String, String>? payload, bool whenHiddenOnly = true}) {
  if (whenHiddenOnly && html.document.hidden != true) return;
  void show() {
    final n = html.Notification(title, body: body);
    n.onClick.listen((_) {
      n.close();
      if (payload != null && _tapHandler != null) {
        _tapHandler!(payload['kind'] ?? 'im', payload);
      }
    });
  }

  if (html.Notification.permission == 'granted') {
    show();
  } else if (html.Notification.permission != 'denied') {
    html.Notification.requestPermission().then((p) {
      if (p == 'granted') show();
    });
  }
}

void maybeNotifyImMessage(Map<String, dynamic> msg) {
  final lookup = _imLookup?.call(msg);
  final from = (msg['fromName'] ?? msg['ext']?['fromName'] ?? msg['fromUserId'] ?? msg['ext']?['fromUserId'] ?? '新消息').toString();
  final gid = (msg['groupId'] ?? msg['ext']?['groupId'] ?? '').toString();
  final gname = (lookup?['groupName'] ?? msg['groupName'] ?? msg['ext']?['groupName'] ?? '').toString();
  final peerName = (lookup?['peerName'] ?? lookup?['title'] ?? '').toString();
  final title = gid.isNotEmpty
      ? (gname.isNotEmpty ? gname : '群聊')
      : (peerName.isNotEmpty ? peerName : from);
  final preview = imNotifyPreview(msg);
  final sender = (msg['senderName'] ?? msg['ext']?['senderName'] ?? from).toString();
  final body = gid.isNotEmpty && sender.isNotEmpty && sender != '新消息'
      ? '$sender: ${preview.length > 60 ? '${preview.substring(0, 60)}…' : preview}'
      : preview;
  final payload = <String, String>{'kind': 'im'};
  if (gid.isNotEmpty) {
    payload['groupId'] = gid;
    if (gname.isNotEmpty) payload['groupName'] = gname;
  } else {
    final peerId = (lookup?['peerId'] ?? from).toString();
    if (peerId.isNotEmpty) payload['peerId'] = peerId;
    if (peerName.isNotEmpty) payload['peerName'] = peerName;
  }
  _showNotification(title, body, payload: payload);
}

void maybeNotifyCircleMessage(Map<String, dynamic> msg) {
  final event = (msg['event'] ?? '').toString();
  if (event != 'live.start') return;
  final payload = Map<String, dynamic>.from((msg['payload'] as Map?) ?? {});
  final from = (payload['fromUserName'] ?? payload['fromUserId'] ?? '圈子').toString();
  final title = (payload['title'] ?? '').toString();
  final roomId = (payload['roomId'] ?? '').toString();
  final body = title.isNotEmpty ? '$from 开播：$title' : '$from 开始直播了';
  final payloadOut = <String, String>{'kind': 'circle', 'event': event, if (roomId.isNotEmpty) 'roomId': roomId};
  _showNotification('直播开播', body, payload: payloadOut);
}

void maybeNotifyAiMessage(Map<String, dynamic> msg) {
  if (isCircleUtilityWs(msg)) return;
  final content = (msg['content'] ?? '').toString();
  final body = content.length > 80 ? '${content.substring(0, 80)}…' : content;
  final convId = (msg['convId'] ?? msg['sessionID'] ?? msg['ext']?['convId'] ?? '').toString();
  final payload = <String, String>{'kind': 'ai', if (convId.isNotEmpty) 'convId': convId};
  _showNotification('AI 助手', body.isEmpty ? '收到新回复' : body, payload: payload);
}

void maybeNotifySubscriptionExpiry({required int daysLeft, String planName = 'AI Pro'}) {
  final name = planName.isNotEmpty ? planName : 'AI Pro';
  _showNotification(
    '订阅即将到期',
    '$name 还剩 $daysLeft 天，点击续订',
    payload: const {'kind': 'subscription'},
    whenHiddenOnly: false,
  );
}

bool webDocumentHidden() => html.document.hidden == true;

void maybeNotifyCallSignal(Map<String, dynamic> msg) {
  final from = (msg['senderName'] ?? msg['fromUserId'] ?? '来电').toString();
  final raw = (msg['content'] ?? '').toString();
  var isVideo = false;
  try {
    isVideo = raw.contains('"media":"video"');
  } catch (_) {}
  final body = isVideo ? '邀请你视频通话' : '邀请你语音通话';
  final peerId = (msg['fromUserId'] ?? '').toString();
  final payload = <String, String>{'kind': 'im', if (peerId.isNotEmpty) 'peerId': peerId, 'peerName': from};
  _showNotification(from, body, payload: payload);
}
