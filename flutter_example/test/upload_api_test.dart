import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/api/upload_api.dart';

void main() {
  test('detectImageUploadType reads magic bytes', () {
    expect(detectImageUploadType([0x89, 0x50, 0x4E, 0x47]), 'png');
    expect(detectImageUploadType([0x47, 0x49, 0x46, 0x38]), 'gif');
    expect(detectImageUploadType([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]), 'webp');
    expect(detectImageUploadType([0xFF, 0xD8, 0xFF]), 'jpeg');
    expect(detectImageUploadType([1, 2, 3], filename: 'photo.PNG'), 'png');
  });

  test('detectMediaUploadType uses extension for non-image', () {
    expect(detectMediaUploadType([1, 2, 3], filename: 'doc.pdf'), 'pdf');
  });
}
