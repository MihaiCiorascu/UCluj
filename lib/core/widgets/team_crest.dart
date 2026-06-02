import 'package:flutter/material.dart';

import '../data/superliga_teams.dart';
import '../theme/app_colors.dart';

/// Club crest for any Romanian Superliga team name (short, display, Sportradar,
/// or CSV variant). Resolves the asset via [badgeAssetForName] and falls back
/// to a neutral shield outline when the name is unknown or the asset is
/// missing, so a team-versus-team surface never crashes or shows a gap.
class TeamCrest extends StatelessWidget {
  const TeamCrest({required this.teamName, this.size = 20, super.key});

  final String teamName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final asset = badgeAssetForName(teamName);
    if (asset == null) {
      return Icon(Icons.shield_outlined, size: size, color: c.textMuted);
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.shield_outlined, size: size, color: c.textMuted),
    );
  }
}
