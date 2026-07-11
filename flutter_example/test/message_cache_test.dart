import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/message_cache.dart';

void main() {
  test('bucket keys are stable', () {
    expect(MessageCache.imSingleKey('u1'), 's:u1');
    expect(MessageCache.imGroupKey('g1'), 'g:g1');
    expect(MessageCache.aiKey('c1'), 'ai:c1');
  });
}
