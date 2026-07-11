import 'dart:js_interop';

@JS('qdbotUnmuteAllLiveVideos')
external bool _unmuteAll();

@JS('qdbotLiveAudioNeedsUnmute')
external bool _needsUnmute();

class LiveWebAudio {
  static bool needsUnmute() => _needsUnmute();
  static bool unmuteAll() => _unmuteAll();
}
