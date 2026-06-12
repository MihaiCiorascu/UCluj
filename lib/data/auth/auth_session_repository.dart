import 'package:amplify_auth_cognito/amplify_auth_cognito.dart' hide AuthUser;
import 'package:amplify_flutter/amplify_flutter.dart'
    hide AuthUser, ApiException;
import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/services/api_client.dart';
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/core/storage/token_store.dart';

/// Result of a Cognito sign-up: whether the account still needs the emailed
/// confirmation code, or was already confirmed (only possible if the pool is
/// configured to auto-confirm, which UmbraRo's is not).
enum SignUpOutcome { needsConfirmation, complete }

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
    try {
      if (Amplify.isConfigured) await Amplify.Auth.signOut();
    } catch (e) {
      AppLog.w('UmbraRo auth: Amplify signOut failed: $e');
    }
    auth.logout();
    await tokenStore.clear();
  }

  // ── Local email/password fallback ────────────────────────────────────────
  // Used when Cognito is not provisioned (AppConfig.cognitoUserPoolId empty).

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

  // ── Cognito + Amplify path ───────────────────────────────────────────────

  Future<SignUpOutcome> signUpCognito(
    String email,
    String password,
    String fullName,
  ) async {
    final res = await Amplify.Auth.signUp(
      username: email,
      password: password,
      options: SignUpOptions(
        userAttributes: {
          AuthUserAttributeKey.email: email,
          AuthUserAttributeKey.name: fullName,
        },
      ),
    );
    return res.isSignUpComplete
        ? SignUpOutcome.complete
        : SignUpOutcome.needsConfirmation;
  }

  /// Confirm the emailed code, sign in, and exchange for the local JWT pair,
  /// creating the RDS user row (with the chosen team) on first confirmation.
  Future<AuthUser?> confirmCognito(
    String email,
    String code,
    String password,
    String teamName,
  ) async {
    await Amplify.Auth.confirmSignUp(
      username: email,
      confirmationCode: code,
    );
    await _amplifySignIn(email, password);
    return _afterCognitoSignedIn(teamName);
  }

  /// Returning-user sign-in. Throws [UserNotConfirmedException] if the account
  /// has never confirmed its email (the caller routes to the verify screen).
  Future<AuthUser?> signInCognito(
    String email,
    String password, {
    String? teamName,
  }) async {
    await _amplifySignIn(email, password);
    return _afterCognitoSignedIn(teamName);
  }

  Future<void> resendCognitoCode(String email) async {
    await Amplify.Auth.resendSignUpCode(username: email);
  }

  Future<void> _amplifySignIn(String email, String password) async {
    // Clear any lingering Cognito session first, so signIn does not fail with
    // an already-signed-in error.
    try {
      final existing = await Amplify.Auth.fetchAuthSession();
      if (existing.isSignedIn) await Amplify.Auth.signOut();
    } catch (_) {}
    final res = await Amplify.Auth.signIn(username: email, password: password);
    // An unconfirmed account either throws UserNotConfirmedException directly
    // or returns a confirmSignUp next step; normalise both to the exception so
    // the caller routes to the verify screen.
    if (!res.isSignedIn &&
        res.nextStep.signInStep == AuthSignInStep.confirmSignUp) {
      throw UserNotConfirmedException('User is not confirmed.');
    }
  }

  Future<AuthUser?> _afterCognitoSignedIn(String? teamName) async {
    final idToken = await _cognitoIdToken();
    try {
      await auth.exchangeCognito(idToken);
    } on ApiException catch (e) {
      // No RDS row yet (first confirmation): create it via the register path,
      // carrying the chosen team (or the default if we arrived from sign-in).
      if (e.isNeedsRegistration || e.statusCode == 404) {
        await auth.registerWithCognito(idToken, teamName ?? 'U Cluj');
      } else {
        rethrow;
      }
    }
    final me = await auth.me();
    final a = api.accessToken;
    final r = api.refreshToken;
    if (a != null && r != null) await tokenStore.write(access: a, refresh: r);
    return me;
  }

  Future<String> _cognitoIdToken() async {
    final session =
        await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    return session.userPoolTokensResult.value.idToken.raw;
  }
}
