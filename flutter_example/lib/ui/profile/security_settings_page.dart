import 'package:flutter/material.dart';
import '../../api/user_api.dart';
import 'device_list_page.dart';
import 'payment/payment_hub_page.dart';

class SecuritySettingsPage extends StatefulWidget {
  final String token;
  final String userId;
  final String userCode;
  final String email;

  const SecuritySettingsPage({
    super.key,
    required this.token,
    required this.userId,
    this.userCode = '',
    this.email = '',
  });

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final _oldPwd = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _oldPwd.dispose();
    _newPwd.dispose();
    _confirmPwd.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newPwd.text.length < 6) {
      setState(() => _error = '新密码至少 6 位');
      return;
    }
    if (_newPwd.text != _confirmPwd.text) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserApi(widget.token).changePassword(oldPassword: _oldPwd.text, newPassword: _newPwd.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已更新'), backgroundColor: Colors.green));
      _oldPwd.clear();
      _newPwd.clear();
      _confirmPwd.clear();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_outlined),
            title: const Text('登录邮箱'),
            subtitle: Text(widget.email.isNotEmpty ? widget.email : '未绑定'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('展示码'),
            subtitle: Text(widget.userCode.isNotEmpty ? widget.userCode : widget.userId),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentHubPage(
                  token: widget.token,
                  userId: widget.userId,
                  currentUserCode: widget.userCode,
                ),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_outlined),
            title: const Text('登录设备管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DeviceListPage(token: widget.token)),
            ),
          ),
          const Divider(height: 32),
          const Text('修改密码', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(controller: _oldPwd, obscureText: true, decoration: const InputDecoration(labelText: '当前密码', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _newPwd, obscureText: true, decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _confirmPwd, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder())),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _changePassword,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('保存密码'),
          ),
        ],
      ),
    );
  }
}
