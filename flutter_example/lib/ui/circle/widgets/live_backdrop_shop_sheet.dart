import 'package:flutter/material.dart';

import '../../../api/circle_api.dart';
import '../circle_models.dart';
import 'circle_ui.dart';
import 'live_backdrop.dart' show liveListCoverFallback;

/// 直播背景墙装修商店：购买后替换
Future<LiveBackdropItem?> showLiveBackdropItemShopSheet(
  BuildContext context, {
  required CircleApi api,
  required String currentImageUrl,
  bool studio = false,
}) {
  return showModalBottomSheet<LiveBackdropItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kLiveSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _LiveBackdropItemShopBody(api: api, currentImageUrl: currentImageUrl, studio: studio),
  );
}

class _LiveBackdropItemShopBody extends StatefulWidget {
  final CircleApi api;
  final String currentImageUrl;
  final bool studio;

  const _LiveBackdropItemShopBody({required this.api, required this.currentImageUrl, required this.studio});

  @override
  State<_LiveBackdropItemShopBody> createState() => _LiveBackdropItemShopBodyState();
}

class _LiveBackdropItemShopBodyState extends State<_LiveBackdropItemShopBody> {
  List<LiveBackdropItem> _items = const [];
  double _balance = 0;
  bool _loading = true;
  bool _busy = false;
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
      final r = await widget.api.listLiveBackdropItems();
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _balance = r.balance;
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

  Future<void> _buy(LiveBackdropItem b) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.purchaseLiveBackdropItem(b.id);
      if (!mounted) return;
      setState(() {
        _items = _items.map((x) => x.id == updated.id ? updated : x).toList();
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已购买「${updated.name}」')));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('购买失败: $e')));
    }
  }

  Future<void> _tap(LiveBackdropItem b) async {
    if (b.owned) {
      Navigator.pop(context, b);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('购买装修「${b.name}」'),
        content: Text('价格 ${b.price.toStringAsFixed(0)} QD币\n当前余额 ${_balance.toStringAsFixed(0)} QD币'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('购买')),
        ],
      ),
    );
    if (ok == true) await _buy(b);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.studio ? '虚拟背景' : '选择虚拟背景';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                Text('${_balance.toStringAsFixed(0)} QD', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text(
              '购买后可在开摄像头时作为虚拟背景（网页直播）',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: kLiveAccent)))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.currentImageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, LiveBackdropItem.empty()),
                          icon: const Icon(Icons.wallpaper_outlined, size: 18),
                          label: const Text('关闭虚拟背景'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white30),
                          ),
                        ),
                      ),
                    Expanded(
                      child: GridView.builder(
                        shrinkWrap: true,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final b = _items[i];
                          final selected = widget.currentImageUrl == b.imageUrl;
                          return InkWell(
                            onTap: _busy ? null : () => _tap(b),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(b.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => liveListCoverFallback()),
                                        if (!b.owned)
                                          Container(color: Colors.black54, child: const Center(child: Icon(Icons.lock_outline, color: Colors.white70))),
                                        if (selected)
                                          DecoratedBox(
                                            decoration: BoxDecoration(border: Border.all(color: kLiveAccent, width: 3), borderRadius: BorderRadius.circular(12)),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: selected ? kLiveAccent : Colors.white70, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                                Text(
                                  b.owned ? '已拥有' : (b.free ? '免费' : '${b.price.toStringAsFixed(0)} QD'),
                                  style: TextStyle(fontSize: 10, color: b.owned ? Colors.greenAccent : Colors.white38),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
