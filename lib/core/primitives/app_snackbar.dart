import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/shape_tokens.dart';
import '../theme/typography_tokens.dart';

/// Brief, floating confirmations (message sent, avatar updated) and errors.
/// One at a time (clears the queue first) so feedback never stacks. The
/// underlying [SnackBar] announces itself to screen readers automatically.
class AppSnackbar {
  const AppSnackbar._();

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    bool isError = false,
  }) {
    final c = context.colors;
    final tone = isError ? c.negative : c.primary;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: c.surfaceHigh,
          elevation: 0,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: ShapeTokens.control,
            side: BorderSide(color: c.divider),
          ),
          content: Row(
            children: [
              Icon(icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline),
                  size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TypographyTokens.bodySmall.copyWith(
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, icon: Icons.check_circle_outline);

  static void error(BuildContext context, String message) =>
      show(context, message, isError: true);
}
