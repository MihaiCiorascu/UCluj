import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:umbraro/core/config/app_config.dart';

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  // 90s, not 35s: a cold App Runner instance (deploy / idle-resume / autoscale)
  // can take up to ~75s on its first heavy request before the startup pre-warm
  // lands. A longer ceiling turns that rare cold hit into a slow load behind the
  // loading skeleton instead of a hard ApiException(408). Warm requests are ~2ms.
  static const Duration _requestTimeout = Duration(seconds: 90);

  final String _baseUrl;
  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null;

  void setTokens({required String access, required String refresh}) {
    _accessToken = access;
    _refreshToken = refresh;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
          )
          .timeout(_requestTimeout);
      return _handleMap(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out. Check backend connection.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(0, 'Network error: $e');
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(_requestTimeout);
      return _handleMap(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out. Check backend connection.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(0, 'Network error: $e');
    }
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required List<int> fileBytes,
    required String fileName,
    String fileField = 'file',
  }) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'));

      // Add authorization header if available
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }

      final multipartFile = http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: fileName,
      );

      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      return _handleMap(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out. Check backend connection.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(0, 'Network error: $e');
    }
  }

  Future<List<dynamic>> getList(String path) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
          )
          .timeout(_requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      _throwError(response);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out. Check backend connection.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(0, 'Network error: $e');
    }
  }

  Map<String, dynamic> _handleMap(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _throwError(response);
  }

  Never _throwError(http.Response response) {
    Object? detail;
    String message = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded.containsKey('detail')) {
        final d = decoded['detail'];
        detail = d;
        if (d is String) {
          message = d;
        } else if (d is Map) {
          message =
              d['message'] as String? ?? d['code'] as String? ?? d.toString();
        } else {
          message = d.toString();
        }
      }
    } catch (_) {}
    throw ApiException(response.statusCode, message, detail: detail);
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;
  final Object? detail;

  bool get isNeedsRegistration {
    if (detail is Map) {
      return (detail as Map)['code'] == 'NEEDS_REGISTRATION';
    }
    return message == 'NEEDS_REGISTRATION' ||
        message.contains('NEEDS_REGISTRATION');
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
