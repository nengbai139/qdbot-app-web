import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../../util/circle_ai.dart';
import '../app_theme.dart';
import '../im_media.dart';
import 'widgets/circle_ui.dart';

class MomentComposePage extends StatefulWidget {
  final String token;
  final String userId;

  const MomentComposePage({super.key, required this.token, required this.userId});

  @override
  State<MomentComposePage> createState() => _MomentComposePageState();
}

class _MomentComposePageState extends State<MomentComposePage> {
  final _textCtrl = TextEditingController();
  late final CircleApi _api = CircleApi(widget.token);
  final _images = <String>[];
  String _visibility = 'friends';
  bool _busy = false;
  bool _aiBusy = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  int _uploadingCount = 0;

  Future<void> _pickImage() async {
    final remain = 9 - _images.length;
    if (remain <= 0) return;
    final picked = await pickMultipleImageBytes(maxCount: remain);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _uploadingCount = picked.length;
    });
    try {
      final urls = <String>[];
      for (final p in picked) {
        final url = await _api.uploadMediaBytes(p.bytes, userId: widget.userId, kind: 'image', filename: p.name ?? 'photo.jpg');
        urls.add(url);
      }
      if (!mounted) return;
      setState(() => _images.addAll(urls));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _uploadingCount = 0;
      });
    }
  }

  Future<void> _suggestCaption() async {
    setState(() => _aiBusy = true);
    try {
      final text = await suggestCircleCopy(token: widget.token, userId: widget.userId, draft: _textCtrl.text, forVideo: false);
      if (!mounted) return;
      _textCtrl.text = text;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _publish() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    setState(() => _busy = true);
    try {
      final post = await _api.createMoment(text: text, images: _images, visibility: _visibility);
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发布失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: circleComposeAppBar(
        context,
        title: '',
        publishLabel: '发表',
        onPublish: _busy ? null : _publish,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _textCtrl,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(fontSize: 16, height: 1.45),
            decoration: InputDecoration(
              hintText: '这一刻的想法…',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.55), fontSize: 16),
              border: InputBorder.none,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _aiBusy || _busy ? null : _suggestCaption,
              icon: _aiBusy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                    )
                  : Icon(Icons.auto_awesome_outlined, size: 18, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
              label: Text(_aiBusy ? 'AI 生成中…' : 'AI 配文', style: TextStyle(color: AppTheme.brandBlue)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _images.length; i++)
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () => showImageViewer(context, _images[i], urls: _images, initialIndex: i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(_images[i], width: 80, height: 80, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2)),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_images.length < 9)
                GestureDetector(
                  onTap: _busy ? null : _pickImage,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.add, color: scheme.onSurfaceVariant.withValues(alpha: 0.6), size: 32),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('谁可以看', style: TextStyle(fontSize: 15)),
            subtitle: Text(circleVisibilityLabel(_visibility), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            onTap: _busy
                ? null
                : () async {
                    final v = await showModalBottomSheet<String>(
                      context: context,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                      builder: (ctx) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              circleSheetHandle(ctx),
                              const Text('谁可以看', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              circleVisibilitySegments(
                                value: _visibility,
                                onChanged: (val) {
                                  setState(() => _visibility = val);
                                  Navigator.pop(ctx, val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (v != null) setState(() => _visibility = v);
                  },
          ),
          if (_busy && _uploadingCount > 0) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                '正在上传 $_uploadingCount 张…',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          if (_busy && _uploadingCount == 0) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ],
      ),
    );
  }
}
