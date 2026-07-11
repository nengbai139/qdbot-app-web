import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Timer? _cycleTimer;
Timer? _secondBurstTimer;
web.AudioContext? _ringCtx;
web.GainNode? _ringGain;
web.OscillatorNode? _oscA;
web.OscillatorNode? _oscB;

/// 经典双音电话铃（440+480Hz 正弦，双脉冲 + 长静音），比方波柔和。
/// ponytail: 无 mp3 资源；要定制铃声可换 assets/audio/ring.mp3 + AudioElement.loop
void startIncomingRing() {
  stopIncomingRing();
  try {
    final ctx = web.AudioContext();
    _ringCtx = ctx;

    final master = ctx.createGain();
    master.gain.value = 0;
    master.connect(ctx.destination);
    _ringGain = master;

    _oscA = _toneOsc(ctx, 440);
    _oscB = _toneOsc(ctx, 480);
    _oscA!.connect(master);
    _oscB!.connect(master);
    _oscA!.start();
    _oscB!.start();

    unawaited(ctx.resume().toDart);

    void burst() {
      final g = _ringGain;
      final c = _ringCtx;
      if (g == null || c == null) return;
      final t = c.currentTime;
      final param = g.gain;
      param.cancelScheduledValues(t);
      param.setValueAtTime(0, t);
      param.linearRampToValueAtTime(0.14, t + 0.05);
      param.setValueAtTime(0.14, t + 0.38);
      param.linearRampToValueAtTime(0, t + 0.48);
    }

    void cycle() {
      burst();
      _secondBurstTimer?.cancel();
      _secondBurstTimer = Timer(const Duration(milliseconds: 620), burst);
    }

    cycle();
    _cycleTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) => cycle());
  } catch (_) {}
}

web.OscillatorNode _toneOsc(web.AudioContext ctx, double hz) {
  final o = ctx.createOscillator();
  o.type = 'sine';
  o.frequency.value = hz;
  return o;
}

void stopIncomingRing() {
  _cycleTimer?.cancel();
  _cycleTimer = null;
  _secondBurstTimer?.cancel();
  _secondBurstTimer = null;
  for (final o in [_oscA, _oscB]) {
    try {
      o?.stop();
    } catch (_) {}
  }
  _oscA = null;
  _oscB = null;
  _ringGain = null;
  try {
    _ringCtx?.close();
  } catch (_) {}
  _ringCtx = null;
}
