import 'package:web/web.dart' as web;

/// 同源 URL 直接触发下载，无需把整个文件读进内存
void downloadMediaUrl(String src, String filename) {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = src
    ..download = filename
    ..target = '_blank';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

void openUrlInNewTab(String src) {
  web.window.open(src, '_blank');
}
