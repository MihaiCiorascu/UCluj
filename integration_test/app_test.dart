import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:umbraro/app/app.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/storage/token_store.dart';
import 'package:umbraro/core/theme/theme_mode_notifier.dart';
import 'package:umbraro/data/auth/auth_session_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auth gate with session restore off shows login', (tester) async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:1/api/v1');
    final auth = AuthService(api);
    final st = AuthState(
      api: api,
      auth: auth,
      session: AuthSessionRepository(
        api: api,
        auth: auth,
        tokenStore: TokenStore(),
      ),
      runSessionRestore: false,
    );
    await tester.pumpWidget(UmbraRoApp(
      authState: st,
      themeMode: ThemeModeNotifier(ThemeMode.light),
    ));
    await tester.pump();
    expect(find.text('SIGN IN'), findsOneWidget);
  });
}
