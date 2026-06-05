import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  /// Upload a new profile picture via the S3 presigned-URL flow:
  ///   1. POST /auth/me/avatar-upload-url → { uploadUrl, avatarUrl }
  ///   2. http.put the raw JPEG bytes straight to the presigned S3 URL
  ///      (Content-Type: image/jpeg, NOT multipart — S3 rejects multipart on a
  ///      single-object PUT and the signature is bound to that content type).
  ///   3. PUT /auth/me/avatar with { avatar_url } to persist on the user row;
  ///      the backend returns the full UserResponse incl. the cache-busted URL.
  /// On success the local user is refreshed and listeners are notified.
  /// Returns false on any failure.
  Future<bool> uploadAvatar(Uint8List bytes) async {
    if (_user == null || bytes.isEmpty) return false;
    try {
      // 1) Ask the backend for a presigned PUT URL + the public avatar URL.
      final signed = await api.post('/auth/me/avatar-upload-url');
      final uploadUrl = signed['uploadUrl'] as String?;
      final avatarUrl = signed['avatarUrl'] as String?;
      if (uploadUrl == null || uploadUrl.isEmpty ||
          avatarUrl == null || avatarUrl.isEmpty) {
        return false;
      }

      // 2) Direct PUT of the raw bytes to S3. This bypasses ApiClient on
      //    purpose: no Authorization header, no JSON wrapping — the presigned
      //    URL carries its own auth and the body must be the image itself.
      final putRes = await http
          .put(
            Uri.parse(uploadUrl),
            headers: const {'Content-Type': 'image/jpeg'},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        AppLog.e('avatar S3 PUT failed', putRes.statusCode);
        return false;
      }

      // 3) Persist the public URL on the user row (JSON, not multipart).
      final data = await api.put('/auth/me/avatar', body: {
        'avatar_url': avatarUrl,
      });
      _user = AuthUser.fromJson(data);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      AppLog.e('uploadAvatar api error', e);
      return false;
    } catch (e) {
      AppLog.e('uploadAvatar error', e);
      return false;
    }
  }

  /// Update the signed-in user's display name via the backend, then refresh
  /// the local user. Returns false on empty input or a failed request.
  Future<bool> updateName(String name) async {
    final n = name.trim();
    if (_user == null || n.isEmpty) return false;
    try {
      final data = await api.post('/auth/me', body: {'full_name': n});
      _user = AuthUser.fromJson(data);
      notifyListeners();
      return true;
    } catch (e) {
      AppLog.e('updateName error', e);
      return false;
    }
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
