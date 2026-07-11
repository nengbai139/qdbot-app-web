import 'package:flutter/material.dart';

import '../circle_models.dart';

/// 礼物荣誉感等级（与后端 catalog 价格对齐）
enum GiftHonorLevel { basic, sweet, star, epic, legend }

class GiftHonorStyle {
  final GiftHonorLevel level;
  final String badge;
  final List<Color> gradient;
  final Color border;
  final double borderWidth;
  final double emojiSize;
  final double nameSize;
  final List<BoxShadow> shadows;
  final bool fullScreenBurst;
  final int burstMs;

  const GiftHonorStyle({
    required this.level,
    required this.badge,
    required this.gradient,
    required this.border,
    this.borderWidth = 0,
    required this.emojiSize,
    required this.nameSize,
    this.shadows = const [],
    this.fullScreenBurst = false,
    this.burstMs = 0,
  });
}

GiftHonorStyle giftHonorFor(double amount) {
  if (amount >= 520) {
    return const GiftHonorStyle(
      level: GiftHonorLevel.legend,
      badge: '传奇',
      gradient: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFE5484D)],
      border: Color(0xFFFFE566),
      borderWidth: 2,
      emojiSize: 40,
      nameSize: 17,
      shadows: [
        BoxShadow(color: Color(0xFFFFD700), blurRadius: 18, spreadRadius: 1),
        BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
      ],
      fullScreenBurst: true,
      burstMs: 3200,
    );
  }
  if (amount >= 99) {
    return const GiftHonorStyle(
      level: GiftHonorLevel.epic,
      badge: '豪礼',
      gradient: [Color(0xFF9B59B6), Color(0xFFE5484D), Color(0xFFFF7A45)],
      border: Color(0xFFFFB347),
      borderWidth: 1.5,
      emojiSize: 34,
      nameSize: 16,
      shadows: [
        BoxShadow(color: Color(0xFFE5484D), blurRadius: 14),
        BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
      ],
      fullScreenBurst: true,
      burstMs: 2400,
    );
  }
  if (amount >= 10) {
    return const GiftHonorStyle(
      level: GiftHonorLevel.star,
      badge: '闪耀',
      gradient: [Color(0xFF4FACFE), Color(0xFF6A82FB), Color(0xFFE5484D)],
      border: Color(0xFF8EC5FF),
      borderWidth: 1,
      emojiSize: 30,
      nameSize: 15,
      shadows: [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
    );
  }
  if (amount >= 5) {
    return const GiftHonorStyle(
      level: GiftHonorLevel.sweet,
      badge: '甜蜜',
      gradient: [Color(0xFFFF9A9E), Color(0xFFFECFEF), Color(0xFFE5484D)],
      border: Color(0xFFFFB4C8),
      emojiSize: 26,
      nameSize: 14,
      shadows: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
    );
  }
  return const GiftHonorStyle(
    level: GiftHonorLevel.basic,
    badge: '暖心',
    gradient: [Color(0xFFFF7A45), Color(0xFFE5484D)],
    border: Colors.transparent,
    emojiSize: 22,
    nameSize: 14,
    shadows: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
  );
}

/// 从弹幕文案推断礼物价格（无 QD 时按名称匹配 catalog）
double giftAmountFromMessage(String text) {
  final m = RegExp(r'(\d+)\s*QD').firstMatch(text);
  if (m != null) return double.tryParse(m.group(1)!) ?? 1;
  for (final (name, price) in [('皇冠', 520), ('火箭', 99), ('星星', 10), ('糖果', 5), ('玫瑰', 1)]) {
    if (text.contains(name)) return price.toDouble();
  }
  return 1;
}

String giftSenderLabel(LiveGiftEvent gift) {
  final n = gift.senderName.trim();
  return n.isNotEmpty ? n : '观众';
}

/// 分级打赏飘条
class LiveGiftHonorBanner extends StatelessWidget {
  final LiveGiftEvent gift;
  final bool compact;

