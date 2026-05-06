import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/storage/token_store.dart';

class AuthSessionRepository {
  AuthSessionRepository({
    required this.api,
    required this.auth,
    required this.tokenStore,
  });

  final ApiClient api;
  final AuthService auth;
  final TokenStore tokenStore;

  Future<({AuthUser? user})> restoreColdStart() async {
    final pair = await tokenStore.read();
    if (pair != null) {
      api.setTokens(access: pair.access, refresh: pair.refresh);
      try {
        final me = await auth.me();
        return (user: me);
      } on ApiException catch (e) {
        AppLog.w('UmbraRo auth: token restore /me failed: $e');
        await tokenStore.clear();
        api.clearTokens();
      }
    }
    return (user: null);
  }

  Future<void> signOut() async {
    auth.logout();
    await tokenStore.clear();
  }

  Future<AuthUser?> signInWithEmailPassword(String email, String password) async {
    await auth.login(email: email, password: password);
    final me = await auth.me();
    final a = api.accessToken;
    final r = api.refreshToken;
    if (a != null && r != null) await tokenStore.write(access: a, refresh: r);
    return me;
  }

  Future<AuthUser?> signUpWithPassword(
    String email,
    String password,
    String fullName,
    String teamName,
  ) async {
    await auth.register(
      email: email,
      password: password,
      fullName: fullName,
      teamName: teamName,
    );
    await auth.login(email: email, password: password);
    final me = await auth.me();
    final a = api.accessToken;
    final r = api.refreshToken;
    if (a != null && r != null) await tokenStore.write(access: a, refresh: r);
    return me;
  }
}
