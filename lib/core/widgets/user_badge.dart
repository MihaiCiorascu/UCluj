import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'team_accent_scope.dart';

/// Iteration N — circular avatar / profile badge that picks up the
/// per-team accent overlay.
///
/// The ring around the icon is painted with the user's team primary
/// colour; if no team is in scope the ring falls back to ``chrome``.
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
    final team = TeamAccentScope.of(context);
    final ring = team?.primaryColor ?? c.chrome;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: c.surfaceElevatedGradient,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 2),
          boxShadow: [
            BoxShadow(
              color: ring.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.5, color: c.primaryDeep),
      ),
    );
  }
}
