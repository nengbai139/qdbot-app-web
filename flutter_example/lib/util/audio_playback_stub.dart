void bindPlatformPlaybackEvents(void Function() fn) {}

Future<void> platformToggle(String src, {String? filename}) async =>
    throw UnsupportedError('audio playback unavailable');

Future<void> platformStopAll() async {}

Future<void> platformDownload(String src, {String? filename}) async =>
    throw UnsupportedError('audio download unavailable');

String? platformPlayingUrl() => null;
