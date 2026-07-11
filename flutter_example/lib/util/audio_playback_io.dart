import 'package:audioplayers/audioplayers.dart';

import 'media_url.dart';
import 'open_file_url.dart';

AudioPlayer? _player;
String? _url;
void Function()? _onStateChanged;

void bindPlatformPlaybackEvents(void Function() fn) {
  _onStateChanged = fn;
  _player ??= AudioPlayer()..onPlayerComplete.listen((_) => _onStateChanged?.call());
}

String? platformPlayingUrl() {
  final p = _player;
  if (p == null || p.state != PlayerState.playing) return null;
  return _url;
}

Future<void> platformToggle(String src, {String? filename}) async {
  _player ??= AudioPlayer();
  final p = _player!;
  if (_url == src && p.state == PlayerState.playing) {
    await p.pause();
    _onStateChanged?.call();
    return;
  }
  await p.stop();
  _url = src;
  await p.play(UrlSource(src));
  _onStateChanged?.call();
}

Future<void> platformStopAll() async {
  await _player?.stop();
  _url = null;
}

Future<void> platformDownload(String src, {String? filename}) async {
  await openRemoteFile(src, name: filename ?? 'voice.m4a');
}
