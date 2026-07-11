import 'package:flutter/material.dart';
import '../../api/im_api.dart';
import 'contact_card.dart';
import 'share_contact_sheet.dart';

/// 打开名片分享面板：选人/选群发送卡片，或复制链接、系统分享
Future<void> shareUserCode(
  BuildContext context, {
  required String token,
  required String userId,
  required String userCode,
  String levelName = '',
  String displayName = '',
  String email = '',
}) {
  if (userCode.isEmpty) return Future.value();
  final card = ContactCardData(
    userId: userId,
    displayName: displayName,
    userCode: userCode,
    levelName: levelName,
    email: email,
  );
  return showShareContactSheet(context, im: ImApi(token), card: card);
}
