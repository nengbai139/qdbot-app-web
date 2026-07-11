import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/circle/circle_models.dart';
import 'package:qdbot_app_example/ui/circle/meeting_deep_link.dart';

LiveRoom _room({required String title, String roomType = LiveRoom.roomTypeLive, String mediaMode = 'hls', String livekitUrl = ''}) => LiveRoom(
      roomId: 'r1',
      hostId: 'h',
      hostName: 'H',
      title: title,
      roomType: roomType,
      mediaMode: mediaMode,
      livekitUrl: livekitUrl,
      status: 'live',
      pushUrl: 'rtmp://x/live/r1',
      playUrl: 'https://x/live/r1.m3u8',
    );

void main() {
  test('meeting vs live roomType rules', () {
    expect(normalizeMeetingTitle('产品讨论'), '产品讨论 · 会议');
    expect(normalizeMeetingTitle(''), '我的会议');
    expect(normalizeLiveTitle('产品讨论 · 会议'), '产品讨论 · 直播');
    expect(normalizeLiveTitle('视频会议'), '互动直播');

    final meetingSfu = _room(title: '周会', roomType: LiveRoom.roomTypeMeeting, mediaMode: 'sfu', livekitUrl: 'wss://lk');
    final meetingHls = _room(title: '周会', roomType: LiveRoom.roomTypeMeeting);
    final live = _room(title: '带货', roomType: LiveRoom.roomTypeLive);

    expect(meetingSfu.isMeeting, isTrue);
    expect(meetingSfu.isSfu, isTrue);
    expect(meetingSfu.meetingJoinable, isTrue);
    expect(meetingHls.isMeeting, isTrue);
    expect(meetingHls.meetingJoinable, isFalse);
    expect(live.isLiveBroadcast, isTrue);
    expect(live.isMeeting, isFalse);
  });
}
