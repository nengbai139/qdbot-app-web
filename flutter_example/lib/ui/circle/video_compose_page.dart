import 'package:flutter/material.dart';

import '../../api/circle_api.dart';
import '../../util/circle_ai.dart';
import '../app_theme.dart';
import '../im_media.dart';
import 'widgets/circle_ui.dart';
import 'widgets/circle_vod_player.dart';

class VideoComposePage extends StatefulWidget {
  final String token;
  final String userId;

  const VideoComposePage({super.key, required this.token, required this.userId});

  @override
  State<VideoComposePage> createState() => _VideoComposePageState();
}

class _VideoComposePageState extends State<VideoComposePage> {
  final _titleCtrl = TextEditingController();
  late final CircleApi _api = CircleApi(widget.token);
  String _visibility = 'public';
  bool _busy = false;
  bool _aiBusy = false;
  String? _videoUrl;
  String? _posterUrl;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await pickVideoBytes();
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _videoUrl = null;
      _posterUrl = null;
    });
    try {
      final uploaded = await _api.uploadVideoWithPoster(picked.bytes, userId: widget.userId, filename: picked.name);
      if (!mounted) return;
      setState(() {
        _videoUrl = uploaded.url;
        _posterUrl = uploaded.poster;
      });
      if ((uploaded.poster == null || uploaded.poster!.isEmpty) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('封面未自动生成，请点「设置封面」')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _suggestTitle() async {
    setState(() => _aiBusy = true);
    try {
      final text = await suggestCircleCopy(token: widget.token, userId: widget.userId, draft: _titleCtrl.text, forVideo: true);
      if (!mounted) return;
      _titleCtrl.text = text;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }


  Future<void> _pickPoster() async {
    if (_videoUrl == null || _videoUrl!.isEmpty) return;
    final picked = await pickImageBytes();
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final url = await _api.uploadMediaBytes(
        picked.bytes,
        userId: widget.userId,
        kind: 'image',
        filename: picked.name ?? 'poster.jpg',
      );
      if (!mounted) return;
      setState(() => _posterUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('封面上传失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (_videoUrl == null || _videoUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择并上传视频')));
      return;
    }
    if (_posterUrl == null || _posterUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请设置视频封面后再发布')));
      return;
    }
    setState(() => _busy = true);
    try {
      final post = await _api.createVideo(
        videoUrl: _videoUrl!,
        posterUrl: _posterUrl ?? '',
        text: _titleCtrl.text.trim(),
        visibility: _visibility,
      );
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发布失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _previewPane(ColorScheme scheme) {
    if (_videoUrl != null && _videoUrl!.isNotEmpty) {
      if (_posterUrl != null && _posterUrl!.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _posterUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => CircleVodPlayer(
                key: ValueKey(_videoUrl),
                url: _videoUrl!,
                posterUrl: '',
                active: true,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black38, Colors.transparent],
                ),
              ),
            ),
            const Center(child: Icon(Icons.play_circle_outline, size: 56, color: Colors.white70)),
          ],
        );
      }
      return CircleVodPlayer(
        key: ValueKey(_videoUrl),
        url: _videoUrl!,
        posterUrl: '',
        active: true,
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.video_library_outlined, size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text('点击选择视频', style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: circleComposeAppBar(
        context,
        title: '发视频',
        onPublish: _busy || _videoUrl == null || (_posterUrl == null || _posterUrl!.isEmpty) ? null : _publish,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : _pickVideo,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _previewPane(scheme),
                    if (_videoUrl != null && !_busy) ...[
                      const Positioned(
                        right: 10,
                        bottom: 10,
                        child: Chip(
                          label: Text('更换视频', style: TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (_posterUrl == null || _posterUrl!.isEmpty)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: ActionChip(
                            avatar: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('设置封面', style: TextStyle(fontSize: 12)),
                            onPressed: _pickPoster,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '视频标题 / 描述（可选）',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    border: InputBorder.none,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _aiBusy || _busy ? null : _suggestTitle,
                    icon: _aiBusy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.auto_awesome_outlined, size: 18, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                    label: Text('AI 写标题', style: TextStyle(color: AppTheme.brandBlue)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          circleSectionTitle(context, '谁可以看'),
          circleVisibilitySegments(
            value: _visibility,
            onChanged: _busy ? null : (v) => setState(() => _visibility = v),
          ),
          if (_busy) ...[
            const SizedBox(height: 28),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _videoUrl == null ? '上传中…' : '发布中…',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
