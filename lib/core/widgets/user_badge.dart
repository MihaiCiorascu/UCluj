import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular profile button in the app bar. Deliberately quiet: a flat
/// surface-toned disc with a hairline border and a muted glyph, so it reads
/// as chrome on the dark header instead of a coloured, glowing token.
class UserBadge extends StatelessWidget {
  const UserBadge({
    this.icon = Icons.person_outline,
    this.size = 32,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(color: c.divider),
        ),
        child: Icon(icon, size: size * 0.5, color: c.textSecondary),
      ),
    );
  }
}
