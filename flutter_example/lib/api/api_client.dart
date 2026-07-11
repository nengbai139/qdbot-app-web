import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiClient {
  final String? token;

  const ApiClient({this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('${AppConfig.baseUrl}$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Future<http.Response> get(String path, {Map<String, String>? query}) =>
      http.get(_uri(path, query), headers: _headers);

  Future<http.Response> post(String path, {Object? body}) => http.post(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  Future<http.Response> put(String path, {Object? body}) => http.put(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  Future<http.Response> patch(String path, {Object? body}) => http.patch(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  Future<http.Response> delete(String path) =>
      http.delete(_uri(path), headers: _headers);

  static Map<String, dynamic> decode(http.Response resp) =>
      jsonDecode(resp.body) as Map<String, dynamic>;
}

/// 无 token 的公开 API
final publicApi = ApiClient();
