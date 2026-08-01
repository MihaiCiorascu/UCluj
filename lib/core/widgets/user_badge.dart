import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular profile button in the app bar. Quiet chrome by default: a flat
/// surface-toned disc with a hairline border and a muted glyph, so it reads as
/// chrome on the dark header instead of a coloured, glowing token. When the
/// signed-in user has an avatar, it shows that photo (clipped to the disc) so
/// the header matches the Profile and Chat screens; it falls back to the glyph
/// while the image loads, on error, or when no avatar is set.
class UserBadge extends StatelessWidget {
  const UserBadge({
    this.icon = Icons.person_outline,
    this.size = 32,
    this.avatarUrl,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final double size;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    Widget glyph() => Icon(icon, size: size * 0.5, color: c.textSecondary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(color: c.divider),
        ),
        child: hasAvatar
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => glyph(),
                errorWidget: (_, __, ___) => glyph(),
              )
            : glyph(),
      ),
    );
  }
}
