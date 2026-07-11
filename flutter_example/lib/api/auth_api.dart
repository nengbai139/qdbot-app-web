import 'package:http/http.dart' as http;
import 'api_client.dart';

class AuthApi {
  Future<http.Response> sendLoginCode(String email) => publicApi.post(
        '/app/auth/verification/send-code',
        body: {'email': email, 'purpose': 'login'},
      );

  Future<http.Response> login({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) =>
      publicApi.post('/app/auth/login', body: {
        'email': email,
        'password': password,
        'deviceId': deviceId,
        'platform': platform,
      });

  Future<http.Response> sendRegisterCode(String email) => publicApi.post(
        '/app/auth/verification/send-code',
        body: {'email': email, 'purpose': 'register'},
      );

  Future<http.Response> register(Map<String, dynamic> body) =>
      publicApi.post('/app/auth/register', body: body);

  Future<http.Response> tenants() => publicApi.get('/app/auth/tenants');

  Future<http.Response> businesses(String tenantId) =>
      publicApi.get('/app/auth/businesses', query: {'tenantId': tenantId});

  Future<http.Response> devices() => publicApi.get('/app/auth/devices');

  Future<http.Response> checkPremiumCode(String code) => publicApi.post(
        '/app/auth/check-premium-code',
        body: {'code': code},
      );

  Future<http.Response> userByCode(String code) =>
      publicApi.get('/app/auth/user-by-code', query: {'userCode': code});

  Future<http.Response> deviceStatus(String deviceId) =>
      publicApi.get('/app/device/status', query: {'deviceId': deviceId});
}

final authApi = AuthApi();
