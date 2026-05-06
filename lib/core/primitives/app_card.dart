import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/spacing_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(SpacingTokens.lg),
    this.backgroundColor,
    this.borderRadius = 6.0,
    this.showGlow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// If null, defaults to [AppColorTokens.surfaceHigh] of the current theme.
  final Color? backgroundColor;

  /// Corner radius. Defaults to 6 — matches the design system card radius.
  final double borderRadius;

  /// Whether to apply the gold ambient glow shadow. Defaults to true.
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = backgroundColor ?? c.surfaceHigh;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: c.divider),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: c.cardGlow,
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
