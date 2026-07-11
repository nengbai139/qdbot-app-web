import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/ui/premium/contact_card.dart';

void main() {
  test('encode and parse contact card', () {
    const card = ContactCardData(
      userId: 'u1',
      displayName: '白能',
      userCode: 'U2026000019',
      levelName: '铜牌·先驱号',
      email: 'nengbai@aliyun.com',
    );
    final raw = encodeContactCard(card);
    final parsed = tryParseContactCard(raw, contentType: 'contact_card');
    expect(parsed?.userCode, 'U2026000019');
    expect(parsed?.displayName, '白能');
    expect(parsed?.levelName, '铜牌·先驱号');
  });

  test('preview label', () {
    const card = ContactCardData(displayName: '白能', userCode: 'U2026000019');
    expect(contactCardPreviewLabel(card), '[名片] 白能');
  });

  test('parse legacy share text with link', () {
    const text =
        '加我 AIM：nengbai@aliyun.com · 靓号 U2026000019（铜牌·先驱号）\n'
        'https://www.aimatchem.com/app_web/?userCode=U2026000019';
    final card = tryParseContactCardFromShareText(text);
    expect(card?.userCode, 'U2026000019');
    expect(card?.email, 'nengbai@aliyun.com');
    expect(card?.levelName, '铜牌·先驱号');
  });
}
