import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiClient {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path) async {
    final response = await http
        .get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: await _headers())
        .timeout(const Duration(seconds: 25));
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    return _decode(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body is Map && body['detail'] != null
            ? body['detail'].toString()
            : 'Request failed (${response.statusCode})',
      );
    }
    return body;
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: 'access_token', value: token);

  Future<String?> token() => _storage.read(key: 'access_token');

  Future<void> logout() => _storage.delete(key: 'access_token');
}
