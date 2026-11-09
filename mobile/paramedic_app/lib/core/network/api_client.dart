import 'dart:async';
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

  Future<dynamic> _withRetry(Future<http.Response> Function() req) async {
    try {
      final response = await req().timeout(const Duration(seconds: 75));
      return _decode(response);
    } on TimeoutException {
      // Retry once on initial cold start
      try {
        final response = await req().timeout(const Duration(seconds: 45));
        return _decode(response);
      } catch (_) {
        throw Exception('Server is warming up or connection timed out. Please retry.');
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Server connection timed out. Please retry.');
      }
      rethrow;
    }
  }

  Future<dynamic> get(String path) async {
    return _withRetry(() async => http.get(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: await _headers()));
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _withRetry(() async => http.post(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    return _withRetry(() async => http.put(
          Uri.parse('${AppConfig.apiBaseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> delete(String path) async {
    return _withRetry(() async => http.delete(Uri.parse('${AppConfig.apiBaseUrl}$path'), headers: await _headers()));
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = body is Map && body['detail'] != null
          ? body['detail'].toString()
          : 'Request failed (${response.statusCode})';
      if (detail.toLowerCase().contains('gst')) {
        detail = 'Invalid email address or password';
      }
      throw Exception(detail);
    }
    return body;
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: 'access_token', value: token);

  Future<String?> token() => _storage.read(key: 'access_token');

  Future<void> logout() => _storage.delete(key: 'access_token');
}
