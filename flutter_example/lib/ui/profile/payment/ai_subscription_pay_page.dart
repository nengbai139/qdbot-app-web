import 'package:flutter/material.dart';
import '../../../api/ai_api.dart';
import '../../../api/pay_api.dart';
import '../../app_theme.dart';

/// AI Pro 月订：下单 + 支付（mock / 支付宝 / 微信沙箱）
class AiSubscriptionPayPage extends StatefulWidget {
  final String token;
  final String userId;
  final AiSubscription? current;

  const AiSubscriptionPayPage({
    super.key,
    required this.token,
    required this.userId,
    this.current,
  });

  @override
  State<AiSubscriptionPayPage> createState() => _AiSubscriptionPayPageState();
}

class _AiSubscriptionPayPageState extends State<AiSubscriptionPayPage> {
  List<AiPlan> _plans = [];
  AiPlan? _selected;
  PayOrder? _order;
  AiSubscription? _sub;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.current;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ai = AiApi(widget.token);
      final plans = await ai.getPlans();
      final sub = await ai.getSubscription();
      if (mounted) {
        setState(() {
          _plans = plans;
          _selected = plans.isNotEmpty ? plans.first : null;
          _sub = sub;
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

  Future<void> _createOrder() async {
    if (_selected == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final order = await PayApi(widget.token).createAiSubscriptionOrder(
        userId: widget.userId,
        planId: _selected!.planId,
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
      final api = PayApi(widget.token);
      if (channel == 'mock') {
        final paid = await api.mockPay(_order!.orderId);
        await _onPaid(paid);
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
            await _onPaid(paid);
          }
        } else if (checkout['status'] == 'paid') {
          await _onPaid(await api.getOrder(_order!.orderId));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _onPaid(PayOrder paid) async {
    setState(() => _order = paid);
    try {
      final ai = AiApi(widget.token);
      final sub = await ai.getSubscription();
      final q = await ai.getQuota();
      if (!mounted) return;
      setState(() => _sub = sub);
      if (sub.active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('订阅已生效：${sub.planName} · 今日配额 ${q.used}/${q.limit}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('支付成功，订阅生效中…请返回对话页重试；若仍不可用请联系客服'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}
  }

  String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final active = _sub?.active == true;
    final paid = _order?.isPaid == true;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Pro 订阅')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (active)
                  Card(
                    color: Colors.deepPurple.shade50,
                    child: ListTile(
                      leading: Icon(Icons.verified, color: AppTheme.brandBlue),
                      title: Text(_sub!.planName.isNotEmpty ? _sub!.planName : 'AI Pro'),
                      subtitle: Text('有效期至 ${_fmt(_sub!.expiresAt)}'),
                    ),
                  ),
                if (_plans.isEmpty)
                  const Text('暂无可用套餐')
                else
                  ..._plans.map((p) => Card(
                        child: RadioListTile<String>(
                          value: p.planId,
                          groupValue: _selected?.planId,
                          onChanged: _order == null && !active
                              ? (v) => setState(() => _selected = p)
                              : null,
                          title: Text(p.name),
                          subtitle: Text('${p.desc} · ${p.days} 天'),
                          secondary: Text('¥${p.price.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                      )),
                if (_order != null) ...[
                  const SizedBox(height: 8),
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
                if (!active && _order == null)
                  FilledButton(
                    onPressed: (_working || _selected == null) ? null : _createOrder,
                    child: _working
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('订阅 ¥${_selected?.price.toStringAsFixed(0) ?? ''}'),
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
                    onPressed: _working ? null : () => _payChannel('mock'),
                    child: Text('模拟支付 ¥${_order!.amount.toStringAsFixed(0)}'),
                  ),
                ]
                else if (active)
                  const Text('当前订阅有效，到期后可续订', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  '支付成功后技能调用优先、配额提升；沙箱环境可模拟完整流程。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }
}
