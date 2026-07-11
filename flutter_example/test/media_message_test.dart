import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/file_message.dart';
import 'package:qdbot_app_example/ui/media_message.dart';

void main() {
  test('video message from contentType video', () {
    final raw = encodeMediaMessage(url: 'https://x.com/a.mp4', name: 'clip.mp4', size: 100);
    final v = tryParseVideoMessage(raw, contentType: 'video');
    expect(v, isNotNull);
    expect(v!.name, 'clip.mp4');
  });

  test('video recognized when sent as file with mp4 name', () {
    final raw = encodeFileMessage(url: 'https://x.com/v', name: 'demo.mp4', size: 100);
    final v = tryParseVideoMessage(raw, contentType: 'file');
    expect(v, isNotNull);
    expect(v!.url, 'https://x.com/v');
  });

  test('non-video file not parsed as video', () {
    final raw = encodeFileMessage(url: 'https://x.com/v', name: 'doc.pdf', size: 100);
    expect(tryParseVideoMessage(raw, contentType: 'file'), isNull);
  });

  test('video poster url roundtrip', () {
    final raw = encodeMediaMessage(
      url: 'https://x.com/a.mp4',
      name: 'clip.mp4',
      poster: 'https://x.com/poster.jpg',
    );
    final v = tryParseVideoMessage(raw, contentType: 'video');
    expect(v?.poster, 'https://x.com/poster.jpg');
  });

  test('voice waveform roundtrip', () {
    final raw = encodeMediaMessage(
      url: 'https://x.com/v.webm',
      durationMs: 3200,
      waveform: [10, 40, 80, 30],
    );
    final v = tryParseMediaMessage(raw, contentType: 'voice');
    expect(v?.waveform, [10, 40, 80, 30]);
  });
}
