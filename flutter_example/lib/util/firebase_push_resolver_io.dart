import 'firebase_push.dart';

Future<String?> resolveFirebaseToken() async {
  if (!kFirebasePushEnabled) return null;
  // ponytail: 配置 Firebase 后取消注释并添加 firebase_options.dart
  // import 'package:firebase_core/firebase_core.dart';
  // import 'package:firebase_messaging/firebase_messaging.dart';
  // await Firebase.initializeApp();
  // return FirebaseMessaging.instance.getToken();
  return null;
}
