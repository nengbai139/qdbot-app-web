import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/vod_url.dart';

void main() {
  test('rejects invalid live replay mp4 paths', () {
    expect(isPlayableCircleVodUrl('live/lr1783586789410137788.mp4'), isFalse);
    expect(isPlayableCircleVodUrl('https://www.aimatchem.com/live/lr1.mp4'), isFalse);
    expect(isPlayableCircleVodUrl('https://www.aimatchem.com/images/circle/u1/video/v.mp4'), isTrue);
  });

  test('detects broken replay posts', () {
    expect(isBrokenReplayPost(text: '测试 · 直播回放', videoUrl: 'https://www.aimatchem.com/live/lr1.mp4'), isTrue);
    expect(isBrokenReplayPost(text: '普通短视频', videoUrl: 'https://www.aimatchem.com/live/lr1.mp4'), isFalse);
    expect(
      isBrokenReplayPost(
        text: '测试 · 直播回放',
        videoUrl: 'https://www.aimatchem.com/images/circle/u1/replay/r.mp4',
      ),
      isFalse,
    );
  });
}
