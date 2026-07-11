import 'package:flutter/material.dart';

import 'media_url.dart';
import 'audio_playback_platform.dart';
import 'voice_transcribe.dart';

/// 全局只允许一条语音在播（微信式）
class AudioPlaybackHub {
  static final _listeners = <VoidCallback>{};
  static var _wired = false;

  static void _wireOnce() {
    if (_wired) return;
    _wired = true;
    bindPlatformPlaybackEvents(_notify);
  }

  static String? get playingUrl => platformPlayingUrl();

  static void addListener(VoidCallback fn) => _listeners.add(fn);
  static void removeListener(VoidCallback fn) => _listeners.remove(fn);

  static void _notify() {
    for (final fn in List<VoidCallback>.from(_listeners)) {
      fn();
    }
  }

  static Future<void> toggle(String url, {String? filename}) async {
    _wireOnce();
    if (url.isEmpty) throw Exception('语音地址无效');
    final src = publicMediaUrl(url);
    await platformToggle(src, filename: filename);
    _notify();
  }

  static Future<void> download(String url, {String? filename}) async {
    if (url.isEmpty) throw Exception('语音地址无效');
    await platformDownload(publicMediaUrl(url), filename: filename);
  }

  static Future<void> stopAll() async {
    await platformStopAll();
    _notify();
  }
}

void showVoiceActionSheet(
  BuildContext context, {
  required String url,
  String? name,
  String? token,
  VoidCallback? onTranscriptReady,
}) {
  final filename = (name != null && name.isNotEmpty) ? name : 'voice.webm';
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (token != null && token.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('转文字'),
              onTap: () async {
                Navigator.pop(ctx);
                await runVoiceTranscribe(
                  context,
                  token: token,
                  url: url,
                  onReady: onTranscriptReady,
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('播放'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await AudioPlaybackHub.toggle(url, filename: filename);
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
                await AudioPlaybackHub.download(url, filename: filename);
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

Future<void> runVoiceTranscribe(
  BuildContext context, {
  required String token,
  required String url,
  VoidCallback? onReady,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('语音转文字中…'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    await transcribeVoiceUrl(token, url);
    if (context.mounted) Navigator.pop(context);
    onReady?.call();
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
