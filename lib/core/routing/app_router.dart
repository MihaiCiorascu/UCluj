import 'package:flutter/material.dart';

import '../../core/state/auth_state.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/standings/presentation/standings_screen.dart';
import '../theme/theme_mode_notifier.dart';
import '../widgets/app_bottom_nav.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.authState, required this.themeMode, super.key});

  final AuthState authState;
  final ThemeModeNotifier themeMode;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _currentTab = AppTab.dashboard;

  void _onTabSelected(AppTab tab) {
    if (_currentTab == tab) return;
    setState(() => _currentTab = tab);
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          authState: widget.authState,
          themeMode: widget.themeMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentTab) {
      case AppTab.dashboard:
        return DashboardScreen(
          authState: widget.authState,
          onTabSelected: _onTabSelected,
          onProfileTap: _openProfile,
        );
      case AppTab.standings:
        return StandingsScreen(
          onTabSelected: _onTabSelected,
          onProfileTap: _openProfile,
          trackedTeam: widget.authState.user?.teamName,
          apiClient: widget.authState.api,
        );
      case AppTab.chat:
        return ChatScreen(
          onTabSelected: _onTabSelected,
          onProfileTap: _openProfile,
          authState: widget.authState,
        );
    }
  }
}
