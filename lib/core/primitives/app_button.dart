import 'package:flutter/material.dart';

import '../theme/glossy_widgets.dart';

/// Project-wide CTA. Both ``primary`` and ``secondary`` variants render
/// with the glossy gradient surface from ``GlossyButton``.
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
  /// toward the user's club colour.
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
