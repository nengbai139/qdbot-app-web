import 'dart:math';

import 'package:flutter/material.dart';

const kVoiceWaveBarCount = 28;

/// 将录音采样压成固定条数的波形（0–100）。
List<int> downsampleToWaveform(List<double> samples, {int bars = kVoiceWaveBarCount}) {
  if (samples.isEmpty) return List.filled(bars, 24);
  final out = <int>[];
  final step = samples.length / bars;
  for (var i = 0; i < bars; i++) {
    final start = (i * step).floor();
    final end = min(samples.length, ((i + 1) * step).ceil());
    var peak = 0.0;
    for (var j = start; j < end; j++) {
      if (samples[j] > peak) peak = samples[j];
    }
    out.add((peak * 100).round().clamp(8, 100));
  }
  return out;
}

List<int> parseWaveformList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => (e as num).round().clamp(0, 100)).toList();
}

/// 无波形数据时用时长 + url 生成稳定占位条（接收端旧消息）。
List<int> fallbackWaveform({required int durationMs, String? seed, int bars = kVoiceWaveBarCount}) {
  var h = seed?.hashCode ?? durationMs;
  return List.generate(bars, (i) {
    h = (h * 1103515245 + 12345 + i) & 0x7fffffff;
    return 16 + (h % 72);
  });
}

double voiceWaveAreaWidth(int durationMs) {
  final sec = ((durationMs / 1000).ceil()).clamp(1, 60);
  return 52 + sec * 2.4;
}

class VoiceWaveBars extends StatelessWidget {
  final List<int> levels;
  final Color color;
  final double width;
  final double height;

  const VoiceWaveBars({
    super.key,
    required this.levels,
    required this.color,
    this.width = 120,
    this.height = 22,
  });

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) return SizedBox(width: width, height: height);
    final n = levels.length;
    const gap = 1.5;
    final barW = max(2.0, (width - (n - 1) * gap) / n);
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: EdgeInsets.only(right: i < n - 1 ? gap : 0),
              child: Container(
                width: barW,
                height: max(3.0, height * (0.22 + 0.78 * levels[i] / 100)),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
