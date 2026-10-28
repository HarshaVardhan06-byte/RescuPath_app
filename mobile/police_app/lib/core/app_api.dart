import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AppApi {
  static const _storage = FlutterSecureStorage();
  static String get baseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  Future<String?> token() => _storage.read(key: 'access_token');
  Future<void> saveToken(String value) => _storage.write(key: 'access_token', value: value);
  Future<void> logout() => _storage.delete(key: 'access_token');

  Future<dynamic> get(String path) async {
    final headers = await _headers();
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: headers).timeout(const Duration(seconds: 18));
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(Uri.parse('$baseUrl$path'), headers: await _headers(), body: jsonEncode(body)).timeout(const Duration(seconds: 18));
    return _decode(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await http.put(Uri.parse('$baseUrl$path'), headers: await _headers(), body: jsonEncode(body)).timeout(const Duration(seconds: 18));
    return _decode(response);
  }

  Future<Map<String, String>> _headers() async {
    final value = await token();
    return {'Content-Type': 'application/json', 'Accept': 'application/json', if (value != null && value.isNotEmpty) 'Authorization': 'Bearer $value'};
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try { body = jsonDecode(response.body); } catch (_) { body = response.body; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map ? body['detail'] : null;
      throw Exception(detail?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return body;
  }
}
