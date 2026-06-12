import 'package:flutter/material.dart';
import 'package:umbraro/core/auth/amplify_config.dart';
import 'package:umbraro/core/config/app_config.dart';
import 'package:umbraro/core/l10n/strings.dart';
import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/observability/global_error_reporter.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/state/meta_state.dart';
import 'package:umbraro/core/storage/token_store.dart';
import 'package:umbraro/core/theme/theme_mode_notifier.dart';
import 'package:umbraro/data/auth/auth_session_repository.dart';

import 'app.dart';
import '../core/theme/theme_notifier.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  installGlobalErrorHandlers();
  await AppConfig.load();
  // Configure Amplify Cognito from the runtime config. No-ops (and the app
  // stays on local-auth) when no Cognito pool is provisioned.
  await configureAmplify();
  await L10n.instance.load();
  ThemeNotifier.instance.init();

  AppLog.i('UmbraRo bootstrap: env=${AppConfig.appEnv} api=${AppConfig.apiBaseUrl}');

  final api = ApiClient();
  final tokenStore = TokenStore();
  final auth = AuthService(api);
  final session = AuthSessionRepository(
    api: api,
    auth: auth,
    tokenStore: tokenStore,
  );
  final authState = AuthState(
    api: api,
    auth: auth,
    session: session,
  );
  // Meta is no-auth and harmless; fire-and-forget so the ribbon can light up
  // as soon as the response lands without blocking the splash screen.
  // ignore: discarded_futures
  MetaState.instance.init(api);
  // Iteration N — load the persisted light/dark preference before
  // mounting the app so the first frame paints with the right palette.
  final themeMode = await ThemeModeNotifier.load();
  runApp(UmbraRoApp(authState: authState, themeMode: themeMode));
}
