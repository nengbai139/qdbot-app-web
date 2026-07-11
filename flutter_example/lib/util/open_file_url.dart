import 'open_file_url_stub.dart' if (dart.library.io) 'open_file_url_io.dart' if (dart.library.html) 'open_file_url_web.dart';

Future<void> openRemoteFile(String src, {String? name}) => openFileUrlImpl(src, name: name);
