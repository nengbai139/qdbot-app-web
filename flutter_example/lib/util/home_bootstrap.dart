import '../session.dart';

/// ponytail: 限制 HomePage 级初始化 API 频率（WS 重连 / Safari 整页重载）
class HomeBootstrap {
  static Future<bool> shouldInit(String token) async {
    if (await SessionStore.shouldSkipHomeBootstrap(token)) return false;
    await SessionStore.markHomeBootstrapped(token);
    return true;
  }

  static Future<void> reset() async {
    await SessionStore.clearHomeBootstrap();
    await SessionStore.clearTabCache();
  }
}
