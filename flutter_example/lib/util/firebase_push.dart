/// Optional Firebase push — not enabled by default (needs google-services / GoogleService-Info).
///
/// To enable:
/// 1. pubspec: firebase_core, firebase_messaging
/// 2. Platform config files per Firebase console
/// 3. In push_register.dart `resolveNativePushToken`:
///    `return FirebaseMessaging.instance.getToken();`
/// 4. Set [kFirebasePushEnabled] = true
/// 5. Server: configure APNs/FCM env vars on qdbot_system
library;

const bool kFirebasePushEnabled = false;

/// 接入 Firebase 后设为 true；Web 仍走浏览器通知。
const List<String> kFirebaseSetupSteps = [
  'pubspec 添加 firebase_core + firebase_messaging',
  'iOS: GoogleService-Info.plist + Push Notifications capability',
  'Android: google-services.json + apply google-services plugin',
  'push_register.dart → resolveNativePushToken 返回 getToken()',
  '本文件 kFirebasePushEnabled = true',
  'qdbot_system .env 配置 FCM/APNs',
];