  const LiveGiftHonorBanner({super.key, required this.gift, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final style = giftHonorFor(gift.amount);
    final scale = compact ? 0.92 : 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: BoxConstraints(maxWidth: compact ? 260 : 320),
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 12 : 14) * scale,
        vertical: (compact ? 8 : 10) * scale,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: style.gradient.map((c) => c.withValues(alpha: 0.95)).toList()),
        borderRadius: BorderRadius.circular(style.level == GiftHonorLevel.legend ? 28 : 22),
        border: style.borderWidth > 0 ? Border.all(color: style.border, width: style.borderWidth) : null,
        boxShadow: style.shadows,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(gift.emoji, style: TextStyle(fontSize: style.emojiSize * scale)),
          SizedBox(width: 10 * scale),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GiftHonorBadge(label: style.badge, level: style.level),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        giftSenderLabel(gift),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: style.nameSize * scale,
                          shadows: style.level.index >= GiftHonorLevel.star.index
                              ? const [Shadow(color: Colors.black45, blurRadius: 4)]
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '送出 ${gift.giftName} · ${gift.amount.toStringAsFixed(0)} QD',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.94),
                    fontSize: (compact ? 11 : 12) * scale,
                    fontWeight: style.level.index >= GiftHonorLevel.epic.index ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GiftHonorBadge extends StatelessWidget {
  final String label;
  final GiftHonorLevel level;

  const GiftHonorBadge({super.key, required this.label, required this.level});

  @override
  Widget build(BuildContext context) {
    final bg = switch (level) {
      GiftHonorLevel.legend => const Color(0xFFFFD700),
      GiftHonorLevel.epic => const Color(0xFFFFB347),
      GiftHonorLevel.star => const Color(0xFF8EC5FF),
      GiftHonorLevel.sweet => const Color(0xFFFFB4C8),
      GiftHonorLevel.basic => Colors.white24,
    };
    final fg = level.index >= GiftHonorLevel.star.index ? Colors.black87 : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: level == GiftHonorLevel.basic ? 0.35 : 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg, height: 1.1),
      ),
    );
  }
}

/// 高价位全屏荣誉感（火箭/皇冠）
class LiveGiftHonorBurst extends StatefulWidget {
  final LiveGiftEvent? gift;

  const LiveGiftHonorBurst({super.key, required this.gift});

  @override
  State<LiveGiftHonorBurst> createState() => _LiveGiftHonorBurstState();
}

class _LiveGiftHonorBurstState extends State<LiveGiftHonorBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _kick();
  }

  @override
  void didUpdateWidget(covariant LiveGiftHonorBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gift?.amount != oldWidget.gift?.amount ||
        widget.gift?.senderName != oldWidget.gift?.senderName ||
        widget.gift?.giftName != oldWidget.gift?.giftName) {
      _kick();
    }
  }

  void _kick() {
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gift = widget.gift;
    if (gift == null) return const SizedBox.shrink();
    final style = giftHonorFor(gift.amount);
    if (!style.fullScreenBurst) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = Curves.easeOutCubic.transform(_ctrl.value);
          final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.1,
                  colors: [
                    style.gradient.first.withValues(alpha: 0.55 * fade),
                    Colors.black.withValues(alpha: 0.72 * fade),
                  ],
                ),
              ),
              child: Center(
                child: Transform.scale(
                  scale: 0.7 + t * 0.35,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (style.level == GiftHonorLevel.legend)
                        Icon(Icons.workspace_premium, color: Colors.amber.shade200, size: 36 * t),
                      Text(gift.emoji, style: TextStyle(fontSize: style.level == GiftHonorLevel.legend ? 72 : 56)),
                      const SizedBox(height: 10),
                      Text(
                        style.badge,
                        style: TextStyle(
                          color: style.level == GiftHonorLevel.legend ? const Color(0xFFFFD700) : const Color(0xFFFFB347),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        giftSenderLabel(gift),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '送出 ${gift.giftName}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15),
                      ),
                      Text(
                        '${gift.amount.toStringAsFixed(0)} QD',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void maybeTriggerGiftHonorBurst({
  required LiveGiftEvent gift,
  required ValueNotifier<LiveGiftEvent?> burstNotifier,
}) {
  final style = giftHonorFor(gift.amount);
  if (!style.fullScreenBurst) return;
  burstNotifier.value = gift;
  Future.delayed(Duration(milliseconds: style.burstMs), () {
    if (burstNotifier.value == gift) burstNotifier.value = null;
  });
}
