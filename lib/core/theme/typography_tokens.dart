import 'package:flutter/material.dart';

/// Typography scale for UHack.
///
/// Colors are intentionally omitted here — apply via [context.colors] at the
/// call site so they respond correctly to theme changes.
class TypographyTokens {
  const TypographyTokens._();

  // ── Display ────────────────────────────────────────────────────────────────
  static const TextStyle displayHero = TextStyle(
    fontSize: 52,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.5,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  // ── Content ────────────────────────────────────────────────────────────────

  /// Card / panel title — team names, match headings
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  /// Standard body text
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Supporting body text — odds, secondary stats
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  // ── Labels & meta ──────────────────────────────────────────────────────────

  /// ALL-CAPS section dividers: "U CLUJ — THIS WEEK"
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
  );

  /// Numeric stats — scores, percentages (monospace-feel)
  static const TextStyle statValue = TextStyle(
    fontSize: 24,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// Compact metadata — dates, venues, match IDs
  static const TextStyle meta = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  /// Bottom nav labels
  static const TextStyle navLabel = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  // ── Buttons ────────────────────────────────────────────────────────────────

  /// Primary button label
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 12,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );
}
