import 'package:flutter/material.dart';

import '../branding/branding_config.dart';
import '../l10n/strings.dart';
import '../state/meta_state.dart';
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DemoModeRibbon(),
          AppBottomNav(
            current: currentTab,
            onSelected: onTabSelected,
          ),
        ],
      ),
    );
  }
}

/// Thin single-line ribbon above the bottom nav that signals demo mode to the
/// committee. Reads from the global MetaState singleton and rebuilds whenever
/// the /meta fetch lands. Renders nothing when demo mode is off, so it has
/// zero footprint in production.
class _DemoModeRibbon extends StatelessWidget {
  const _DemoModeRibbon();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([MetaState.instance, L10n.instance]),
      builder: (context, _) {
        if (!MetaState.instance.demoMode) {
          return const SizedBox.shrink();
        }
        final formatted = _formatDemoDate(
          MetaState.instance.demoToday,
          L10n.instance.isRomanian,
        );
        return Container(
          width: double.infinity,
          color: c.chromeDeep,
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.xs,
          ),
          child: Text(
            '${L10n.t('demoMode.label')}  ·  ${L10n.t('demoMode.fixturesFrom')} $formatted',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onPrimary.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        );
      },
    );
  }
}

/// Format an ISO `YYYY-MM-DD` string as `15 April 2025` (English) or
/// `15 aprilie 2025` (Romanian). Returns the input verbatim on parse failure
/// so the ribbon still renders something rather than nothing.
String _formatDemoDate(String iso, bool isRomanian) {
  try {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    const ro = [
      '', 'ianuarie', 'februarie', 'martie', 'aprilie', 'mai', 'iunie',
      'iulie', 'august', 'septembrie', 'octombrie', 'noiembrie', 'decembrie',
    ];
    const en = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final names = isRomanian ? ro : en;
    if (month < 1 || month > 12) return iso;
    return '$day ${names[month]} $year';
  } catch (_) {
    return iso;
  }
}
