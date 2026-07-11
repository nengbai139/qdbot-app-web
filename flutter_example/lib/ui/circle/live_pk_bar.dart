import 'package:flutter/material.dart';

import 'circle_models.dart';

/// PK 比分条（礼物 QD 累计）
class LivePkBar extends StatelessWidget {
  const LivePkBar({super.key, required this.pk});

  final LivePk pk;

  @override
  Widget build(BuildContext context) {
    final total = pk.myScore + pk.opScore;
    final myFrac = total > 0 ? (pk.myScore / total).clamp(0.05, 0.95) : 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pk.myName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF5B9FFF), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('PK', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Text(
                  pk.opName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Color(0xFFFF6B8A), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(flex: (myFrac * 100).round().clamp(1, 99), child: const ColoredBox(color: Color(0xFF5B9FFF))),
                  Expanded(flex: ((1 - myFrac) * 100).round().clamp(1, 99), child: const ColoredBox(color: Color(0xFFE5484D))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${pk.myScore.toStringAsFixed(0)} QD', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text('${pk.opScore.toStringAsFixed(0)} QD', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
