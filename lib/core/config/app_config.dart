import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class AppConfig {
  AppConfig._();

  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');

  static const String _compiledApiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static String _runtimeApiUrl = _compiledApiUrl;
  static String get apiBaseUrl => _runtimeApiUrl;

  // On web, fetch /config.json at runtime so the API URL can be updated
  // without a full Flutter rebuild.
  static Future<void> load() async {
    if (!kIsWeb) return;
    try {
      final res = await http
          .get(Uri.parse('/config.json'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final url = data['apiBaseUrl'] as String?;
        if (url != null && url.isNotEmpty) _runtimeApiUrl = url;
      }
    } catch (_) {}
  }
}
