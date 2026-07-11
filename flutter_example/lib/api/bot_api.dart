import 'package:http/http.dart' as http;
import 'api_client.dart';

class BotApi {
  final ApiClient _c;
  BotApi(String token) : _c = ApiClient(token: token);

  Future<http.Response> getConfig() => _c.get('/app/im/bot/config');

  Future<http.Response> updateConfig(Map<String, dynamic> body) =>
      _c.put('/app/im/bot/config', body: body);
}
