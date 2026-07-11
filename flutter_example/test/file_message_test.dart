import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/file_message.dart';

void main() {
  test('encode and parse file message', () {
    const url = 'https://example.com/a.pdf';
    final raw = encodeFileMessage(url: url, name: '报告.pdf', size: 2048);
    final f = tryParseFileMessage(raw, contentType: 'file');
    expect(f, isNotNull);
    expect(f!.url, url);
    expect(f.name, '报告.pdf');
    expect(f.size, 2048);
    expect(formatFileSize(2048), '2.0 KB');
  });
}
