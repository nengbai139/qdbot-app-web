import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/voice_transcribe.dart';

void main() {
  test('cleanVoiceTranscript strips markdown fence', () {
    expect(cleanVoiceTranscript('```\n你好世界\n```'), '你好世界');
  });

  test('cleanVoiceTranscript strips label prefix', () {
    expect(cleanVoiceTranscript('转写：明天见'), '明天见');
  });
}
