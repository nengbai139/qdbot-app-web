import 'package:flutter/material.dart';

import '../../api/pay_api.dart';
import '../../api/wallet_api.dart';
import '../app_theme.dart';

/// QD 币钱包：充值（支付宝/微信）→ 余额 → 直播间送礼消费
class QdWalletPage extends StatefulWidget {
  final String token;
  final String userId;

  const QdWalletPage({super.key, required this.token, required this.userId});

  @override
  State<QdWalletPage> createState() => _QdWalletPageState();
}

class _QdWalletPageState extends State<QdWalletPage> {
  late final WalletApi _wallet = WalletApi(widget.token);
  late final PayApi _pay = PayApi(widget.token);
  QdWallet? _walletData;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const _packs = [10.0, 50.0, 100.0, 500.0];

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
      final w = await _wallet.getQdWallet();
      if (!mounted) return;
      setState(() {
        _walletData = w;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _recharge(double coins, String channel) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final order = await _pay.createQdRechargeOrder(userId: widget.userId, coins: coins);
      if (channel == 'mock') {
        await _pay.mockPay(order.orderId);
      } else {
        final checkout = await _pay.checkout(order.orderId, channel);
        if (checkout['mode'] == 'sandbox') {
          if (!mounted) return;
          final label = channel == 'alipay' ? '支付宝' : '微信';
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('$label 充值沙箱'),
              content: Text('充值 ${coins.toInt()} QD币 · ${(checkout['instruction'] ?? '确认已完成支付').toString()}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认已支付')),
              ],
            ),
          );
          if (ok != true) return;
          if (channel == 'alipay') {
            await _pay.alipayConfirm(order.orderId);
          } else {
            await _pay.wechatConfirm(order.orderId);
          }
        } else if (checkout['status'] != 'paid') {
          throw Exception('支付未完成');
        }
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已充值 ${coins.toInt()} QD币')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('充值失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRechargeChannel(double coins) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('充值 ${coins.toInt()} QD币（¥${coins.toInt()}）', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : () { Navigator.pop(ctx); _recharge(coins, 'mock'); }, child: const Text('模拟支付（测试）')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _busy ? null : () { Navigator.pop(ctx); _recharge(coins, 'alipay'); }, child: const Text('支付宝')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _busy ? null : () { Navigator.pop(ctx); _recharge(coins, 'wechat'); }, child: const Text('微信支付')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _withdraw() async {
    final bal = _walletData?.balance ?? 0;
    final amountCtrl = TextEditingController(text: bal >= 10 ? '10' : '');
    final accountCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QD币提现'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('可提现 ${bal.toStringAsFixed(0)} QD · 最低 10', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '提现数量（QD）'),
            ),
            TextField(
              controller: accountCtrl,
              decoration: const InputDecoration(labelText: '支付宝账号/手机号'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('提交')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      amountCtrl.dispose();
      accountCtrl.dispose();
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final account = accountCtrl.text.trim();
    amountCtrl.dispose();
    accountCtrl.dispose();
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('最低提现 10 QD')));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _wallet.withdrawQd(amount: amount, account: account);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _ledgerLabel(QdLedgerEntry e) {
    if (e.kind == 'recharge') return '充值';
    if (e.kind == 'spend' && e.refType == 'live_gift') return '直播礼物';
    if (e.kind == 'spend' && e.refType == 'live_redpacket') return '发福袋';
    if (e.kind == 'credit' && e.refType == 'live_redpacket_grab') return '抢红包';
    if (e.kind == 'credit' && e.refType == 'live_redpacket_refund') return '红包退回';
    if (e.kind == 'credit' && e.refType == 'live_gift_income') return '直播礼物收入';
    if (e.kind == 'spend' && e.refType == 'withdraw') return '提现';
    return e.kind;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QD币钱包')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.brandBlue.withValues(alpha: 0.15), const Color(0xFFE5484D).withValues(alpha: 0.08)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('可用余额', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text(
                              '${(_walletData?.balance ?? 0).toStringAsFixed(0)} QD',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text('1 QD币 = ¥1 · 充值消费 · 直播收益可提现', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _withdraw,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('提现到支付宝'),
                      ),
                      const SizedBox(height: 20),
                      Text('快捷充值', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _packs.map((c) {
                          return ActionChip(
                            label: Text('${c.toInt()} QD'),
                            onPressed: _busy ? null : () => _pickRechargeChannel(c),
                          );
                        }).toList(),
                      ),
                      if (_walletData != null && _walletData!.ledger.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('最近流水', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ..._walletData!.ledger.map((e) {
                          final sign = e.amount >= 0 ? '+' : '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_ledgerLabel(e)),
                            subtitle: Text(e.createdAt.length > 16 ? e.createdAt.substring(0, 16) : e.createdAt),
                            trailing: Text(
                              '$sign${e.amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: e.amount >= 0 ? Colors.green.shade700 : Colors.grey.shade800,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
    );
  }
}
