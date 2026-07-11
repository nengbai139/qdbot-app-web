import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../app_theme.dart';
import '../profile/qd_wallet_page.dart';
import 'circle_models.dart';

class LiveEarningsPage extends StatefulWidget {
  final String token;
  final String userId;

  const LiveEarningsPage({super.key, required this.token, this.userId = ''});

  @override
  State<LiveEarningsPage> createState() => _LiveEarningsPageState();
}

class _LiveEarningsPageState extends State<LiveEarningsPage> {
  late final CircleApi _api = CircleApi(widget.token);
  LiveEarningsDetail? _detail;
  String? _error;
  bool _loading = true;

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
      final d = await _api.myLiveEarningsDetail();
      if (!mounted) return;
      setState(() {
        _detail = d;
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

  String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final local = t.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('直播收益')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _SummaryCard(detail: _detail!),
                      if (widget.userId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QdWalletPage(token: widget.token, userId: widget.userId),
                              ),
                            ),
                            icon: const Icon(Icons.account_balance_wallet_outlined),
                            label: const Text('查看 QD 钱包 / 提现'),
                          ),
                        ),
                      if (_detail!.rooms.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('按场次', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ..._detail!.rooms.map((r) => _RoomTile(room: r, fmtTime: _fmtTime)),
                      ],
                      if (_detail!.recent.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('最近打赏', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ..._detail!.recent.map((g) => _GiftTile(gift: g, fmtTime: _fmtTime)),
                      ],
                      if (_detail!.totalAmount <= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              '暂无打赏记录\n开播后观众送礼会显示在这里',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final LiveEarningsDetail detail;
  const _SummaryCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFE5484D).withValues(alpha: 0.12), AppTheme.brandBlue.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('累计收益', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Text(
                  '${detail.totalAmount.toStringAsFixed(0)} QD',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFFE5484D)),
                ),
                const SizedBox(height: 4),
                Text('礼物收益实时入账 QD 钱包', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${detail.giftCount} 次', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text('打赏', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final LiveRoomEarnings room;
  final String Function(String) fmtTime;

  const _RoomTile({required this.room, required this.fmtTime});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${room.giftCount} 次 · ${fmtTime(room.lastAt)}'),
        trailing: Text(
          '${room.totalAmount.toStringAsFixed(0)} QD',
          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFE5484D)),
        ),
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  final LiveGiftRecord gift;
  final String Function(String) fmtTime;

  const _GiftTile({required this.gift, required this.fmtTime});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Text(gift.emoji, style: const TextStyle(fontSize: 22)),
      title: Text('${gift.senderName} · ${gift.giftName}'),
      subtitle: Text(fmtTime(gift.createdAt)),
      trailing: Text('${gift.amount.toStringAsFixed(0)} QD', style: TextStyle(color: Colors.grey.shade700)),
    );
  }
}
