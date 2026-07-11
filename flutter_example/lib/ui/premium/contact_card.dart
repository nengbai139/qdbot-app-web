import 'dart:convert';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'user_code_display.dart';

/// IM 名片消息 payload（contentType=contact_card）
class ContactCardData {
  final String userId;
  final String displayName;
  final String userCode;
  final String levelName;
  final String email;

  const ContactCardData({
    this.userId = '',
    this.displayName = '',
    required this.userCode,
    this.levelName = '',
    this.email = '',
  });

  bool get premium => levelName.isNotEmpty && levelName != '普通';

  String get title => displayName.isNotEmpty ? displayName : userCode;

  factory ContactCardData.fromJson(Map<String, dynamic> j) => ContactCardData(
        userId: (j['userId'] ?? '').toString(),
        displayName: (j['displayName'] ?? j['nickname'] ?? '').toString(),
        userCode: (j['userCode'] ?? '').toString(),
        levelName: (j['levelName'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        if (userId.isNotEmpty) 'userId': userId,
        if (displayName.isNotEmpty) 'displayName': displayName,
        'userCode': userCode,
        if (levelName.isNotEmpty) 'levelName': levelName,
        if (email.isNotEmpty) 'email': email,
      };
}

String encodeContactCard(ContactCardData card) => jsonEncode(card.toJson());

ContactCardData? tryParseContactCard(String raw, {String? contentType}) {
  final ct = (contentType ?? '').toLowerCase();
  if (ct == 'contact_card' || ct == 'user_card') {
    return _parseContactJson(raw) ?? tryParseContactCardFromShareText(raw);
  }
  if (raw.trimLeft().startsWith('{')) {
    final card = _parseContactJson(raw);
    if (card != null && card.userCode.isNotEmpty) return card;
  }
  return tryParseContactCardFromShareText(raw);
}

/// 旧版「复制分享文案 / 粘贴链接」→ 仍渲染为名片卡片
ContactCardData? tryParseContactCardFromShareText(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final hasShareLink = s.contains('userCode=') || RegExp(r'(?:靓号|展示码)\s+[A-Za-z0-9]').hasMatch(s);
  if (!hasShareLink) return null;

  String? code = RegExp(r'[?&]userCode=([A-Za-z0-9_-]+)').firstMatch(s)?.group(1);
  code ??= RegExp(r'(?:靓号|展示码)\s+([A-Za-z0-9_-]+)').firstMatch(s)?.group(1);
  if (code == null || code.isEmpty) return null;

  var displayName = '';
  var email = '';
  var levelName = '';
  final who = RegExp(r'加我\s*AIM[：:]\s*(.+?)\s*·\s*(?:靓号|展示码)').firstMatch(s);
  if (who != null) {
    final part = who.group(1)!.trim();
    if (part.contains('@')) {
      email = part;
    } else {
      displayName = part;
    }
  }
  final level = RegExp(r'（([^）]+)）').firstMatch(s);
  if (level != null) levelName = level.group(1)!;

  return ContactCardData(displayName: displayName, userCode: code, levelName: levelName, email: email);
}

ContactCardData? _parseContactJson(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final map = Map<String, dynamic>.from(j);
    final code = (map['userCode'] ?? '').toString();
    if (code.isEmpty) return null;
    return ContactCardData.fromJson(map);
  } catch (_) {
    return null;
  }
}

String contactCardPreviewLabel(ContactCardData card) {
  final who = card.title;
  return who.isNotEmpty ? '[名片] $who' : '[名片]';
}

/// 分享弹窗 / 聊天内展示的名片 UI
class ContactCardPreview extends StatelessWidget {
  final ContactCardData card;
  final bool compact;
  final VoidCallback? onTap;

  const ContactCardPreview({
    super.key,
    required this.card,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = card.title.isNotEmpty ? card.title[0].toUpperCase() : '?';
    final border = card.premium ? Colors.amber.shade300 : AppTheme.brandBlue.withValues(alpha: 0.35);
    final bg = card.premium ? Colors.amber.shade50 : Colors.white;

    final body = Container(
      width: compact ? double.infinity : 280,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('AIM 名片', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const Spacer(),
              Icon(Icons.badge_outlined, size: 16, color: Colors.grey.shade500),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Row(
            children: [
              CircleAvatar(
                radius: compact ? 22 : 26,
                backgroundColor: card.premium ? Colors.amber.shade100 : AppTheme.brandBlue.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w600,
                    color: card.premium ? Colors.amber.shade900 : AppTheme.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 16 : 17, fontWeight: FontWeight.w600),
                    ),
                    if (card.email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        card.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            card.userCode,
            style: TextStyle(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade900,
            ),
          ),
          if (card.premium) ...[
            const SizedBox(height: 8),
            PremiumLevelChip(levelName: card.levelName, compact: true),
          ],
          if (onTap != null) ...[
            const SizedBox(height: 10),
            Text('轻触查看 · 发消息', style: TextStyle(fontSize: 11, color: AppTheme.brandBlue)),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: body),
    );
  }
}

/// 聊天消息中的名片气泡
class ContactCardBubble extends StatelessWidget {
  final ContactCardData card;
  final bool isMe;
  final VoidCallback? onTap;

  const ContactCardBubble({
    super.key,
    required this.card,
    this.isMe = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ContactCardPreview(card: card, compact: true, onTap: onTap);
  }
}
