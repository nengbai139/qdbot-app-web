import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../util/voice_waveform.dart';
import 'im_media.dart';
import 'voice_recorder.dart';

class WebVoiceRecorderBackend implements VoiceRecorderBackend {
  web.MediaStream? _stream;
  web.MediaRecorder? _mediaRecorder;
  web.AudioContext? _audioCtx;
  web.AnalyserNode? _analyser;
  final _chunks = <web.Blob>[];
  Completer<void>? _stopCompleter;
  String _mimeType = 'audio/webm;codecs=opus';
  String _ext = 'webm';
  Timer? _levelTimer;
  final _levelController = StreamController<double>.broadcast();
  final _samples = <double>[];

  @override
  Stream<double>? get levelStream => _levelController.stream;

  static String? _pickMime() {
    // ponytail: IM 语音优先 m4a，Safari / iOS Web 对 webm 支持差
    const candidates = <(String, String)>[
      ('audio/mp4;codecs=mp4a.40.2', 'm4a'),
      ('audio/mp4', 'm4a'),
      ('audio/webm;codecs=opus', 'webm'),
      ('audio/webm', 'webm'),
      ('audio/ogg;codecs=opus', 'ogg'),
    ];
    for (final c in candidates) {
      if (web.MediaRecorder.isTypeSupported(c.$1)) return c.$1;
    }
    return null;
  }

  @override
  Future<void> start() async {
    final mime = _pickMime();
    if (mime == null) {
      throw Exception('当前浏览器不支持录音（请用 Chrome / Edge / Safari 最新版）');
    }
    _mimeType = mime;
    _ext = mime.contains('mp4') ? 'm4a' : (mime.contains('ogg') ? 'ogg' : 'webm');
    _samples.clear();

    final constraints = web.MediaStreamConstraints(audio: {true}.toJSBox);
    try {
      _stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
    } catch (e) {
      throw Exception('无法访问麦克风：$e');
    }

    _chunks.clear();
    final mr = web.MediaRecorder(
      _stream!,
      web.MediaRecorderOptions(mimeType: _mimeType),
    );
    mr.ondataavailable = ((web.BlobEvent event) {
      if (event.data.size > 0) _chunks.add(event.data);
    }).toJS;
    mr.onstop = ((web.Event _) {
      final c = _stopCompleter;
      if (c != null && !c.isCompleted) c.complete();
    }).toJS;
    mr.start(250);
    _mediaRecorder = mr;

    _audioCtx = web.AudioContext();
    final source = _audioCtx!.createMediaStreamSource(_stream!);
    _analyser = _audioCtx!.createAnalyser();
    _analyser!.fftSize = 256;
    source.connect(_analyser!);
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _pollLevel());
  }

  void _pollLevel() {
    final analyser = _analyser;
    if (analyser == null) return;
    final buf = Float32List(analyser.fftSize);
    analyser.getFloatTimeDomainData(buf.toJS);
    var sum = 0.0;
    for (final v in buf) {
      sum += v * v;
    }
    final norm = (sqrt(sum / buf.length) * 10).clamp(0.0, 1.0);
    _samples.add(norm);
    if (!_levelController.isClosed) _levelController.add(norm);
  }

  @override
  Future<PickedFileBytes?> stop({required int durationMs}) async {
    final mr = _mediaRecorder;
    if (mr == null || mr.state == 'inactive') return null;

    _stopCompleter = Completer<void>();
    mr.stop();
    try {
      await _stopCompleter!.future.timeout(const Duration(seconds: 8));
    } catch (_) {}

    final chunks = List<web.Blob>.from(_chunks);
    final waveform = downsampleToWaveform(_samples);
    _release();

    if (chunks.isEmpty) return null;
    final blob = web.Blob(
      chunks.toJS,
      web.BlobPropertyBag(type: _mimeType),
    );
    final buf = await blob.arrayBuffer().toDart;
    final bytes = buf.toDart.asUint8List();
    if (bytes.isEmpty) return null;
    return PickedFileBytes(
      bytes,
      name: 'voice.$_ext',
      durationMs: durationMs,
      waveform: waveform,
    );
  }

  @override
  Future<void> cancel() async {
    try {
      if (_mediaRecorder?.state == 'recording') {
        _mediaRecorder?.stop();
      }
    } catch (_) {}
    _release();
  }

  @override
  void dispose() => _release();

  void _release() {
    _levelTimer?.cancel();
    _levelTimer = null;
    _mediaRecorder?.ondataavailable = null;
    _mediaRecorder?.onstop = null;
    _mediaRecorder = null;
    _chunks.clear();
    _analyser = null;
    try {
      _audioCtx?.close();
    } catch (_) {}
    _audioCtx = null;
    final tracks = _stream?.getAudioTracks().toDart ?? <web.MediaStreamTrack>[];
    for (final t in tracks) {
      t.stop();
    }
    _stream = null;
    _samples.clear();
  }
}

VoiceRecorderBackend createVoiceRecorderBackend() => WebVoiceRecorderBackend();
