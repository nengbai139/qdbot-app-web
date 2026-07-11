import 'package:http/http.dart' as http;
import 'api_client.dart';
import '../session.dart';

class PushApi {
  final ApiClient _c;
  PushApi(String token) : _c = ApiClient(token: token);

  Future<http.Response> register({
    required String userId,
    required String deviceId,
    required String platform,
    required String token,
  }) =>
      _c.post('/app/push/register', body: {
        'userId': userId,
        'deviceId': deviceId,
        'platform': platform,
        'token': token,
      });

  Future<http.Response> unregister({required String userId, required String token}) =>
      _c.post('/app/push/unregister', body: {'userId': userId, 'token': token});

  Future<Map<String, dynamic>> status() async {
    final resp = await _c.get('/app/push/status');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return ApiClient.decode(resp);
  }

  Future<void> setDeviceNotify({required bool enabled, String? deviceId}) async {
    final did = deviceId ?? await SessionStore.loadOrCreateDeviceId();
    final resp = await _c.put('/app/push/device', body: {'deviceId': did, 'enabled': enabled});
    if (resp.statusCode != 200) throw Exception(resp.body);
  }
}
