import 'package:flutter/material.dart';

import '../../../core/primitives/app_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../analytics/presentation/analytics_screen.dart';
import '../../chat/presentation/chat_screen.dart';

class MatchIntelligenceScreen extends StatelessWidget {
  const MatchIntelligenceScreen({
    required this.onTabSelected,
    this.onProfileTap,
    super.key,
  });

  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppScaffold(
      currentTab: AppTab.dashboard,
      onTabSelected: onTabSelected,
      onProfileTap: onProfileTap,
      body: ListView(
        children: [
          Text('MATCH INTELLIGENCE',
              style: TypographyTokens.sectionLabel
                  .copyWith(color: c.accent)),
          const SizedBox(height: SpacingTokens.xs),
          Text('VS. FCSB',
              style: TypographyTokens.displayHero.copyWith(fontSize: 58)),
          const SizedBox(height: SpacingTokens.xs),
          Text('OCT 24 • ARENA NATIONALA',
              style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.xl),
          Text('WIN PROBABILITY OPTIMIZATION',
              style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                child: _Box(label: 'BASELINE', value: '65%'),
              ),
              // Iteration N polish: 4 px gap between the two pods reads as a
              // genuine separator rather than a hairline overlap.
              const SizedBox(width: SpacingTokens.xxs),
              Expanded(
                child: _Box(
                  label: 'AI-OPTIMIZED',
                  value: '74%',
                  valueColor: c.accent,
                  footer: '+9.0% UPLIFT',
                  // Iteration N polish: visually anchor the AI pod with a
                  // surfaceHigh background and a left-edge cobalt accent rule
                  // so the baseline-vs-optimised contrast reads at a glance.
                  highlighted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('VICTORY CHANCE',
                  style: TypographyTokens.sectionLabel
                      .copyWith(color: c.accent)),
              Text('74%',
                  style: TypographyTokens.headline
                      .copyWith(color: c.accent)),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          Container(
            height: 6,
            color: c.surfaceLow,
            child: FractionallySizedBox(
              widthFactor: 0.74,
              alignment: Alignment.centerLeft,
              child: Container(color: c.accent),
            ),
          ),
          const SizedBox(height: SpacingTokens.xl),
          Text('TACTICAL BLUEPRINT', style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.sm),
          const _MetricGrid(),
          const SizedBox(height: SpacingTokens.lg),
          Container(
            color: c.surfaceLow,
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TACTICAL DIAGNOSIS',
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: c.accent)),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'The uplift is achieved by transitioning to a high-press 4-3-3 variant. Prioritize wide-area pressure to trigger wing-back fatigue.',
                  style: TypographyTokens.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          AppButton.primary(
            label: 'Generate Detailed Brief',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatScreen(onTabSelected: onTabSelected),
                ),
              );
            },
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppButton.secondary(
            label: 'Full AI Simulation',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AnalyticsScreen(onTabSelected: onTabSelected),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.label,
    required this.value,
    this.valueColor,
    this.footer,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? footer;

  /// When true the pod uses the tonally-elevated surfaceHigh background and
  /// gets a left-edge cobalt accent rule. Used on the AI-OPTIMIZED pod so
  /// the baseline-vs-optimised contrast reads at presentation distance.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effectiveValueColor = valueColor ?? c.textPrimary;
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? c.surfaceHigh : c.surface,
        border: highlighted
            ? Border(left: BorderSide(color: c.accent, width: 2))
            : null,
      ),
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.xs),
          Text(value,
              style: TypographyTokens.displayHero
                  .copyWith(fontSize: 58, color: effectiveValueColor)),
          if (footer != null) ...[
            const SizedBox(height: SpacingTokens.sm),
            // Iteration N polish: lift uplift footer to display-sm so it
            // reads from across the room during the demo presentation.
            Text(footer!,
                style: TypographyTokens.sectionLabel.copyWith(
                  color: c.accent,
                  fontSize: 13,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w900,
                )),
          ],
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget cell(String label, String value, {Color? color}) {
      final effectiveColor = color ?? c.textPrimary;
      return Container(
        color: c.surface,
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TypographyTokens.sectionLabel),
            const SizedBox(height: SpacingTokens.xs),
            Text(value,
                style: TypographyTokens.headline.copyWith(color: effectiveColor)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          Expanded(child: cell('POSSESSION', '58%')),
          const SizedBox(width: 1),
          Expanded(child: cell('SHOTS', '14'))
        ]),
        const SizedBox(height: 1),
        Row(children: [
          Expanded(child: cell('S.O.T.', '6')),
          const SizedBox(width: 1),
          Expanded(child: cell('CORNERS', '8'))
        ]),
        const SizedBox(height: 1),
        Row(
          children: [
            Expanded(child: cell('XG TARGET', '2.1')),
            const SizedBox(width: 1),
            Expanded(child: cell('XGA LIMIT', '0.4', color: c.negative)),
          ],
        ),
      ],
    );
  }
}
