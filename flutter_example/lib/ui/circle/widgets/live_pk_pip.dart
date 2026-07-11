import 'package:flutter/material.dart';

import '../circle_models.dart';
import '../live_player.dart';

/// PK 对手小窗（手机竖屏用 PiP，避免双 HLS 全屏黑屏）
class LivePkOpponentPiP extends StatelessWidget {
  final LivePk pk;

  const LivePkOpponentPiP({super.key, required this.pk});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (pk.opPlayUrl.isNotEmpty)
            LivePlayer(key: ValueKey('pk-pip-${pk.opPlayUrl}'), url: pk.opPlayUrl)
          else
            const ColoredBox(
              color: Colors.black54,
              child: Center(child: Text('缓冲中…', style: TextStyle(color: Colors.white70, fontSize: 10))),
            ),
          Container(
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.all(4),
            child: Text(
              pk.opName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
            ),
          ),
        ],
      ),
    );
  }
}
