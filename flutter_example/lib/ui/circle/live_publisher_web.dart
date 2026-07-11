import 'dart:js_interop';

@JS('qdbotWhipPublish')
external JSPromise<JSString?> _whipPublish(String whipUrl, bool wantAudio, bool wantVideo, String backdropUrl);

@JS('qdbotWhipStop')
external void _whipStop();

@JS('qdbotWhipPublishing')
external bool _whipPublishing();

@JS('qdbotWhipAttachPreview')
external bool _whipAttachPreview();

@JS('qdbotWhipSwitchVideo')
external JSPromise<JSString?> _whipSwitchVideo(String mode);

@JS('qdbotWhipScreenSharing')
external bool _whipScreenSharing();

class LiveWebPublisher {
  static Future<String?> start(String whipUrl, {bool audio = true, bool video = true, String backdropUrl = ''}) async {
    final err = await _whipPublish(whipUrl, audio, video, backdropUrl).toDart;
    return err?.toDart;
  }

  static void attachPreview() {
    _whipAttachPreview();
  }

  static void stop() => _whipStop();

  static bool get publishing => _whipPublishing();

  static bool get screenSharing => _whipScreenSharing();

  static Future<String?> switchToScreen() async {
    final err = await _whipSwitchVideo('screen').toDart;
    return err?.toDart;
  }

  static Future<String?> switchToCamera() async {
    final err = await _whipSwitchVideo('camera').toDart;
    return err?.toDart;
  }
}
