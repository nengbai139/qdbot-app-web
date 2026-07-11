import 'package:flutter/material.dart';
import '../session.dart';
import 'app_theme.dart';
import 'home_page.dart';

class OnboardingPage extends StatefulWidget {
  final String token;
  final String userId;
  final String userCode;

  const OnboardingPage({super.key, required this.token, required this.userId, this.userCode = ''});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _page = PageController();
  int _index = 0;

  static const _pages = [
    (Icons.chat_bubble_outline, '消息', '与同事单聊、群聊。\n在群里 @同事 可唤醒 TA 的数字分身代答。'),
    (Icons.smart_toy_outlined, '助手', '私人 AI：查资料、写分析、调用技能。\n对话仅自己可见，不会发到群聊。'),
    (Icons.account_circle_outlined, '数字分身', '在「我的」开启数字分身并设置人设。\n被 @ 时由 AI 按你的人设回复。'),
  ];

  Future<void> _finish() async {
    await SessionStore.saveOnboardingDone();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(token: widget.token, userId: widget.userId, userCode: widget.userCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('跳过')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final (icon, title, body) = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 72, color: AppTheme.brandBlue),
                        const SizedBox(height: 28),
                        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.55, color: Colors.grey.shade700)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index ? AppTheme.brandBlue : Colors.grey.shade300,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_index < _pages.length - 1) {
                      _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_index < _pages.length - 1 ? '下一步' : '开始使用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
