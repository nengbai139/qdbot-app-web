import 'dart:async';

import 'package:record/record.dart';

import '../util/path_bytes.dart';
import '../util/voice_waveform.dart';
import 'im_media.dart';
import 'voice_recorder.dart';
import 'voice_record_helper.dart';

class IoVoiceRecorderBackend implements VoiceRecorderBackend {
  final _recorder = AudioRecorder();
  VoiceRecordFormat? _format;
  String? _path;
  StreamSubscription<Amplitude>? _ampSub;
  final _levelController = StreamController<double>.broadcast();
  final _samples = <double>[];

  @override
  Stream<double>? get levelStream => _levelController.stream;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('需要麦克风权限');
    }
    _format = await pickVoiceRecordFormat(_recorder);
    if (_format == null) {
      throw Exception('当前设备不支持录音');
    }
    _path = 'voice_${DateTime.now().millisecondsSinceEpoch}.${_format!.extension}';
    _samples.clear();
    await _ampSub?.cancel();
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((amp) {
      final norm = ((amp.current + 50) / 50).clamp(0.0, 1.0);
      _samples.add(norm);
      if (!_levelController.isClosed) _levelController.add(norm);
    });
    await _recorder.start(_format!.config, path: _path!);
    if (!await _recorder.isRecording()) {
      throw Exception('无法开始录音');
    }
  }

  @override
  Future<PickedFileBytes?> stop({required int durationMs}) async {
    await _ampSub?.cancel();
    _ampSub = null;
    final filePath = await _recorder.stop() ?? _path;
    if (filePath == null) return null;
    final bytes = await readPathBytes(filePath);
    if (bytes == null || bytes.isEmpty) return null;
    return PickedFileBytes(
      bytes,
      name: 'voice.${_format?.extension ?? 'm4a'}',
      durationMs: durationMs,
      waveform: downsampleToWaveform(_samples),
    );
  }

  @override
  Future<void> cancel() async {
    await _ampSub?.cancel();
    _ampSub = null;
    _samples.clear();
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _levelController.close();
    _recorder.dispose();
  }
}

VoiceRecorderBackend createVoiceRecorderBackend() => IoVoiceRecorderBackend();
