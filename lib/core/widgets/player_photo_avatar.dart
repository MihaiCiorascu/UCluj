import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/typography_tokens.dart';

/// Square player headshot with a role-coloured ring, in the Stoic Analyst
/// language (sharp edges, no radius). Loads a self-hosted photo via
/// [CachedNetworkImage] and degrades to the player's initials on a tonal
/// surface whenever the URL is empty or the image fails to load, so the pitch
/// never shows a broken image or a gap.
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
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        border: Border.all(color: ringColor, width: (size * 0.07).clamp(2.0, 3.5)),
      ),
      child: ClipRect(child: inner),
    );
  }
}
