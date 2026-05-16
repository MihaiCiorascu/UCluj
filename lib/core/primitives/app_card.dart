import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/glossy_widgets.dart';
import '../theme/spacing_tokens.dart';

/// Iteration N — ``AppCard`` is the project-wide stat / info container.
/// It now renders as a ``GlossyCard`` (gradient surface, chrome border,
/// soft drop-shadow). The public API (`child`, `padding`, optional
/// `backgroundColor`) is preserved so the eleven screens consuming it
/// pick up the new aesthetic without per-call-site edits.
///
/// If a caller passes ``backgroundColor`` explicitly, we honour it as a
/// flat solid (used in rare cases where the glossy gradient looks wrong,
/// e.g. inside a chart legend); otherwise we render the glossy panel.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(SpacingTokens.lg),
    this.backgroundColor,
    this.radius = 10,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (backgroundColor != null) {
      final c = context.colors;
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: c.chrome, width: 0.6),
        ),
        child: child,
      );
    }
    return GlossyCard(
      padding: padding,
      radius: radius,
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
