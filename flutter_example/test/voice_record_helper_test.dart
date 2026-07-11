import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/voice_record_helper.dart';
import 'package:record/record.dart';

class _FakeRecorder extends AudioRecorder {
  final Set<AudioEncoder> supported;

  _FakeRecorder(this.supported);

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => supported.contains(encoder);
}

void main() {
  test('prefers aac when supported', () async {
    final fmt = await pickVoiceRecordFormat(_FakeRecorder({AudioEncoder.aacLc}));
    expect(fmt?.extension, 'm4a');
  });

  test('falls back to opus on web-like browsers', () async {
    final fmt = await pickVoiceRecordFormat(_FakeRecorder({AudioEncoder.opus}));
    expect(fmt?.extension, 'webm');
  });

  test('returns null when nothing supported', () async {
    final fmt = await pickVoiceRecordFormat(_FakeRecorder({}));
    expect(fmt, isNull);
  });
}
