import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/auth_api.dart';
import '../register_page.dart';
import '../session.dart';
import '../util/tab_data_cache.dart';
import 'circle/meeting_deep_link.dart';
import 'premium/premium_deep_link.dart';
import 'home_page.dart';
import 'onboarding_page.dart';

String _loginErrorMessage(http.Response resp) {
  if (resp.statusCode == 401) return '邮箱或密码错误';
  try {
    final err = jsonDecode(resp.body);
    if (err is Map && err['error'] != null) return err['error'].toString();
  } catch (_) {}
  return '登录失败 (${resp.statusCode})';
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _verifyCode = TextEditingController();
  final _deviceIdController = TextEditingController();
  String _platform = kIsWeb ? 'web' : 'ios';
  bool _loading = false;
  bool _restoringSession = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deviceIdController.text = 'device_${DateTime.now().millisecondsSinceEpoch}';
    final pendingCode = parseUserCodeFromUri(Uri.base);
    if (pendingCode != null) SessionStore.savePendingUserCode(pendingCode);
    final pendingMeeting = parseMeetingRoomFromUri(Uri.base);
    if (pendingMeeting != null) {
      SessionStore.savePendingMeetingRoom(pendingMeeting);
      SessionStore.savePendingMeetingPasscode(parseMeetingPasscodeFromUri(Uri.base));
    }
    // ponytail: 立即显示登录表单，后台恢复会话；避免整页转圈像「自动刷新」
    _restoreSessionInBackground();
  }

  Future<void> _goHome({required String token, required String userId, String userCode = ''}) async {
    await TabDataCache.restore(token);
    final done = await SessionStore.loadOnboardingDone();
    if (!mounted) return;
    final page = done
        ? HomePage(token: token, userId: userId, userCode: userCode)
        : OnboardingPage(token: token, userId: userId, userCode: userCode);
    await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _restoreSessionInBackground() async {
    final email = await SessionStore.loadLastEmail();
    final platform = await SessionStore.loadLastPlatform();
    if (!mounted) return;
    if (email != null) _emailController.text = email;
    if (platform != null) {
      _platform = platform;
    } else if (kIsWeb) {
      _platform = 'web';
    }

    final session = await SessionStore.load();
    if (!mounted) return;
    if (session == null) return;

    setState(() => _restoringSession = true);
    try {
      await _goHome(
        token: session.token,
        userId: session.userId.isNotEmpty ? session.userId : session.token,
        userCode: session.userCode,
      );
    } catch (_) {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _verifyCode.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _sendLoginCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) { setState(() => _error = '请先输入邮箱'); return; }
    try {
      final resp = await authApi.sendLoginCode(email);
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('验证码已发送'), backgroundColor: Colors.green));
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await authApi.login(
        email: _emailController.text,
        password: _passwordController.text,
        deviceId: _deviceIdController.text,
        platform: _platform,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final token = data['token'] as String;
        final email = _emailController.text.trim();
        await SessionStore.saveLastEmail(email);
        await SessionStore.saveLastPlatform(_platform);
        await SessionStore.save(
          token: token,
          userId: (data['userId'] ?? email).toString(),
          userCode: (data['userCode'] ?? '').toString(),
        );
        if (mounted) {
          await _goHome(
            token: token,
            userId: (data['userId'] ?? _emailController.text).toString(),
            userCode: (data['userCode'] ?? '').toString(),
          );
        }
      } else {
        setState(() => _error = _loginErrorMessage(resp));
      }
    } catch (e) {
      setState(() => _error = '网络错误: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QDBot App 登录'),
        actions: [
          if (_restoringSession)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: '邮箱',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(controller: _verifyCode, decoration: const InputDecoration(labelText: '* 验证码', hintText: '邮箱验证码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.verified_user)))),
              const SizedBox(width: 12),
              SizedBox(height: 56, child: ElevatedButton(onPressed: _sendLoginCode, child: const Text('获取'))),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              decoration: const InputDecoration(
                labelText: '平台',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
              items: const [
                DropdownMenuItem(value: 'ios', child: Text('iOS')),
                DropdownMenuItem(value: 'android', child: Text('Android')),
                DropdownMenuItem(value: 'web', child: Text('Web')),
                DropdownMenuItem(value: 'pad', child: Text('Pad')),
              ],
              onChanged: (v) {
                setState(() => _platform = v!);
                SessionStore.saveLastPlatform(v!);
              },
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
              child: const Text('没有账号？去注册'),
            ),
          ],
        ),
      ),
    );
  }
}

