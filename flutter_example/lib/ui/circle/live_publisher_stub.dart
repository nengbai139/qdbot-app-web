class LiveWebPublisher {
  static Future<String?> start(String whipUrl, {bool audio = true, bool video = true, String backdropUrl = ''}) async =>
      throw UnsupportedError('网页推流仅支持 Web');

  static void attachPreview() {}

  static void stop() {}

  static bool get publishing => false;

  static bool get screenSharing => false;

  static Future<String?> switchToScreen() async => '仅网页版支持屏幕共享';

  static Future<String?> switchToCamera() async => '仅网页版支持屏幕共享';
}
