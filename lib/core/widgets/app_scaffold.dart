import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_notifier.dart';
import '../theme/spacing_tokens.dart';
import 'app_bottom_nav.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.currentTab,
    required this.body,
    required this.onTabSelected,
    this.onProfileTap,
    this.trailing,
    super.key,
  });

  final AppTab currentTab;
  final Widget body;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback? onProfileTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = ThemeNotifier.instance.isDark;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md,
                SpacingTokens.sm,
                SpacingTokens.md,
                SpacingTokens.xs,
              ),
              child: Row(
                children: [
                  // Club crest
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: Image.asset(
                      'assets/teams/universitatea_cluj.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  // Brand wordmark
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'U CLUJ',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          height: 1.0,
                          letterSpacing: 2.0,
                          color: c.accent,
                        ),
                      ),
                      Text(
                        'TACTICAL INTELLIGENCE',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 7,
                          height: 1.2,
                          letterSpacing: 2.5,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Theme toggle
                  _HeaderIconButton(
                    onTap: ThemeNotifier.instance.toggle,
                    icon: isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    iconColor: c.accent,
                    c: c,
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  // Profile
                  trailing ??
                      _HeaderIconButton(
                        onTap: onProfileTap,
                        icon: Icons.person_outline,
                        iconColor: c.textPrimary,
                        c: c,
                      ),
                ],
              ),
            ),
            // Gold accent rule
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.accent, c.accentStrong, const Color(0x00000000)],
                ),
              ),
            ),
            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md,
                  SpacingTokens.md,
                  SpacingTokens.md,
                  SpacingTokens.xs,
                ),
                child: body,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: currentTab,
        onSelected: onTabSelected,
      ),
    );
  }
}

/// Compact 32×32 icon button for the scaffold header.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.iconColor,
    required this.c,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final AppColorTokens c;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          border: Border.all(color: c.divider),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 15, color: iconColor),
      ),
    );
  }
}
