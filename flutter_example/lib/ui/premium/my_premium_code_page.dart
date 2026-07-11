import 'package:flutter/material.dart';
import '../../api/user_api.dart';
import '../profile/payment/payment_hub_page.dart';
import 'premium_deep_link.dart';
import 'share_util.dart';
import 'user_code_display.dart';

/// 我的靓号：展示码、等级、分享链接
class MyPremiumCodePage extends StatefulWidget {
  final String token;
  final String userId;
  final String fallbackUserCode;

  const MyPremiumCodePage({
    super.key,
    required this.token,
    required this.userId,
    this.fallbackUserCode = '',
  });

  @override
  State<MyPremiumCodePage> createState() => _MyPremiumCodePageState();
}

class _MyPremiumCodePageState extends State<MyPremiumCodePage> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await UserApi(widget.token).getProfile();
      if (mounted) setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _userCode {
    final c = _profile?.userCode ?? '';
    return c.isNotEmpty ? c : widget.fallbackUserCode;
  }

  @override
  Widget build(BuildContext context) {
    final code = _userCode;
    final levelName = _profile?.levelName ?? '';
    final premium = _profile?.premium == true;
    final link = code.isNotEmpty ? shareLinkForUserCode(code) : '';

    return Scaffold(
      appBar: AppBar(title: const Text('我的靓号')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          code.isNotEmpty ? code : '暂无展示码',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        if (levelName.isNotEmpty && levelName != '普通') ...[
                          const SizedBox(height: 12),
                          Center(child: PremiumLevelChip(levelName: levelName)),
                        ],
                        if (_profile?.levelDesc.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(_profile!.levelDesc, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (code.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: () => shareUserCode(
                      context,
                      token: widget.token,
                      userId: widget.userId,
                      userCode: code,
                      levelName: levelName,
                      displayName: _profile?.nickname ?? '',
                      email: _profile?.email ?? '',
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('分享名片'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => copyUserCode(context, code),
                    icon: const Icon(Icons.copy),
                    label: const Text('复制展示码'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => copyUserCode(context, code, shareText: link),
                    icon: const Icon(Icons.link),
                    label: const Text('复制分享链接'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      final text = premium
                          ? '我的 AIM 靓号：$code（$levelName） $link'
                          : '加我 AIM：$code $link';
                      copyUserCode(context, code, shareText: text);
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('复制分享文案'),
                  ),
                ],
                const SizedBox(height: 16),
                Text('说明', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  '好友打开分享链接并登录后，可自动发起与你的单聊；也可在 IM 搜索你的展示码添加。',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.diamond_outlined),
                  title: const Text('购买 / 更换靓号'),
                  subtitle: const Text('豹子号、顺子号、生日号等'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentHubPage(
                          token: widget.token,
                          userId: widget.userId,
                          currentUserCode: code,
                        ),
                      ),
                    );
                    _load();
                  },
                ),
              ],
            ),
    );
  }
}
