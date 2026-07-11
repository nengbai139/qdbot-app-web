import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'circle_ui.dart';
import 'live_backdrop.dart';

/// 开播前准备：封面 + 标题 + 一键开播（简洁沉浸）
class LiveHostPrepView extends StatelessWidget {
  final TextEditingController titleController;
  final String coverUrl;
  final Uint8List? localCoverBytes;
  final bool busy;
  final bool resuming;
  final VoidCallback onPickCover;
  final VoidCallback onStart;
  final VoidCallback onClose;
  final VoidCallback onObsHelp;

  const LiveHostPrepView({
    super.key,
    required this.titleController,
    required this.coverUrl,
    this.localCoverBytes,
    required this.busy,
    this.resuming = false,
    required this.onPickCover,
    required this.onStart,
    required this.onClose,
    required this.onObsHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(onTap: busy ? null : onPickCover, child: _hero(coverUrl, localCoverBytes)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 26),
                    onPressed: busy ? null : onClose,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: kLiveAccent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('准备开播', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: busy ? null : onPickCover,
                            icon: const Icon(Icons.image_outlined, size: 16, color: Colors.white70),
                            label: const Text('选虚拟背景', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        enabled: !busy,
                        maxLength: 40,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: '给直播起个标题',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 22, fontWeight: FontWeight.w500),
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '虚拟背景：开摄像头后身后将替换为已选背景墙（网页）',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : onStart,
                        style: FilledButton.styleFrom(
                          backgroundColor: kLiveAccent,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(resuming ? '开始直播' : '创建并开播', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: busy ? null : onObsHelp,
                          child: Text('电脑 OBS 推流说明', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(String url, Uint8List? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (url.isNotEmpty) {
      return LiveBackdrop(coverUrl: url, dimmed: false);
    }
    return const LiveBackdrop(dimmed: false);
  }
}

/// OBS 推流说明（按需展开，不占主界面）
Future<void> showLiveObsHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kLiveSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('电脑 OBS 推流', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              '网页可一键摄像头推流；若用 OBS：\n'
              '1. 安装 OBS Studio（obsproject.com）\n'
              '2. 设置 → 推流 → 服务选「自定义」\n'
              '3. 开播后在本页「更多 → 推流设置」复制服务器与密钥\n'
              '4. 在 OBS 点「开始推流」',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx), style: FilledButton.styleFrom(backgroundColor: kLiveAccent), child: const Text('知道了')),
          ],
        ),
      ),
    ),
  );
}
