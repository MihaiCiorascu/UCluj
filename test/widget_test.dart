import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbraro/app/app.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/storage/token_store.dart';
import 'package:umbraro/core/theme/theme_mode_notifier.dart';
import 'package:umbraro/data/auth/auth_session_repository.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1/api/v1');
    final store = TokenStore();
    final auth = AuthService(api);
    final session = AuthSessionRepository(
      api: api,
      auth: auth,
      tokenStore: store,
    );
    final st = AuthState(
      api: api,
      auth: auth,
      session: session,
      runSessionRestore: false,
    );
    await tester.pumpWidget(UmbraRoApp(
      authState: st,
      themeMode: ThemeModeNotifier(ThemeMode.light),
    ));
  });
}
