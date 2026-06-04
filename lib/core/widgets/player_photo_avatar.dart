import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/typography_tokens.dart';

/// Rounded player headshot with a thin role-coloured ring. Loads a self-hosted
/// photo via [CachedNetworkImage] and degrades to the player's initials on a
/// tonal surface whenever the URL is empty or the image fails to load, so the
/// pitch never shows a broken image or a gap. The ring is deliberately subtle
/// (a hairline, not a heavy frame); callers overlay rating/position themselves.
class PlayerPhotoAvatar extends StatelessWidget {
  const PlayerPhotoAvatar({
    required this.photoUrl,
    required this.name,
    required this.ringColor,
    this.size = 40,
    super.key,
  });

  final String photoUrl;
  final String name;
  final Color ringColor;
  final double size;

  String get _initials {
    final tokens = name
        .replaceAll('.', ' ')
        .split(' ')
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '?';
    if (tokens.length == 1) {
      final t = tokens.first;
      return (t.length >= 2 ? t.substring(0, 2) : t).toUpperCase();
    }
    return (tokens.first[0] + tokens.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget initialsBox() => Container(
          alignment: Alignment.center,
          color: c.surfaceHigh,
          child: Text(
            _initials,
            style: TypographyTokens.sectionLabel.copyWith(
              color: c.textPrimary,
              fontSize: size * 0.34,
              letterSpacing: 0.5,
            ),
          ),
        );

    final Widget inner = photoUrl.isEmpty
        ? initialsBox()
        : CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            width: size,
            height: size,
            placeholder: (_, __) => initialsBox(),
            errorWidget: (_, __, ___) => initialsBox(),
          );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(
          color: ringColor.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: inner,
    );
  }
}
