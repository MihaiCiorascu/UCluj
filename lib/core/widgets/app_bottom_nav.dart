import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_colors.dart';
import '../theme/typography_tokens.dart';

enum AppTab { dashboard, standings, chat }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.current,
    required this.onSelected,
    super.key,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider, width: 1),
        ),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: current.index,
        onTap: (index) => onSelected(AppTab.values[index]),
        elevation: 0,
        backgroundColor: Colors.transparent,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textMuted,
        selectedLabelStyle: TypographyTokens.navLabel,
        unselectedLabelStyle: TypographyTokens.navLabel,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: L10n.t('nav.dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.leaderboard_outlined),
            activeIcon: const Icon(Icons.leaderboard),
            label: L10n.t('nav.standings'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble_outline),
            activeIcon: const Icon(Icons.chat_bubble),
            label: L10n.t('nav.chat'),
          ),
        ],
      ),
    );
  }
}
