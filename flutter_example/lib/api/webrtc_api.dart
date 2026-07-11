import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class WebrtcApi {
  final String token;
  WebrtcApi(this.token);

  /// 从独立 relay 拉取 ICE/TURN 配置；失败时返回 null
  Future<List<Map<String, dynamic>>?> fetchIceServers() async {
    final base = AppConfig.webrtcRelayUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v1/ice-servers');
    try {
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final raw = data['iceServers'];
      if (raw is! List) return null;
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }
}

/// 内置 STUN 兜底（relay 不可用时）
List<Map<String, dynamic>> fallbackIceServers() => [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
