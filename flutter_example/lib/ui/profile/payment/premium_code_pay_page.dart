import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../api/auth_api.dart';
import '../../../api/pay_api.dart';
import '../../../session.dart';
import '../../premium/premium_code_success_page.dart';

/// 靓号检测 + 下单 + 模拟支付（注册页与「我的」共用）
class PremiumCodePayPage extends StatefulWidget {
  final String? token;
  final String? userId;
  final String currentUserCode;
  final String? presetEmail;
  final String? presetCode;
  final PayOrder? existingOrder;
  final void Function(PayOrder order)? onPaid;

  const PremiumCodePayPage({
    super.key,
    this.token,
    this.userId,
    this.currentUserCode = '',
    this.presetEmail,
    this.presetCode,
    this.existingOrder,
    this.onPaid,
  });

  @override
  State<PremiumCodePayPage> createState() => _PremiumCodePayPageState();
}

class _PremiumCodePayPageState extends State<PremiumCodePayPage> {
  final _code = TextEditingController();
  final _email = TextEditingController();
  Map<String, dynamic>? _premiumInfo;
  PayOrder? _order;
  bool _checking = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.presetEmail != null) _email.text = widget.presetEmail!;
    if (widget.presetCode != null) _code.text = widget.presetCode!;
    if (widget.existingOrder != null) {
      _order = widget.existingOrder;
      _code.text = widget.existingOrder!.userCode;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _checkPremium() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _premiumInfo = null);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final resp = await authApi.checkPremiumCode(code);
      if (resp.statusCode == 200 && mounted) {
        setState(() => _premiumInfo = jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _createOrder() async {
    final code = _code.text.trim();
    final email = _email.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入展示码');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = '请输入邮箱（订单绑定）');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final api = widget.token != null ? PayApi(widget.token) : publicPayApi;
      final order = await api.createPremiumOrder(
        userCode: code,
        email: email,
        userId: widget.userId,
      );
      if (mounted) setState(() => _order = order);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _payChannel(String channel) async {
    if (_order == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final api = publicPayApi;
      if (channel == 'mock') {
        final paid = await api.mockPay(_order!.orderId);
        if (mounted) _onPaid(paid);
        return;
      }
      final checkout = await api.checkout(_order!.orderId, channel);
      if (channel == 'alipay' || channel == 'wechat') {
        if (checkout['mode'] == 'sandbox') {
          if (!mounted) return;
          final label = channel == 'alipay' ? '支付宝' : '微信支付';
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('$label沙箱'),
              content: Text((checkout['instruction'] ?? '确认已完成支付').toString()),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认已支付')),
              ],
            ),
          );
          if (ok == true) {
            final paid = channel == 'alipay'
                ? await api.alipayConfirm(_order!.orderId)
                : await api.wechatConfirm(_order!.orderId);
            if (mounted) _onPaid(paid);
          }
        } else if (checkout['status'] == 'paid') {
          final paid = await api.getOrder(_order!.orderId);
          if (mounted) _onPaid(paid);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _onPaid(PayOrder paid) {
    setState(() => _order = paid);
    widget.onPaid?.call(paid);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('支付成功（${paid.payChannel ?? "mock"}）'), backgroundColor: Colors.green),
    );
  }

  Future<void> _mockPay() async => _payChannel('mock');

  Future<void> _applyForLoggedIn() async {
    if (_order == null || widget.token == null || widget.userId == null) return;
    setState(() => _working = true);
    try {
      final code = await PayApi(widget.token!).applyUserCode(
        userCode: _order!.userCode,
        premiumOrderId: _order!.orderId,
      );
      await SessionStore.save(
        token: widget.token!,
        userId: widget.userId!,
        userCode: code,
      );
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PremiumCodeSuccessPage(
            userCode: code,
            levelName: _order!.levelName,
            levelDesc: (_premiumInfo?['desc'] ?? '').toString(),
            token: widget.token!,
            userId: widget.userId!,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = _premiumInfo?['premium'] == true;
    final paid = _order?.isPaid == true;

    return Scaffold(
      appBar: AppBar(title: Text(widget.token != null ? '购买靓号' : '靓号支付')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.currentUserCode.isNotEmpty)
            Text('当前展示码：${widget.currentUserCode}', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: _order == null,
            decoration: InputDecoration(
              labelText: '目标展示码',
              hintText: '如 U202600888',
              border: const OutlineInputBorder(),
              suffixIcon: _checking
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : TextButton(onPressed: _checkPremium, child: const Text('检测')),
            ),
            onChanged: (_) => _checkPremium(),
          ),
          if (_premiumInfo != null) ...[
            const SizedBox(height: 8),
            _PremiumBadge(info: _premiumInfo!),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '绑定邮箱', border: OutlineInputBorder()),
          ),
          if (_order != null) ...[
            const SizedBox(height: 16),
            Card(
              color: paid ? Colors.green.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('订单 ${_order!.orderId}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${_order!.levelName} · ¥${_order!.amount.toStringAsFixed(0)}'),
                    Text('状态：${paid ? "已支付" : "待支付"}'),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          if (_order == null && premium)
            FilledButton(
              onPressed: (_working || _premiumInfo?['available'] != true) ? null : _createOrder,
              child: _working ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('创建订单'),
            )
          else if (_order != null && !paid) ...[
            FilledButton.icon(
              onPressed: _working ? null : () => _payChannel('alipay'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text('支付宝 ¥${_order!.amount.toStringAsFixed(0)}'),
            ),
            OutlinedButton(
              onPressed: _working ? null : () => _payChannel('wechat'),
              child: Text('微信支付 ¥${_order!.amount.toStringAsFixed(0)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _working ? null : _mockPay,
              child: Text('模拟支付 ¥${_order!.amount.toStringAsFixed(0)}'),
            ),
          ]
          else if (paid && widget.token != null)
            FilledButton(
              onPressed: _working ? null : _applyForLoggedIn,
              child: const Text('确认更换展示码'),
            )
          else if (paid && widget.onPaid == null)
            const Text('支付完成，请返回继续注册', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '支付宝/微信沙箱可演练完整流程；生产需配置 ALIPAY_* / WECHAT_PAY_* 环境变量。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  final Map<String, dynamic> info;
  const _PremiumBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    final premium = info['premium'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: premium ? Colors.amber.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: premium ? Colors.amber : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(
            premium ? Icons.diamond : Icons.circle_outlined,
            size: 20,
            color: premium ? Colors.amber.shade700 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${info['levelName'] ?? '普通'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${info['desc'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (premium) Text('¥${info['price']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(width: 4),
          Icon(info['available'] == true ? Icons.check_circle : Icons.cancel, color: info['available'] == true ? Colors.green : Colors.red, size: 18),
        ],
      ),
    );
  }
}
