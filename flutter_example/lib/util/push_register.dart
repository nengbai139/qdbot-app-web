import 'package:flutter/foundation.dart';
import '../api/push_api.dart';
import '../session.dart';
import 'firebase_push.dart';
import 'firebase_push_resolver_stub.dart'
    if (dart.library.io) 'firebase_push_resolver_io.dart';

String pushPlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.android:
      return 'android';
    default:
      return 'web';
  }
}

Future<void> initFirebasePushIfEnabled() async {
  if (!kFirebasePushEnabled || kIsWeb) return;
  await resolveFirebaseToken();
}

Future<String?> resolveNativePushToken() async {
  if (!kFirebasePushEnabled || kIsWeb) return null;
  return resolveFirebaseToken();
}

Future<void> registerPushIfNeeded({required String authToken, required String userId}) async {
  if (userId.isEmpty) return;
  await initFirebasePushIfEnabled();
  final deviceId = await SessionStore.loadOrCreateDeviceId();
  final platform = pushPlatform();
  final native = await resolveNativePushToken();
  final pushToken = native ?? 'device:$platform:$deviceId';
  final saved = await SessionStore.loadPushToken();
  if (saved == pushToken) return;

  try {
    final resp = await PushApi(authToken).register(
      userId: userId,
      deviceId: deviceId,
      platform: platform,
      token: pushToken,
    );
    if (resp.statusCode == 200) {
      await SessionStore.savePushToken(pushToken);
      await PushApi(authToken).setDeviceNotify(enabled: true);
    }
  } catch (_) {}
}

Future<void> unregisterPush({required String authToken, required String userId}) async {
  final pushToken = await SessionStore.loadPushToken();
  if (userId.isEmpty || pushToken == null || pushToken.isEmpty) return;
  try {
    await PushApi(authToken).unregister(userId: userId, token: pushToken);
  } catch (_) {}
  await SessionStore.clearPushToken();
}

bool isPlaceholderPushToken(String? token) => token != null && token.startsWith('device:');

bool get nativePushConfigured => kFirebasePushEnabled;
