import 'dart:io' show File;

Future<List<int>?> readPathBytesImpl(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  } catch (_) {
    return null;
  }
}
