import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// ponytail: file_picker web plugin missing from generated registrant; init once at startup
void registerFilePickerWeb() => FilePickerWeb.registerWith(webPluginRegistrar);
