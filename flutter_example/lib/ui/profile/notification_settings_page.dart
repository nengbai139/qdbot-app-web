import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../api/push_api.dart';
import '../../api/user_api.dart';
import '../../session.dart';
import '../../util/firebase_push.dart';
import '../../util/push_register.dart';
import '../../util/web_notify.dart';

class NotificationSettingsPage extends StatefulWidget {
  final String token;

  const NotificationSettingsPage({super.key, required this.token});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPrefs _prefs = const NotificationPrefs();
  String? _pushToken;
  Map<String, dynamic>? _pushStatus;
  bool _loading = true;
  bool _saving = false;
  bool _devicePush = true;
  bool _devicePushSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await UserApi(widget.token).getNotifications();
      final push = await SessionStore.loadPushToken();
      Map<String, dynamic>? status;
      try {
        status = await PushApi(widget.token).status();
      } catch (_) {}
      await SessionStore.saveWebNotifyEnabled(prefs.webNotify);
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _pushToken = push;
          _pushStatus = status;
          _devicePush = status?['deviceNotify'] != false;
          _loading = false;
        });
      }
    } catch (_) {
      final on = await SessionStore.loadWebNotifyEnabled();
      final push = await SessionStore.loadPushToken();
      if (mounted) {
        setState(() {
          _prefs = NotificationPrefs(webNotify: on);
          _pushToken = push;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(NotificationPrefs next) async {
    setState(() {
      _prefs = next;
      _saving = true;
    });
    await SessionStore.saveWebNotifyEnabled(next.webNotify);
    try {
      final saved = await UserApi(widget.token).updateNotifications(next);
      if (mounted) setState(() => _prefs = saved);
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _setDevicePush(bool enabled) async {
    setState(() {
      _devicePush = enabled;
      _devicePushSaving = true;
    });
    try {
      if (enabled && _pushToken == null) {
        await registerPushIfNeeded(authToken: widget.token, userId: (await SessionStore.load())?.userId ?? '');
      }
      await PushApi(widget.token).setDeviceNotify(enabled: enabled);
      if (mounted) {
        _pushStatus = await PushApi(widget.token).status();
        _pushToken = await SessionStore.loadPushToken();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _devicePush = !enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录并完成推送注册'), duration: Duration(seconds: 2)),
        );
      }
    }
    if (mounted) setState(() => _devicePushSaving = false);
  }

  String _pushSubtitle() {
    if (nativePushConfigured) return 'Firebase 已接入';
    if (kIsWeb) return 'Web 端使用上方浏览器通知';
    if (_pushToken == null) return '未注册';
    final devices = _pushStatus?['deviceTokens'];
    final real = _pushStatus?['realTokens'];
    final deviceHint = devices is num && devices > 0 ? ' · ${devices.toInt()} 台设备' : '';
    final realHint = real is num && real > 0 ? '（${real.toInt()} 真推送）' : '';
    if (isPlaceholderPushToken(_pushToken)) {
      final configured = _pushStatus?['configured'] == true;
      if (!configured) {
        return '占位 token$deviceHint（服务端未配置 APNs/FCM）';
      }
      return '占位 token$deviceHint（接入 Firebase 后可收真实推送$realHint）';
    }
    return '已注册真实推送$deviceHint$realHint';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息通知'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (kIsWeb)
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('Web 浏览器通知'),
                    subtitle: const Text('标签页在后台时弹出提醒（已同步云端）'),
                    value: _prefs.webNotify,
                    onChanged: (v) async {
                      if (v) {
                        final granted = await requestWebNotifyPermission();
                        if (!granted && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('浏览器未授权通知'), duration: Duration(seconds: 3)),
                          );
                        }
                      }
                      await _save(_prefs.copyWith(webNotify: v));
                    },
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.chat_outlined),
                  title: const Text('IM 消息通知'),
                  subtitle: const Text('单聊/群聊新消息'),
                  value: _prefs.imNotify,
                  onChanged: (v) => _save(_prefs.copyWith(imNotify: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.alternate_email),
                  title: const Text('@ 提及提醒'),
                  value: _prefs.mentionNotify,
                  onChanged: (v) => _save(_prefs.copyWith(mentionNotify: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.smart_toy_outlined),
                  title: const Text('AI 助手通知'),
                  value: _prefs.aiNotify,
                  onChanged: (v) => _save(_prefs.copyWith(aiNotify: v)),
                ),
                if (kIsWeb)
                  const ListTile(
                    leading: Icon(Icons.event_busy_outlined),
                    title: Text('订阅到期提醒'),
                    subtitle: const Text('开启浏览器通知后，AI Pro 到期前 7 天每日提醒一次；原生端需配置 APNs/FCM'),
                  ),
                if (_pushStatus != null)
                  ListTile(
                    leading: Icon(
                      Icons.cloud_done_outlined,
                      color: _pushStatus!['configured'] == true ? Colors.green : Colors.grey,
                    ),
                    title: const Text('推送服务'),
                    subtitle: Text(
                      'APNs ${_pushStatus!['apns'] == true ? '✓' : '—'} · FCM ${_pushStatus!['fcm'] == true ? '✓' : '—'}',
                    ),
                  ),
                ListTile(
                  leading: Icon(Icons.sync, color: _pushToken != null ? Colors.green : Colors.grey),
                  title: const Text('本机推送注册'),
                  subtitle: Text(_pushSubtitle()),
                ),
                if (!kIsWeb)
                  SwitchListTile(
                    secondary: const Icon(Icons.phonelink_ring_outlined),
                    title: const Text('本机接收推送'),
                    subtitle: const Text('关闭后本设备不再收到 APNs/FCM（其它设备不受影响）'),
                    value: _devicePush,
                    onChanged: _devicePushSaving || _pushToken == null ? null : _setDevicePush,
                  ),
                if (!kIsWeb && !nativePushConfigured)
                  ExpansionTile(
                    leading: const Icon(Icons.integration_instructions_outlined),
                    title: const Text('Firebase 接入步骤'),
                    subtitle: const Text('未启用 · 见 lib/util/firebase_push.dart'),
                    children: kFirebaseSetupSteps
                        .map((s) => ListTile(dense: true, title: Text(s, style: const TextStyle(fontSize: 13))))
                        .toList(),
                  ),
              ],
            ),
    );
  }
}

extension on NotificationPrefs {
  NotificationPrefs copyWith({bool? webNotify, bool? imNotify, bool? mentionNotify, bool? aiNotify}) =>
      NotificationPrefs(
        webNotify: webNotify ?? this.webNotify,
        imNotify: imNotify ?? this.imNotify,
        mentionNotify: mentionNotify ?? this.mentionNotify,
        aiNotify: aiNotify ?? this.aiNotify,
      );
}

Future<void> syncNotificationPrefsFromServer(String token) async {
  try {
    final prefs = await UserApi(token).getNotifications();
    await SessionStore.saveWebNotifyEnabled(prefs.webNotify);
  } catch (_) {}
}
