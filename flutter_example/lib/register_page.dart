import 'dart:convert';
import 'package:flutter/material.dart';
import 'api/auth_api.dart';
import 'api/pay_api.dart';
import 'ui/profile/payment/premium_code_pay_page.dart';
import 'ui/premium/premium_code_success_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPwd = TextEditingController();
  final _phone = TextEditingController();
  final _idCard = TextEditingController();
  final _userCode = TextEditingController();
  final _deviceId = TextEditingController();
  final _verifyCode = TextEditingController();
  String _platform = 'web';
  String? _tenantId;
  String? _businessId;
  List<Map<String, dynamic>> _tenants = [];
  List<Map<String, dynamic>> _businesses = [];
  List<Map<String, dynamic>> _devices = [];
  bool _loading = false, _loadingTenants = true;
  String? _error;
  Map<String, dynamic>? _premiumInfo;
  Map<String, dynamic>? _deviceInfo;
  PayOrder? _paidOrder;

  @override
  void initState() {
    super.initState();
    _deviceId.text = 'device_${DateTime.now().millisecondsSinceEpoch}';
    _loadTenants();
    _loadDevices();
  }

  @override
  void dispose() {
    _verifyCode.dispose();
    _name.dispose(); _email.dispose(); _password.dispose(); _confirmPwd.dispose();
    _phone.dispose(); _idCard.dispose(); _userCode.dispose(); _deviceId.dispose();
    super.dispose();
  }

  Future<void> _loadTenants() async {
    try {
      final resp = await authApi.tenants();
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _tenants = List<Map<String, dynamic>>.from(data['tenants'] ?? []);
          if (_tenants.isNotEmpty) _tenantId = _tenants[0]['tenantId'];
          _loadingTenants = false;
        });
        // 默认 tenant 加载其 businesses
        if (_tenantId != null) _loadBusinesses();
      }
    } catch (_) { setState(() => _loadingTenants = false); }
  }

  Future<void> _loadBusinesses() async {
    if (_tenantId == null) return;
    try {
      final resp = await authApi.businesses(_tenantId!);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _businesses = List<Map<String, dynamic>>.from(data['businesses'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadDevices() async {
    try {
      final resp = await authApi.devices();
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _devices = List<Map<String, dynamic>>.from(data['devices'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _checkPremium() async {
    final code = _userCode.text.trim();
    if (code.isEmpty) { setState(() => _premiumInfo = null); return; }
    try {
      final resp = await authApi.checkPremiumCode(code);
      if (resp.statusCode == 200) {
        setState(() => _premiumInfo = jsonDecode(resp.body));
      }
    } catch (_) {}
  }

  Future<void> _verifyDevice() async {
    final did = _deviceId.text.trim();
    if (did.isEmpty) return;
    try {
      final resp = await authApi.deviceStatus(did);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() => _deviceInfo = data['valid'] == true ? data : null);
        if (data['valid'] != true) {
          setState(() => _error = '设备ID无效或未注册');
        }
      }
    } catch (_) { setState(() => _error = '设备验证网络错误'); }
  }

  Future<void> _sendVerifyCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) { setState(() => _error = '请先输入有效邮箱'); return; }
    try {
      final resp = await authApi.sendRegisterCode(email);
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮箱'), backgroundColor: Colors.green));
      } else {
        setState(() => _error = '发送验证码失败，请稍后再试');
      }
    } catch (_) { setState(() => _error = '网络错误'); }
  }

  Future<void> _register() async {
    if (_name.text.trim().isEmpty) { setState(() => _error = '请输入用户名'); return; }
    if (!_email.text.contains('@')) { setState(() => _error = '请输入有效邮箱'); return; }
    if (_password.text.length < 6) { setState(() => _error = '密码至少6位'); return; }
    if (_phone.text.trim().isEmpty) { setState(() => _error = '请输入手机号'); return; }
    if (_idCard.text.trim().isEmpty) { setState(() => _error = '请输入身份证号'); return; }
    if (_deviceId.text.trim().isEmpty) { setState(() => _error = '请选择智能体'); return; }
    if (_password.text != _confirmPwd.text) { setState(() => _error = '两次密码不一致'); return; }
    final code = _userCode.text.trim();
    if (_premiumInfo?['premium'] == true) {
      if (_paidOrder == null || !_paidOrder!.isPaid) {
        setState(() => _error = '靓号需先完成支付');
        return;
      }
      if (_paidOrder!.userCode != code) {
        setState(() => _error = '支付订单与展示码不一致');
        return;
      }
    }
    setState(() { _loading = true; _error = null; });
    try {
      final body = <String, dynamic>{
          'username': _name.text.trim(), 'email': _email.text.trim(),
          'password': _password.text, 'phone': _phone.text.trim(),
          'idCard': _idCard.text.trim(), 'deviceId': _deviceId.text,
          'platform': _platform, 'tenantId': _tenantId ?? 'default',
          'businessId': _businessId, 'channel': 'app',
        };
      if (code.isNotEmpty) body['userCode'] = code;
      if (_paidOrder != null) body['premiumOrderId'] = _paidOrder!.orderId;
      final resp = await authApi.register(body);
      if (resp.statusCode == 200) {
        if (!mounted) return;
        if (_paidOrder?.isPaid == true) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final assigned = (data['userCode'] ?? code).toString();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (successCtx) => PremiumCodeSuccessPage(
                userCode: assigned,
                levelName: _paidOrder!.levelName,
                levelDesc: (_premiumInfo?['desc'] ?? '').toString(),
                doneLabel: '去登录',
                onDone: () {
                  Navigator.pop(successCtx);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('注册成功！请登录'), backgroundColor: Colors.green));
          Navigator.pop(context);
        }
      } else {
        setState(() => _error = jsonDecode(resp.body)['error'] ?? '注册失败');
      }
    } catch (e) { setState(() => _error = '网络错误: $e'); }
    finally { setState(() => _loading = false); }
  }

  // ========== UI ==========

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionTitle('基本信息'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: '* 用户名', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: '* 邮箱', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: '* 密码(6位以上)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
          const SizedBox(height: 12),
          TextField(controller: _confirmPwd, obscureText: true, decoration: const InputDecoration(labelText: '* 确认密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_outline))),

          _sectionTitle('联系方式'),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '* 手机号', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_android))),
          const SizedBox(height: 12),
          TextField(controller: _idCard, decoration: const InputDecoration(labelText: '* 身份证号', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),

          _sectionTitle('展示码（选填）'),
          TextField(
            controller: _userCode,
            decoration: InputDecoration(
              labelText: '自定义展示码', hintText: '如 U202600001，留空自动生成',
              border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.credit_card),
              suffixIcon: TextButton(onPressed: _checkPremium, child: const Text('检测')),
            ),
            onChanged: (_) async {
              setState(() => _paidOrder = null);
              await Future.delayed(const Duration(milliseconds: 500));
              _checkPremium();
            },
          ),
          if (_premiumInfo != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _premiumInfo!['premium'] == true ? Colors.amber.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _premiumInfo!['premium'] == true ? Colors.amber : Colors.grey.shade300),
              ),
              child: Row(children: [
                Icon(
                  _premiumInfo!['premium'] == true ? Icons.diamond : Icons.circle_outlined,
                  size: 20,
                  color: _premiumInfo!['premium'] == true ? Colors.amber.shade700 : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_premiumInfo!['levelName'] ?? '普通', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_premiumInfo!['desc'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ])),
                if (_premiumInfo!['premium'] == true)
                  Text('¥${_premiumInfo!["price"]}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(width: 4),
                Icon(_premiumInfo!['available'] == true ? Icons.check_circle : Icons.cancel, color: _premiumInfo!['available'] == true ? Colors.green : Colors.red, size: 18),
              ]),
            ),
            if (_premiumInfo!['premium'] == true && _premiumInfo!['available'] == true) ...[
              const SizedBox(height: 8),
              if (_paidOrder?.isPaid == true)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text('已支付 ${_paidOrder!.levelName} · ¥${_paidOrder!.amount.toStringAsFixed(0)}')),
                  ]),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PremiumCodePayPage(
                          presetEmail: _email.text.trim(),
                          presetCode: _userCode.text.trim(),
                          onPaid: (PayOrder o) => setState(() => _paidOrder = o),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payment),
                  label: Text('支付靓号 ¥${_premiumInfo!["price"]}'),
                ),
            ],
          ],

          _sectionTitle('账号归属'),
          _loadingTenants ? const Center(child: CircularProgressIndicator()) : DropdownButtonFormField<String>(
            value: _tenantId,
            decoration: const InputDecoration(labelText: '租户', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
            items: _tenants.map<DropdownMenuItem<String>>((t) => DropdownMenuItem<String>(value: t['tenantId'], child: Text(t['name'] ?? t['tenantId'] ?? ''))).toList(),
            onChanged: (v) { setState(() { _tenantId = v; _businessId = null; }); _loadBusinesses(); },
          ),
          if (_businesses.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _businessId,
              decoration: const InputDecoration(labelText: '业务单元', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store)),
              items: _businesses.map<DropdownMenuItem<String>>((b) => DropdownMenuItem<String>(value: b['businessId'], child: Text(b['name'] ?? b['businessId'] ?? ''))).toList(),
              onChanged: (v) => setState(() => _businessId = v),
            ),
          ],

          _sectionTitle('🤖 智能体绑定'),
          Text('选择您的智能体（如 qdbotclaw），智能体通过 DeviceID 拉取您的消息。',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 8),
          _devices.isEmpty
            ? Text('暂无可用设备，请联系管理员', style: TextStyle(color: Colors.grey[500]))
            : DropdownButtonFormField<String>(
                value: _deviceId.text.isEmpty ? null : _deviceId.text,
                decoration: const InputDecoration(labelText: '* 智能体 DeviceID', border: OutlineInputBorder(), prefixIcon: Icon(Icons.memory)),
                items: _devices.map<DropdownMenuItem<String>>((d) => DropdownMenuItem<String>(value: d['deviceId'], child: Text('${d['name'] ?? d['deviceId']} (${d['channel'] ?? ''})'))).toList(),
                onChanged: (v) => setState(() { _deviceId.text = v ?? ''; if (v != null) { final dev = _devices.firstWhere((d) => d['deviceId'] == v, orElse: () => {}); if (dev.isNotEmpty) { _tenantId = dev['tenantId']; _businessId = dev['businessId']; } } }),
              ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _platform,
            decoration: const InputDecoration(labelText: '平台', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_android)),
            items: const [DropdownMenuItem(value: 'ios', child: Text('iOS')), DropdownMenuItem(value: 'android', child: Text('Android')), DropdownMenuItem(value: 'web', child: Text('Web')), DropdownMenuItem(value: 'pad', child: Text('Pad'))],
            onChanged: (v) => setState(() => _platform = v!),
          ),

          _sectionTitle('📧 邮箱验证'),
          Text('验证码将发送到您的注册邮箱', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _verifyCode, decoration: const InputDecoration(labelText: '验证码', hintText: '6位数字', border: OutlineInputBorder(), prefixIcon: Icon(Icons.verified_user)))),
            const SizedBox(width: 12),
            SizedBox(height: 56, child: ElevatedButton(onPressed: _sendVerifyCode, child: const Text('发送验证码'))),
          ]),

          const SizedBox(height: 24),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          SizedBox(height: 48, child: ElevatedButton(onPressed: _loading ? null : _register, child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('注册', style: TextStyle(fontSize: 16)))),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('已有账号？去登录')),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
