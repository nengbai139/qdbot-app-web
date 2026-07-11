import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

Future<List<int>?> readPathBytesImpl(String path) async {
  try {
    if (path.startsWith('blob:')) {
      final resp = await web.window.fetch(path.toJS).toDart;
      if (!resp.ok) return null;
      final buf = await resp.arrayBuffer().toDart;
      return buf.toDart.asUint8List();
    }
    if (path.startsWith('http')) {
      final r = await http.get(Uri.parse(path));
      if (r.statusCode == 200) return r.bodyBytes;
    }
  } catch (_) {}
  return null;
}
