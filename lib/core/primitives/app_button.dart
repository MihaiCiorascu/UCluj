import 'package:flutter/material.dart';

import '../theme/glossy_widgets.dart';

/// Iteration N — ``AppButton`` is the project-wide CTA. Both ``primary``
/// and ``secondary`` variants now render with the glossy gradient surface
/// from ``GlossyButton``. The public API (named constructors, ``label``,
/// ``onPressed``) is preserved so consumers are not touched.
class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.label,
    this.onPressed,
    this.accentBias,
    super.key,
  }) : isPrimary = true;

  const AppButton.secondary({
    required this.label,
    this.onPressed,
    this.accentBias,
    super.key,
  }) : isPrimary = false;

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  /// Optional per-team accent — biases the top sheen of primary buttons
  /// toward the user's club colour. Iteration N.8.
  final Color? accentBias;

  @override
  Widget build(BuildContext context) {
    return GlossyButton(
      label: label,
      onPressed: onPressed,
      isPrimary: isPrimary,
      accentBias: accentBias,
    );
  }
}
