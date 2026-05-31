import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/spacing_tokens.dart';
import '../theme/typography_tokens.dart';

/// Stoic Analyst empty state. Replaces bare `Center(Text(...))` placeholders
/// across the app (dashboard "no matches this week", starting XI "no players
/// available", etc.) with a typographically anchored panel that gives the
/// committee a clear "this is intentional, the system is fine" cue rather
/// than the bare-text impression of a half-broken screen.
///
/// Renders three vertically stacked elements at the centre of the available
/// space:
///   - an optional icon at chrome-deep tone
///   - an all-caps headline at sectionLabel weight
///   - an optional body line at bodySmall
/// Sharp edges, no shadows, tonal layering only.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.headline,
    this.body,
    this.icon,
    super.key,
  });

  final String headline;
  final String? body;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 36, color: c.chromeDeep),
                const SizedBox(height: SpacingTokens.md),
              ],
              Text(
                headline.toUpperCase(),
                textAlign: TextAlign.center,
                style: TypographyTokens.sectionLabel.copyWith(
                  color: c.textPrimary,
                  fontSize: 12,
                  letterSpacing: 2.4,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: TypographyTokens.bodySmall.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
