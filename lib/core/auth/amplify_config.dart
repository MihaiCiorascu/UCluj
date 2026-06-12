import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:umbraro/core/config/app_config.dart';
import 'package:umbraro/core/observability/app_logger.dart';

/// Configures the AWS Amplify Auth (Cognito) plugin from the runtime config
/// (`web/config.json` on web, `--dart-define` on native).
///
/// Safe to call when Cognito is not provisioned: if the pool id or app client
/// id is missing it simply no-ops, and the app keeps using the local
/// email/password authentication fallback. This lets the app build and run
/// before any Cognito pool exists, then pick up Cognito automatically once the
/// two values are filled in.
Future<void> configureAmplify() async {
  if (Amplify.isConfigured) return;
  if (AppConfig.cognitoUserPoolId.isEmpty ||
      AppConfig.cognitoAppClientId.isEmpty) {
    AppLog.i('UmbraRo auth: Cognito not configured, using local-auth fallback');
    return;
  }
  try {
    await Amplify.addPlugin(AmplifyAuthCognito());
    await Amplify.configure(_buildConfig());
    AppLog.i('UmbraRo auth: Amplify Cognito configured');
  } catch (e) {
    // A configuration failure must never crash the splash; the app falls back
    // to local auth (Cognito calls are only made when the pool id is present,
    // and a failed configure leaves Amplify.isConfigured false).
    AppLog.e('UmbraRo auth: Amplify configure failed', e);
  }
}

String _buildConfig() {
  final cfg = {
    'UserAgent': 'aws-amplify-cli/2.0',
    'Version': '1.0',
    'auth': {
      'plugins': {
        'awsCognitoAuthPlugin': {
          'UserAgent': 'aws-amplify-cli/0.1.0',
          'Version': '0.1.0',
          'CognitoUserPool': {
            'Default': {
              'PoolId': AppConfig.cognitoUserPoolId,
              'AppClientId': AppConfig.cognitoAppClientId,
              'Region': AppConfig.cognitoRegion,
            },
          },
          'Auth': {
            'Default': {
              'authenticationFlowType': 'USER_SRP_AUTH',
              'signupAttributes': ['EMAIL'],
              'verificationMechanisms': ['EMAIL'],
            },
          },
        },
      },
    },
  };
  return jsonEncode(cfg);
}
