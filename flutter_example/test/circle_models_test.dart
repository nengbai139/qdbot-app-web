import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/circle/circle_models.dart';

void main() {
  test('CirclePost parses json', () {
    final p = CirclePost.fromJson({
      'postId': 'p1',
      'authorId': 'u1',
      'authorName': 'Alice',
      'text': 'hi',
      'images': ['https://x.com/a.jpg'],
      'likeCount': 2,
      'liked': true,
    });
    expect(p.postId, 'p1');
    expect(p.likeCount, 2);
    expect(p.liked, isTrue);
    expect(p.images.first, contains('a.jpg'));
  });

  test('CircleKind availability', () {
    expect(CircleKind.moments.available, isTrue);
    expect(CircleKind.video.available, isTrue);
    expect(CircleKind.live.available, isTrue);
    expect(CircleKind.shop.available, isFalse);
  });
}
