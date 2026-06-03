import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shape + elevation tokens for the redesign.
///
/// A single, calm radius vocabulary (cards 10, controls 10, sheets 18, chips
/// full) and one soft, brand-tinted elevation scale (`e1` cards, `e2` raised /
/// pressed, `e3` sheets) so depth reads consistently instead of the one-off
/// shadows scattered across the old screens.
class ShapeTokens {
  const ShapeTokens._();

  static const double radiusChip = 999;
  static const double radiusControl = 10;
  static const double radiusCard = 10;
  static const double radiusSheet = 18;

  static const BorderRadius card =
      BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius control =
      BorderRadius.all(Radius.circular(radiusControl));
  static const BorderRadius chip =
      BorderRadius.all(Radius.circular(radiusChip));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(radiusSheet));

  /// Resting card elevation.
  static List<BoxShadow> e1(BuildContext context) {
    final c = context.colors;
    return [
      BoxShadow(
        color: c.shadowBase.withValues(alpha: c.isDark ? 0.45 : 0.14),
        blurRadius: 16,
        spreadRadius: -4,
        offset: const Offset(0, 6),
      ),
    ];
  }

  /// Raised / pressed elevation.
  static List<BoxShadow> e2(BuildContext context) {
    final c = context.colors;
    return [
      BoxShadow(
        color: c.shadowBase.withValues(alpha: c.isDark ? 0.55 : 0.20),
        blurRadius: 24,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ];
  }

  /// Sheet elevation — lifts upward off the page.
  static List<BoxShadow> e3(BuildContext context) {
    final c = context.colors;
    return [
      BoxShadow(
        color: c.shadowBase.withValues(alpha: c.isDark ? 0.60 : 0.26),
        blurRadius: 32,
        spreadRadius: -2,
        offset: const Offset(0, -8),
      ),
    ];
  }
}
