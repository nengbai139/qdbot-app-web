import 'package:flutter/material.dart';
import '../../session.dart';
import '../onboarding_page.dart';

class AboutPage extends StatelessWidget {
  final String token;
  final String userId;
  final String userCode;

  const AboutPage({
    super.key,
    required this.token,
    required this.userId,
    this.userCode = '',
  });

  Future<void> _replayOnboarding(BuildContext context) async {
    await SessionStore.clearOnboardingDone();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingPage(token: token, userId: userId, userCode: userCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Icon(Icons.smart_toy, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                const Text('QDBot App', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('版本 1.0.0', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '跨平台 IM + AI 智能助手。支持单聊群聊、私人 AI 助手与数字分身。',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('帮助与反馈'),
            subtitle: const Text('如有问题请联系管理员'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'QDBot App',
              applicationVersion: '1.0.0',
              children: const [Text('跨平台 IM + AI 智能助手')],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('重新观看引导'),
            onTap: () => _replayOnboarding(context),
          ),
        ],
      ),
    );
  }
}
