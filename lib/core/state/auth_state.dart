import 'package:flutter/foundation.dart';
import 'package:umbraro/core/observability/app_logger.dart';
import 'package:umbraro/core/services/api_client.dart' show ApiClient, ApiException;
import 'package:umbraro/core/services/auth_service.dart';
import 'package:umbraro/data/auth/auth_session_repository.dart';

class AuthState extends ChangeNotifier {
  AuthState({
    required this.api,
    required AuthService auth,
    required AuthSessionRepository session,
    bool runSessionRestore = true,
  })  : _auth = auth,
        _session = session {
    if (runSessionRestore) {
      _tryRestoreSession();
    } else {
      _loading = false;
    }
  }

  final ApiClient api;
  final AuthService _auth;
  final AuthSessionRepository _session;

  AuthUser? _user;
  bool _loading = true;
  String? _error;

  AuthUser? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  String? get error => _error;
  AuthService get authService => _auth;

  Future<void> _tryRestoreSession() async {
    _loading = true;
    notifyListeners();
    try {
      final r = await _session.restoreColdStart();
      _user = r.user;
    } catch (_) {
      await _session.signOut();
      _user = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      _user = await _session.signInWithEmailPassword(email, password);
      if (_user == null) {
        _error = 'Sign in failed';
        return false;
      }
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _user = null;
      return false;
    } catch (e) {
      AppLog.e('login error', e);
      _error = 'Could not complete login. Check backend connection.';
      _user = null;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String teamName,
  }) async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      _user = await _session.signUpWithPassword(email, password, fullName, teamName);
      if (_user == null) {
        _error = 'Registration failed';
        return false;
      }
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _user = null;
      return false;
    } catch (e) {
      AppLog.e('register error', e);
      _error = 'Could not complete registration. Check backend connection.';
      _user = null;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void updateAvatarUrl(String url) {
    if (_user == null) return;
    _user = _user!.copyWith(avatarUrl: url);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _session.signOut();
    } finally {
      _user = null;
      _error = null;
      notifyListeners();
    }
  }
}
