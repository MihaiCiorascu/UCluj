import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:umbraro/core/config/app_config.dart';
import 'package:umbraro/core/l10n/strings.dart';
import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/observability/global_error_reporter.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/storage/token_store.dart';
import 'package:umbraro/data/auth/auth_session_repository.dart';
import 'package:umbraro/data/user/user_profile_sync.dart';
import 'package:umbraro/core/observability/enable_crashlytics_if_supported.dart' show enableCrashlyticsIfSupported;
import 'package:umbraro/firebase_options.dart';

import 'app.dart';
import '../core/theme/theme_notifier.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  installGlobalErrorHandlers();
  await AppConfig.load();
  await L10n.instance.load();
  // ignore: unawaited_futures — fire-and-forget, default dark used until ready
  ThemeNotifier.instance.init();

  if (AppConfig.useFirebaseAuth) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      try {
        FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
      } catch (_) {}
      await enableCrashlyticsIfSupported();
      AppLog.i('UmbraRo metrics: firebase_init_ok env=${AppConfig.appEnv}');
    } catch (e, s) {
      AppLog.e('Firebase init failed (continue with legacy path where possible)', e, s);
    }
  }

  final api = ApiClient();
  final tokenStore = TokenStore();
  final auth = AuthService(api);
  final profile = AppConfig.useFirebaseAuth ? UserProfileSync() : null;
  final session = AuthSessionRepository(
    api: api,
    auth: auth,
    tokenStore: tokenStore,
    userProfileSync: profile,
  );
  final authState = AuthState(
    api: api,
    auth: auth,
    session: session,
  );
  runApp(UmbraRoApp(authState: authState));
}
