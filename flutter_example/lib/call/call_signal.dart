import 'dart:convert';

enum CallMedia { audio, video }

enum CallAction { invite, accept, reject, hangup, offer, answer, ice }

class CallSignal {
  final String callId;
  final CallAction action;
  final CallMedia media;
  final String fromUserId;
  final String toUserId;
  final String? sdp;
  final Map<String, dynamic>? candidate;

  const CallSignal({
    required this.callId,
    required this.action,
    required this.media,
    required this.fromUserId,
    required this.toUserId,
    this.sdp,
    this.candidate,
  });

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'action': action.name,
        'media': media.name,
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
      };

  static CallSignal? parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final action = CallAction.values.asNameMap()[(j['action'] ?? '').toString()];
      final media = CallMedia.values.asNameMap()[(j['media'] ?? 'audio').toString()] ?? CallMedia.audio;
      if (action == null) return null;
      return CallSignal(
        callId: (j['callId'] ?? '').toString(),
        action: action,
        media: media,
        fromUserId: (j['fromUserId'] ?? '').toString(),
        toUserId: (j['toUserId'] ?? '').toString(),
        sdp: j['sdp']?.toString(),
        candidate: j['candidate'] is Map ? Map<String, dynamic>.from(j['candidate'] as Map) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

String newCallId() => 'c${DateTime.now().microsecondsSinceEpoch}';

/// 同 callId 的 invite 可能是 offer 先到的补包，不能当忙线拒绝。
bool shouldRejectIncomingInvite({
  required String? activeCallId,
  required String inviteCallId,
  required bool inCall,
}) {
  if (inviteCallId.isEmpty) return false;
  if (activeCallId == inviteCallId) return false;
  return inCall;
}
