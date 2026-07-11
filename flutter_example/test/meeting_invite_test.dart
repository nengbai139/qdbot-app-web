import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/circle/meeting_deep_link.dart';

void main() {
  test('encode and parse meeting invite json', () {
    const invite = MeetingInviteData(roomId: 'lr123', title: '周会', passcode: '8888');
    final raw = encodeMeetingInvite(invite);
    final parsed = tryParseMeetingInvite(raw, contentType: 'meeting_invite');
    expect(parsed?.roomId, 'lr123');
    expect(parsed?.title, '周会');
    expect(parsed?.passcode, '8888');
    expect(meetingInvitePreviewLabel(parsed!), '[会议邀请] 周会');
  });

  test('parse plain text meeting invite', () {
    final text = meetingInviteText(title: '产品讨论', roomId: 'lr999', passcode: 'abc');
    final parsed = tryParseMeetingInviteText(text);
    expect(parsed?.roomId, 'lr999');
    expect(parsed?.title, '产品讨论');
    expect(parsed?.passcode, 'abc');
  });
}
