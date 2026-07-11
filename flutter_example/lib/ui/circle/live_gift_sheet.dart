import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../profile/qd_wallet_page.dart';

/// 直播礼物：QD 币扣款（充值请去钱包页）
class LiveGiftSheet extends StatefulWidget {
  final String token;
  final String userId;
  final String roomId;

  const LiveGiftSheet({
    super.key,
    required this.token,
    required this.userId,
    required this.roomId,
  });

  static void show(BuildContext context, {required String token, required String userId, required String roomId}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LiveGiftSheet(token: token, userId: userId, roomId: roomId),
    );
  }

  @override
  State<LiveGiftSheet> createState() => _LiveGiftSheetState();
}

class _LiveGiftSheetState extends State<LiveGiftSheet> {
  static const _gifts = [
    _Gift('rose', '🌹', '玫瑰', 1),
    _Gift('candy', '🍬', '糖果', 5),
    _Gift('star', '⭐', '星星', 10),
    _Gift('rocket', '🚀', '火箭', 99),
    _Gift('crown', '👑', '皇冠', 520),
  ];

  late final CircleApi _circle = CircleApi(widget.token);
  bool _busy = false;
  _Gift? _selected;
  double _balance = 0;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final b = await _circle.getQdBalance();
      if (mounted) setState(() => _balance = b);
    } catch (_) {}
  }

  Future<void> _sendGift() async {
    final gift = _selected;
    if (gift == null || _busy) return;
    if (_balance + 0.001 < gift.price) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('QD币不足'),
          content: Text('需要 ${gift.price} QD，当前余额 ${_balance.toStringAsFixed(0)} QD'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('去充值')),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.pop(context);
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QdWalletPage(token: widget.token, userId: widget.userId)),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _circle.sendLiveGift(widget.roomId, gift.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已送出 ${gift.emoji} ${gift.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('送礼失败: $e')));
      _loadBalance();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('送礼物', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Text(
                  '余额 ${_balance.toStringAsFixed(0)} QD',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                IconButton(
                  icon: Icon(Icons.account_balance_wallet_outlined, color: Colors.grey.shade400, size: 20),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => QdWalletPage(token: widget.token, userId: widget.userId)),
                    );
                  },
                ),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _selected == null ? '选礼物，使用 QD 币支付' : '已选 ${_selected!.emoji} ${_selected!.name} · ${ _selected!.price} QD',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _gifts.map((g) {
                final sel = _selected?.id == g.id;
                return InkWell(
                  onTap: _busy ? null : () => setState(() => _selected = g),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFE5484D).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: sel ? Border.all(color: const Color(0xFFE5484D)) : null,
                    ),
                    child: Column(
                      children: [
                        Text(g.emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(g.name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        Text('${g.price} QD', style: const TextStyle(color: Color(0xFFE5484D), fontSize: 10)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _sendGift,
                child: Text('送出 · ${_selected!.price} QD'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Gift {
  final String id;
  final String emoji;
  final String name;
  final int price;
  const _Gift(this.id, this.emoji, this.name, this.price);
}
