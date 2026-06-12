import 'package:flutter/material.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/shape_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';

/// The shared primary call-to-action for the auth screens. One accent, one
/// radius, one busy spinner, so login, register, and verify match.
class AuthButton extends StatelessWidget {
  const AuthButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 48,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          shape: const RoundedRectangleBorder(borderRadius: ShapeTokens.control),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.onAccent,
                ),
              )
            : Text(
                label,
                style: TypographyTokens.buttonLabel.copyWith(color: c.onAccent),
              ),
      ),
    );
  }
}
