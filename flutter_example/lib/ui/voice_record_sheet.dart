import 'dart:async';

import 'package:flutter/material.dart';

import '../util/voice_waveform.dart';
import 'im_media.dart';
import 'voice_recorder.dart';
import 'voice_recorder_platform.dart';

/// 录音面板（点击开始 / 停止发送）
Future<PickedFileBytes?> showVoiceRecordSheet(BuildContext context) {
  return showModalBottomSheet<PickedFileBytes>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _VoiceRecordSheet(),
  );
}

class _VoiceRecordSheet extends StatefulWidget {
  const _VoiceRecordSheet();

  @override
  State<_VoiceRecordSheet> createState() => _VoiceRecordSheetState();
}

class _VoiceRecordSheetState extends State<_VoiceRecordSheet> {
  late final VoiceRecorderBackend _backend = createVoiceRecorderBackend();
  bool _recording = false;
  bool _busy = false;
  int _elapsedMs = 0;
  Timer? _timer;
  StreamSubscription<double>? _levelSub;
  List<int> _liveWave = List.filled(kVoiceWaveBarCount, 12);
  String _status = '点「开始录音」，浏览器会弹出麦克风授权';

  @override
  void initState() {
    super.initState();
    _levelSub = _backend.levelStream?.listen(_onLevel);
  }

  void _onLevel(double level) {
    if (!mounted || !_recording) return;
    setState(() {
      _liveWave = [..._liveWave.sublist(1), (level * 100).round().clamp(8, 100)];
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levelSub?.cancel();
    unawaited(_backend.cancel());
    _backend.dispose();
    super.dispose();
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _status = msg);
  }

  Future<void> _start() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _status = '正在请求麦克风…';
    });
    try {
      await _backend.start();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsedMs = 0;
        _liveWave = List.filled(kVoiceWaveBarCount, 12);
        _status = '录音中，说完点「发送」';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedMs += 1000);
        if (_elapsedMs >= 60000) _stop(send: true);
      });
    } catch (e) {
      _setStatus('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop({required bool send}) async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      if (!send) {
        await _backend.cancel();
        if (mounted) Navigator.pop(context);
        return;
      }
      _setStatus('正在处理录音…');
      final picked = await _backend.stop(durationMs: _elapsedMs);
      if (!mounted) return;
      setState(() => _recording = false);
      if (picked == null || picked.bytes.isEmpty) {
        _setStatus('录音为空，请重试');
        return;
      }
      Navigator.pop(context, picked);
    } catch (e) {
      _setStatus('录音失败: $e');
      setState(() => _recording = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _timeLabel {
    final s = (_elapsedMs / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final canTap = !_busy;
    final statusColor = _status.contains('失败') || _status.contains('无法') || _status.contains('不支持')
        ? Colors.red.shade700
        : Colors.grey.shade600;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _recording ? '录音中 $_timeLabel' : '语音消息',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.35, color: statusColor),
            ),
            if (_recording) ...[
              const SizedBox(height: 14),
              VoiceWaveBars(
                levels: _liveWave,
                color: Colors.red.shade400,
                width: 220,
                height: 28,
              ),
            ],
            const SizedBox(height: 16),
            Icon(
              _recording ? Icons.mic : Icons.mic_none_outlined,
              size: 56,
              color: _recording ? Colors.red : Colors.grey,
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: canTap ? () => _stop(send: false) : null,
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: canTap ? (_recording ? () => _stop(send: true) : _start) : null,
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic),
                  label: Text(_recording ? '发送' : '开始录音'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
