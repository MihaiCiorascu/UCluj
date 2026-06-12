import 'package:flutter/material.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/shape_tokens.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';

/// Form-level / server error surface (e.g. "email already registered", a
/// network failure, a wrong verification code). Per-field validation errors
/// render inline inside [AuthTextField] instead.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.sm),
      decoration: BoxDecoration(
        color: c.negative.withValues(alpha: 0.12),
        borderRadius: ShapeTokens.control,
        border: Border.all(color: c.negative.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: c.negative),
          const SizedBox(width: SpacingTokens.xs),
          Expanded(
            child: Text(
              message,
              style: TypographyTokens.bodySmall.copyWith(color: c.negative),
            ),
          ),
        ],
      ),
    );
  }
}
