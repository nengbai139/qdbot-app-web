import 'package:connectivity_plus/src/connectivity_plus_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// ponytail: livekit_client 依赖 connectivity_plus；Web 上需显式注册，否则 MissingPluginException(check)
void registerConnectivityWeb() => ConnectivityPlusWebPlugin.registerWith(webPluginRegistrar);
