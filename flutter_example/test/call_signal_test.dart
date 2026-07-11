import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/call/call_signal.dart';

void main() {
  test('call signal roundtrip', () {
    final s = CallSignal(
      callId: 'c1',
      action: CallAction.invite,
      media: CallMedia.video,
      fromUserId: 'caller',
      toUserId: 'user@example.com',
    );
    final parsed = CallSignal.parse('{"callId":"c1","action":"invite","media":"video","fromUserId":"caller","toUserId":"user@example.com"}');
    expect(parsed?.toUserId, 'user@example.com');
    expect(parsed?.fromUserId, 'caller');
    expect(s.toJson()['action'], 'invite');
  });

  test('shouldRejectIncomingInvite same callId after offer', () {
    expect(
      shouldRejectIncomingInvite(activeCallId: 'c1', inviteCallId: 'c1', inCall: true),
      isFalse,
    );
    expect(
      shouldRejectIncomingInvite(activeCallId: 'c1', inviteCallId: 'c2', inCall: true),
      isTrue,
    );
    expect(
      shouldRejectIncomingInvite(activeCallId: null, inviteCallId: 'c1', inCall: false),
      isFalse,
    );
  });
}
