import 'dart:typed_data';

import 'save_bytes_stub.dart' if (dart.library.html) 'save_bytes_web.dart' as save_bytes_impl;

Future<bool> saveBytesAsFile(Uint8List bytes, String filename) =>
    save_bytes_impl.saveBytesAsFile(bytes, filename);
