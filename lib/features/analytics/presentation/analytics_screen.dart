import 'package:flutter/material.dart';

import '../../../core/primitives/app_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../team/presentation/team_screen.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
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
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          border: Border.all(color: c.divider),
        ),
        child: Icon(Icons.person_outline,
            size: 16, color: c.textPrimary),
      ),
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            color: c.surface,
            padding: const EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WIN PROBABILITY SCORE',
                    style: TypographyTokens.sectionLabel),
                const SizedBox(height: SpacingTokens.xs),
                Text('78.4%',
                    style: TypographyTokens.displayHero.copyWith(fontSize: 82)),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: SpacingTokens.lg),
          Text('TACTICAL FORM',
              style: TypographyTokens.headline.copyWith(fontSize: 42)),
          const SizedBox(height: SpacingTokens.sm),
          const _MetricLine(label: 'SHOTS', value: '18.4'),
          const _MetricLine(label: 'ON TARGET', value: '6.2'),
          const _MetricLine(label: 'POSSESSION', value: '58%'),
          const SizedBox(height: SpacingTokens.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACTIVE RECOMMENDATION',
                    style: TypographyTokens.sectionLabel),
                const SizedBox(height: SpacingTokens.sm),
                Text('HIGH-BLOCK TRANSITION',
                    style: TypographyTokens.body
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'Shift to 4-3-3 pressing structure at 60. Opposition recovery times are lagging 1.2s behind baseline.',
                  style: TypographyTokens.body,
                ),
                const SizedBox(height: SpacingTokens.md),
                Container(
                  color: c.textPrimary,
                  padding:
                      const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TeamScreen(onTabSelected: onTabSelected),
                        ),
                      );
                    },
                    child: Center(
                      child: Text(
                        'EXECUTE SIMULATION',
                        style: TypographyTokens.sectionLabel
                            .copyWith(color: c.surface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          const Row(
            children: [
              Expanded(child: _MetricLine(label: 'XG DELTA', value: '+0.42')),
              SizedBox(width: SpacingTokens.sm),
              Expanded(child: _MetricLine(label: 'PASS CHAIN', value: '8.4')),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          const Row(
            children: [
              Expanded(child: _MetricLine(label: 'VERT. INDEX', value: '0.72')),
              SizedBox(width: SpacingTokens.sm),
              Expanded(child: _MetricLine(label: 'REC. PHASE', value: '4.2s')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TypographyTokens.sectionLabel),
          Text(
            value,
            style: TypographyTokens.body.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
