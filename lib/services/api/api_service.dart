import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

/// Базовый HTTP клиент для работы с REST API сервера.
class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  String? _token; // JWT токен после авторизации
  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ── GET ───────────────────────────────────────────

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? params}) async {
    var uri = Uri.parse('${AppConfig.baseUrl}$path');
    if (params != null) uri = uri.replace(queryParameters: params);

    final res = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _handle(res);
  }

  // ── POST ──────────────────────────────────────────

  Future<Map<String, dynamic>> post(String path,
      Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _handle(res);
  }

  // ── PUT ───────────────────────────────────────────

  Future<Map<String, dynamic>> put(String path,
      Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('${AppConfig.baseUrl}$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _handle(res);
  }

  // ── DELETE ────────────────────────────────────────

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}$path'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    return _handle(res);
  }

  // ── Multipart (загрузка файлов) ───────────────────

  Future<Map<String, dynamic>> upload(String path, List<http.MultipartFile> files,
      {Map<String, String>? fields}) async {
    final req = http.MultipartRequest('POST',
        Uri.parse('${AppConfig.baseUrl}$path'));
    req.headers.addAll(_headers..remove('Content-Type'));
    req.files.addAll(files);
    if (fields != null) req.fields.addAll(fields);

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  // ── Обработка ответа ──────────────────────────────

  Map<String, dynamic> _handle(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
    }
    throw ApiException(res.statusCode, body);
  }
}

class ApiException implements Exception {
  final int    statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound     => statusCode == 404;
  bool get isServerError  => statusCode >= 500;
}
