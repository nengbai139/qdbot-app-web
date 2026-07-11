import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/api/webrtc_api.dart';

void main() {
  test('fallback ice servers include stun', () {
    final list = fallbackIceServers();
    expect(list, isNotEmpty);
    expect(list.first['urls'], contains('stun:'));
  });
}
