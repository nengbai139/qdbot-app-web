import 'package:url_launcher/url_launcher.dart';

Future<void> openFileUrlImpl(String src, {String? name}) async {
  final uri = Uri.parse(src);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) throw Exception('无法打开文件');
}
