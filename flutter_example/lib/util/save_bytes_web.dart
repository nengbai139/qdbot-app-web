import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<bool> saveBytesAsFile(Uint8List bytes, String filename) async {
  final blobParts = ([bytes.toJS].toJS) as JSArray<web.BlobPart>;
  final blob = web.Blob(blobParts);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
