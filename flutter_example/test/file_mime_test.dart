import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/file_mime.dart';

void main() {
  test('pdf is viewable in browser', () {
    expect(fileViewableInBrowser('报告.pdf'), isTrue);
    expect(mimeForFilename('报告.pdf'), 'application/pdf');
  });

  test('docx downloads not inline view', () {
    expect(fileViewableInBrowser('a.docx'), isFalse);
    expect(isVideoFilename('a.mp4'), isTrue);
  });
}
