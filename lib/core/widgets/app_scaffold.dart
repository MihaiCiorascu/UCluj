import 'package:flutter/material.dart';

import '../branding/branding_config.dart';
import '../theme/app_colors.dart';
import '../theme/glossy_widgets.dart';
import '../theme/spacing_tokens.dart';
import 'app_bottom_nav.dart';
import 'team_accent_scope.dart';
import 'user_badge.dart';

/// Iteration N — application chrome rebuilt around UmbraRo branding +
/// the glossy app bar. The header now carries the UmbraRo logo, the
/// "UMBRARO / TACTICAL INTELLIGENCE" wordmark, and (when a team is in
/// scope) a thin per-team accent strip beneath the gloss bar.
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
    final accentColors = TeamAccentScope.colorsOf(context);
    return Scaffold(
      backgroundColor: c.surfaceBaseTop,
      body: Container(
        decoration: BoxDecoration(gradient: c.surfaceBaseGradient),
        child: SafeArea(
          child: Column(
            children: [
              GlossyAppBar(
                accentColors: accentColors.isEmpty ? null : accentColors,
                leading: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        BrandingConfig.logoIcon,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          BrandingConfig.appName.toUpperCase(),
                          style: TextStyle(
                            color: c.onPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            height: 1.0,
                            letterSpacing: 2.0,
                          ),
                        ),
                        Text(
                          BrandingConfig.tagline.toUpperCase(),
                          style: TextStyle(
                            color: c.onPrimary.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                            fontSize: 8,
                            height: 1.2,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: trailing ??
                    UserBadge(onTap: onProfileTap),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.xl,
                    SpacingTokens.xl,
                    SpacingTokens.xl,
                    SpacingTokens.md,
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        current: currentTab,
        onSelected: onTabSelected,
      ),
    );
  }
}
