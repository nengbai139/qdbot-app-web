import 'package:flutter/material.dart';
import '../../../api/ai_api.dart';
import '../../../api/pay_api.dart';
import '../../../session.dart';
import '../../app_theme.dart';
import '../../premium/premium_code_success_page.dart';
import 'ai_subscription_pay_page.dart';
import 'premium_code_pay_page.dart';

class PaymentHubPage extends StatefulWidget {
  final String token;
  final String userId;
  final String currentUserCode;

  const PaymentHubPage({
    super.key,
    required this.token,
    required this.userId,
    this.currentUserCode = '',
  });

  @override
  State<PaymentHubPage> createState() => _PaymentHubPageState();
}

class _PaymentHubPageState extends State<PaymentHubPage> {
  List<PayOrder> _orders = [];
  AiSubscription? _aiSub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pay = PayApi(widget.token);
      final ai = AiApi(widget.token);
      final results = await Future.wait([pay.listOrders(), ai.getSubscription()]);
      if (mounted) {
        setState(() {
          _orders = results[0] as List<PayOrder>;
          _aiSub = results[1] as AiSubscription;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return '待支付';
      case 'paid':
        return '已支付';
      case 'consumed':
        return '已使用';
      case 'expired':
        return '已过期';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('支付中心'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_aiSub?.expiringSoon == true)
                  Card(
                    color: Colors.orange.shade50,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: Colors.orange.shade800),
                      title: Text('AI Pro 将于 ${_aiSub!.daysLeft} 天后到期'),
                      subtitle: const Text('续订后可叠加有效期'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AiSubscriptionPayPage(
                              token: widget.token,
                              userId: widget.userId,
                              current: _aiSub,
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome, color: Colors.deepPurple.shade400),
                    title: const Text('AI Pro 月订'),
                    subtitle: Text(
                      _aiSub?.active == true
                          ? '${_aiSub!.planName} · 至 ${_fmt(_aiSub!.expiresAt)}'
                          : '技能优先 · 更高配额 · ¥29/月',
                    ),
                    trailing: _aiSub?.active == true
                        ? Chip(label: const Text('已开通'), backgroundColor: Colors.green.shade100)
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AiSubscriptionPayPage(
                            token: widget.token,
                            userId: widget.userId,
                            current: _aiSub,
                          ),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.diamond_outlined, color: AppTheme.brandBlue),
                    title: const Text('购买靓号'),
                    subtitle: Text(widget.currentUserCode.isNotEmpty ? '当前 ID ${widget.currentUserCode}' : '自定义展示码'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PremiumCodePayPage(
                            token: widget.token,
                            userId: widget.userId,
                            currentUserCode: widget.currentUserCode,
                          ),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text('订单记录', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_orders.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('暂无订单')))
                else
                  ..._orders.map((o) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(o.isAiSubscription ? o.levelName : o.userCode),
                          subtitle: Text(
                            o.isAiSubscription
                                ? 'AI 订阅 · ¥${o.amount.toStringAsFixed(0)} · ${_statusLabel(o.status)}'
                                : '${o.levelName} · ¥${o.amount.toStringAsFixed(0)} · ${_statusLabel(o.status)}',
                          ),
                          trailing: !o.isAiSubscription && o.status == 'paid'
                              ? FilledButton(
                                  onPressed: () => _applyPaidOrder(o),
                                  child: const Text('换号'),
                                )
                              : null,
                        ),
                      )),
              ],
            ),
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _applyPaidOrder(PayOrder o) async {
    try {
      final code = await PayApi(widget.token).applyUserCode(userCode: o.userCode, premiumOrderId: o.orderId);
      await SessionStore.save(
        token: widget.token,
        userId: widget.userId,
        userCode: code,
      );
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PremiumCodeSuccessPage(
            userCode: code,
            levelName: o.levelName,
            token: widget.token,
            userId: widget.userId,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
