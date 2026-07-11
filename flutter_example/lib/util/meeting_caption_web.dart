import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('qdbotMeetingCaptionStart')
external JSString? _captionStart(JSString lang);

@JS('qdbotMeetingCaptionStop')
external void _captionStop();

@JS('qdbotMeetingCaptionDrain')
external JSString _captionDrain();

typedef MeetingCaptionCallback = void Function(String text, bool isFinal, {String? error});

class MeetingCaptionEngine {
  Timer? _poll;
  MeetingCaptionCallback? _onResult;
  var _running = false;

  bool get running => _running;

  String? start({String lang = 'zh-CN', MeetingCaptionCallback? onResult}) {
    _onResult = onResult;
    final err = _captionStart(lang.toJS)?.toDart;
    if (err != null && err.isNotEmpty) return err;
    _running = true;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _drain());
    return null;
  }

  void _drain() {
    final raw = _captionDrain().toDart;
    if (raw.isEmpty || raw == '[]') return;
    try {
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final err = (m['error'] ?? '').toString();
        if (err.isNotEmpty) {
          _onResult?.call('', true, error: err);
          continue;
        }
        final text = (m['text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        _onResult?.call(text, m['final'] == true);
      }
    } catch (_) {}
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
    _running = false;
    _onResult = null;
    _captionStop();
  }
}
