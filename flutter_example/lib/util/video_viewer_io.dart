import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/media_url.dart';

Future<void> showVideoViewerImpl(BuildContext context, String src, {String? name}) async {
  final url = publicMediaUrl(src);
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    throw Exception('无法打开视频');
  }
}

Future<void> downloadVideoImpl(String src, {String? name}) async {
  final url = publicMediaUrl(src);
  await Share.shareUri(Uri.parse(url));
}
