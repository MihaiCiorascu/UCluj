import 'package:flutter/material.dart';

import '../../../core/primitives/app_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../match_intelligence/presentation/match_intelligence_screen.dart';
import 'starting_xi_screen.dart';

class TeamScreen extends StatelessWidget {
  const TeamScreen({
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
          Text('SEASON STATUS', style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.sm),
          Text('RANK #3',
              style: TypographyTokens.displayHero.copyWith(fontSize: 76)),
          const SizedBox(height: SpacingTokens.sm),
          Text('46 PTS', style: TypographyTokens.headline),
          const SizedBox(height: SpacingTokens.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PERFORMANCE SUMMARY',
                    style: TypographyTokens.sectionLabel),
                SizedBox(height: SpacingTokens.sm),
                Text('WIN RATE 68%   GOALS/MATCH 2.41',
                    style: TypographyTokens.body),
                SizedBox(height: SpacingTokens.xs),
                Text('CLEAN SHEETS 12   TOP-4 RATE 54%',
                    style: TypographyTokens.body),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SQUAD LOAD MONITORING',
                    style: TypographyTokens.sectionLabel),
                SizedBox(height: SpacingTokens.sm),
                Text('HENDERSON   OPTIMAL', style: TypographyTokens.body),
                SizedBox(height: SpacingTokens.xs),
                Text('RASHFORD   ROTATION', style: TypographyTokens.body),
                SizedBox(height: SpacingTokens.xs),
                Text('FERNANDES   CAUTION', style: TypographyTokens.body),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Container(
            color: c.surfaceLow,
            width: double.infinity,
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECENT FORM', style: TypographyTokens.sectionLabel),
                const SizedBox(height: SpacingTokens.sm),
                const Row(
                  children: [
                    _FormBox('W'),
                    SizedBox(width: SpacingTokens.xs),
                    _FormBox('W'),
                    SizedBox(width: SpacingTokens.xs),
                    _FormBox('D'),
                    SizedBox(width: SpacingTokens.xs),
                    _FormBox('L'),
                    SizedBox(width: SpacingTokens.xs),
                    _FormBox('W'),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text('NEXT OPPONENT  LIVERPOOL FC (H)',
                    style: TypographyTokens.body),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          Container(
            color: c.accent,
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TACTICAL ALERT: MATCH PLAN DEVIATION',
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: c.onAccent,
                  ),
                ),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'Midfield defensive transition lags 1.4s behind opposition average.',
                  style: TypographyTokens.body.copyWith(color: c.onAccent),
                ),
                const SizedBox(height: SpacingTokens.sm),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MatchIntelligenceScreen(
                          onTabSelected: onTabSelected,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    color: c.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.md,
                      vertical: SpacingTokens.sm,
                    ),
                    child: Text(
                      'OPEN MATCH PLAN',
                      style: TypographyTokens.sectionLabel.copyWith(
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StartingXiScreen(
                    onTabSelected: onTabSelected,
                  ),
                ),
              );
            },
            child: Container(
              color: c.surface,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
                vertical: SpacingTokens.lg,
              ),
              child: Text(
                'AI STARTING XI GENERATOR',
                style: TypographyTokens.sectionLabel.copyWith(
                  color: c.accent,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormBox extends StatelessWidget {
  const _FormBox(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 28,
      height: 24,
      color: label == 'L' ? c.negative : c.accent,
      alignment: Alignment.center,
      child: Text(
        label,
        style: TypographyTokens.sectionLabel.copyWith(
          color: c.surface,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
