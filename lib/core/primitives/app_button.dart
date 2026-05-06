import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/spacing_tokens.dart';
import '../theme/typography_tokens.dart';

class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.label,
    this.onPressed,
    super.key,
  }) : isPrimary = true;

  const AppButton.secondary({
    required this.label,
    this.onPressed,
    super.key,
  }) : isPrimary = false;

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = isPrimary ? c.onAccent : c.accent;
    final bg = isPrimary ? c.accent : Colors.transparent;
    final isDisabled = onPressed == null;

    return SizedBox(
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
          backgroundColor: isDisabled
              ? (isPrimary ? c.accent.withValues(alpha: 0.4) : Colors.transparent)
              : bg,
          foregroundColor: isDisabled ? fg.withValues(alpha: 0.4) : fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: isPrimary
              ? BorderSide.none
              : BorderSide(
                  color: isDisabled
                      ? c.divider.withValues(alpha: 0.4)
                      : c.divider,
                ),
        ),
        onPressed: onPressed,
        child: Text(
          label.toUpperCase(),
          style: TypographyTokens.buttonLabel.copyWith(color: isDisabled ? fg.withValues(alpha: 0.4) : fg),
        ),
      ),
    );
  }
}
