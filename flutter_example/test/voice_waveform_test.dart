import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/voice_waveform.dart';

void main() {
  test('downsample keeps bar count', () {
    final samples = List.generate(100, (i) => (i % 10) / 10.0);
    final bars = downsampleToWaveform(samples, bars: 12);
    expect(bars.length, 12);
    expect(bars.every((b) => b >= 8 && b <= 100), isTrue);
  });

  test('fallback is stable for same seed', () {
    final a = fallbackWaveform(durationMs: 5000, seed: 'u1');
    final b = fallbackWaveform(durationMs: 5000, seed: 'u1');
    expect(a, b);
  });
}
