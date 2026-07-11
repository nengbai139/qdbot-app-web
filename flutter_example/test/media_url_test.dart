import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/media_url.dart';

void main() {
  test('publicMediaUrl rewrites OSS direct to /images/', () {
    const oss =
        'https://qdbot-bucket01.oss-cn-beijing.aliyuncs.com/im/u1/image/m1/a.jpeg?';
    expect(
      publicMediaUrl(oss),
      'https://www.aimatchem.com/images/im/u1/image/m1/a.jpeg',
    );
  });

  test('publicMediaUrl strips presign query on aimatchem path', () {
    expect(
      publicMediaUrl('https://www.aimatchem.com/images/qdbot/x.png?X-Amz-Signature=abc'),
      'https://www.aimatchem.com/images/qdbot/x.png',
    );
  });
}
