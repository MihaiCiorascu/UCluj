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

  // API Gateway WebSocket connect URL for instant chat. App Runner is HTTP-only
  // and cannot serve WebSockets, so the chat socket points at the API Gateway
  // WS stage (e.g. wss://{apiId}.execute-api.eu-central-1.amazonaws.com/prod).
  // The chat client appends ?channel={channelId}&token={localAccessJwt}.
  // Blank by default so a missing config.json simply disables the live socket
  // (history + REST send still work) rather than dialling a bad URL.
  static const String _compiledWsConnectUrl = String.fromEnvironment(
    'WS_CONNECT_URL',
    defaultValue: '',
  );

  // AWS Cognito user pool, consumed by the Amplify Auth plugin (and matched by
  // the backend, which verifies the Cognito ID token against this pool). Blank
  // by default so a build with no Cognito pool simply runs the local
  // email/password auth fallback instead of trying to talk to Cognito.
  static const String _compiledUserPoolId =
      String.fromEnvironment('COGNITO_USER_POOL_ID', defaultValue: '');
  static const String _compiledAppClientId =
      String.fromEnvironment('COGNITO_APP_CLIENT_ID', defaultValue: '');
  static const String cognitoRegion =
      String.fromEnvironment('COGNITO_REGION', defaultValue: 'eu-central-1');

  static String _runtimeApiUrl = _compiledApiUrl;
  static String get apiBaseUrl => _runtimeApiUrl;

  static String _runtimeWsConnectUrl = _compiledWsConnectUrl;
  static String get wsConnectUrl => _runtimeWsConnectUrl;

  static String _runtimeUserPoolId = _compiledUserPoolId;
  static String get cognitoUserPoolId => _runtimeUserPoolId;

  static String _runtimeAppClientId = _compiledAppClientId;
  static String get cognitoAppClientId => _runtimeAppClientId;

  // On web, fetch /config.json at runtime so the API URL, WS URL, and Cognito
  // pool can be updated without a full Flutter rebuild.
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
        final wsUrl = data['wsConnectUrl'] as String?;
        if (wsUrl != null && wsUrl.isNotEmpty) _runtimeWsConnectUrl = wsUrl;
        final poolId = data['cognitoUserPoolId'] as String?;
        if (poolId != null && poolId.isNotEmpty) _runtimeUserPoolId = poolId;
        final clientId = data['cognitoAppClientId'] as String?;
        if (clientId != null && clientId.isNotEmpty) {
          _runtimeAppClientId = clientId;
        }
      }
    } catch (_) {}
  }
}
