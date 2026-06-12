import 'api_client.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    required this.teamName,
    required this.isActive,
    this.avatarUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        fullName: json['full_name']?.toString(),
        role: json['role']?.toString() ?? '',
        teamName: json['team_name'] as String?,
        isActive: json['is_active'] as bool? ?? false,
        avatarUrl: json['avatar_url']?.toString(),
      );

  AuthUser copyWith({String? avatarUrl}) => AuthUser(
        id: id,
        email: email,
        fullName: fullName,
        role: role,
        teamName: teamName,
        isActive: isActive,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  final String id;
  final String email;
  final String? fullName;
  final String role;
  final String? teamName;
  final bool isActive;
  final String? avatarUrl;
}

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Future<List<String>> fetchTeams() async {
    final list = await _api.getList('/auth/teams');
    return list.cast<String>();
  }

  Future<AuthUser> register({
    required String email,
    required String password,
    required String fullName,
    required String teamName,
  }) async {
    final data = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
      'full_name': fullName,
      'team_name': teamName,
    });
    return AuthUser.fromJson(data);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    });
    _setTokensFromResponse(data);
  }

  /// Exchange a verified Cognito ID token for the local JWT pair (returning
  /// user whose RDS row already exists).
  Future<void> exchangeCognito(String idToken) async {
    final data = await _api.post('/auth/cognito', bearer: idToken);
    _setTokensFromResponse(data);
  }

  /// First Cognito sign-in: create/link the local user row (carrying the
  /// chosen team) and return the local JWT pair.
  Future<void> registerWithCognito(String idToken, String teamName) async {
    final data = await _api.post(
      '/auth/register_with_cognito',
      body: {'team_name': teamName},
      bearer: idToken,
    );
    _setTokensFromResponse(data);
  }

  void _setTokensFromResponse(Map<String, dynamic> data) {
    _api.setTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
  }

  Future<void> refresh() async {
    final rt = _api.refreshToken;
    if (rt == null) throw ApiException(401, 'No refresh token');
    final data = await _api.post('/auth/refresh', body: {
      'refresh_token': rt,
    });
    _api.setTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
  }

  Future<AuthUser> me() async {
    final data = await _api.get('/auth/me');
    return AuthUser.fromJson(data);
  }

  void logout() {
    _api.clearTokens();
  }
}
