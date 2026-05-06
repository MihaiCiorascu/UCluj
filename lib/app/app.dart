import 'package:flutter/material.dart';

import '../core/l10n/strings.dart';
import '../core/state/auth_state.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_notifier.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../core/routing/app_router.dart';

class UmbraRoApp extends StatefulWidget {
  const UmbraRoApp({super.key, required this.authState});

  final AuthState authState;

  @override
  State<UmbraRoApp> createState() => _UmbraRoAppState();
}

class _UmbraRoAppState extends State<UmbraRoApp> {
  late final AuthState _authState;

  @override
  void initState() {
    super.initState();
    _authState = widget.authState;
    _authState.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([L10n.instance, ThemeNotifier.instance]),
      builder: (context, _) {
        final isDark = ThemeNotifier.instance.isDark;
        return AppColorsScope(
          isDark: isDark,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'U Cluj — Tactical Intelligence',
            theme: AppTheme.lightThemeData,
            darkTheme: AppTheme.darkThemeData,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              return ColoredBox(
                color: context.colors.surface,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: _buildRoot(isDark),
          ),
        );
      },
    );
  }

  Widget _buildRoot(bool isDark) {
    if (_authState.loading) {
      return Scaffold(
        backgroundColor: isDark
            ? AppColorTokens.dark.surface
            : AppColorTokens.light.surface,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColorTokens.dark.accent,
          ),
        ),
      );
    }

    if (!_authState.isLoggedIn) {
      return _AuthGate(authState: _authState);
    }

    return AppShell(authState: _authState);
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.authState});
  final AuthState authState;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return LoginScreen(
        authState: widget.authState,
        onRegisterTap: () => setState(() => _showLogin = false),
      );
    }
    return RegisterScreen(
      authState: widget.authState,
      onLoginTap: () => setState(() => _showLogin = true),
    );
  }
}
