import 'package:flutter/material.dart';

import '../core/branding/branding_config.dart';
import '../core/data/superliga_teams.dart';
import '../core/routing/app_router.dart';
import '../core/state/auth_state.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_notifier.dart';
import '../core/widgets/team_accent_scope.dart';
import '../features/auth/presentation/email_verification_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';

class UmbraRoApp extends StatefulWidget {
  const UmbraRoApp({
    super.key,
    required this.authState,
    required this.themeMode,
  });

  final AuthState authState;
  final ThemeModeNotifier themeMode;

  @override
  State<UmbraRoApp> createState() => _UmbraRoAppState();
}

class _UmbraRoAppState extends State<UmbraRoApp> {
  late final AuthState _authState;
  late final ThemeModeNotifier _themeMode;

  @override
  void initState() {
    super.initState();
    _authState = widget.authState;
    _themeMode = widget.themeMode;
    _authState.addListener(_onChanged);
    _themeMode.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authState.removeListener(_onChanged);
    _themeMode.removeListener(_onChanged);
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: BrandingConfig.title,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode.mode,
      home: AppColorsScope(
        isDark: _themeMode.mode == ThemeMode.dark
            || (_themeMode.mode == ThemeMode.system
                && MediaQuery.platformBrightnessOf(context) == Brightness.dark),
        child: TeamAccentScope(
          team: teamByShort(_authState.user?.teamName),
          child: _buildRoot(),
        ),
      ),
    );
  }

  Widget _buildRoot() {
    if (_authState.loading) {
      return _SplashScreen(themeMode: _themeMode);
    }

    if (!_authState.isLoggedIn) {
      switch (_authState.stage) {
        case AuthFlowStage.login:
          return LoginScreen(
            authState: _authState,
            onRegisterTap: _authState.goToRegister,
          );
        case AuthFlowStage.register:
          return RegisterScreen(
            authState: _authState,
            onLoginTap: _authState.goToLogin,
          );
        case AuthFlowStage.verify:
          return EmailVerificationScreen(authState: _authState);
      }
    }

    return AppShell(authState: _authState, themeMode: _themeMode);
  }
}

/// Splash shown while the auth-restore is still pending. UmbraRo logo +
/// gradient base + a thin progress indicator at the bottom.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.themeMode});
  final ThemeModeNotifier themeMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Image.asset(
                BrandingConfig.logoFull,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

