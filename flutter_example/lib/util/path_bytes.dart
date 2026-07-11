import 'path_bytes_stub.dart' if (dart.library.io) 'path_bytes_io.dart' if (dart.library.html) 'path_bytes_web.dart';

Future<List<int>?> readPathBytes(String path) => readPathBytesImpl(path);
