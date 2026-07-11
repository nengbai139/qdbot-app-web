import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_theme.dart';
import 'contact_card.dart';
import 'premium_deep_link.dart';
import 'user_code_display.dart';

/// 微信 / 朋友圈专用竖版分享图（375×520 @1x，导出 3x）
class ContactCardSharePoster extends StatelessWidget {
  static const posterWidth = 375.0;
  static const posterHeight = 520.0;

  final ContactCardData card;
  final String shareLink;

  const ContactCardSharePoster({
    super.key,
    required this.card,
    required this.shareLink,
  });

  @override
  Widget build(BuildContext context) {
    final initial = card.title.isNotEmpty ? card.title[0].toUpperCase() : '?';
    final accent = card.premium ? Colors.amber.shade700 : AppTheme.brandBlue;

    return SizedBox(
      width: posterWidth,
      height: posterHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: card.premium
                ? [const Color(0xFFFFF8E7), const Color(0xFFFFEFCC), Colors.white]
                : [const Color(0xFFE8F1FF), const Color(0xFFF5F9FF), Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.badge_outlined, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'AIM 个人名片',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F1F1F)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: card.premium ? Colors.amber.shade100 : AppTheme.brandBlue.withValues(alpha: 0.12),
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: card.premium ? Colors.amber.shade900 : AppTheme.brandBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      if (card.email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              card.userCode,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                            ),
                            if (card.premium) ...[
                              const SizedBox(height: 8),
                              PremiumLevelChip(levelName: card.levelName),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: QrImageView(
                      data: shareLink,
                      size: 88,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(color: Color(0xFF111111)),
                      dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF111111)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '微信扫码添加好友',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '或打开链接登录 AIM',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          shareLink.replaceFirst('https://', ''),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: AppTheme.brandBlue, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uint8List?> captureContactCardPoster(BuildContext context, ContactCardData card) async {
  final key = GlobalKey();
  final link = shareLinkForUserCode(card.userCode);
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -8000,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: key,
          child: ContactCardSharePoster(card: card, shareLink: link),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
