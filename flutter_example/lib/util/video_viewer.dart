import 'package:flutter/material.dart';

import 'video_viewer_stub.dart' if (dart.library.io) 'video_viewer_io.dart' if (dart.library.html) 'video_viewer_web.dart';

Future<void> showVideoViewer(BuildContext context, String url, {String? name}) =>
    showVideoViewerImpl(context, url, name: name);

Future<void> downloadVideo(String url, {String? name}) => downloadVideoImpl(url, name: name);

void showVideoActionSheet(
  BuildContext context, {
  required String url,
  String? name,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('播放'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await showVideoViewer(context, url, name: name);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法播放: $e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('下载'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await downloadVideo(url, name: name);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已开始下载')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}
