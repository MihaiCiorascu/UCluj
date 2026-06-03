import 'package:flutter/material.dart';

/// Typography scale for UmbraRo.
///
/// Two families, one job each: **Epilogue** for display and headings
/// (editorial, confident) and **Inter** for body, labels, and data (clean and
/// legible at small sizes). Both are bundled as variable fonts under
/// `assets/fonts/` (declared in pubspec) so they render offline with no runtime
/// network fetch. Every numeric style enables tabular figures so scores,
/// percentages, and table columns align and never reflow as digits change.
/// Colours are applied at the call site via `context.colors`.
class TypographyTokens {
  const TypographyTokens._();

  static const String _display = 'Epilogue';
  static const String _body = 'Inter';
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  // ── Display / headings (Epilogue) ──────────────────────────────────────────
  static const TextStyle displayHero = TextStyle(
    fontFamily: _display,
    fontSize: 46,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _display,
    fontSize: 26,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// Section / sheet title.
  static const TextStyle title = TextStyle(
    fontFamily: _display,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  // ── Content (Inter) ─────────────────────────────────────────────────────────

  /// Card / panel title — team names, match headings.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: _body,
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
  );

  /// Standard body text.
  static const TextStyle body = TextStyle(
    fontFamily: _body,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Supporting body text — secondary stats, captions.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _body,
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  // ── Labels & meta (Inter) ────────────────────────────────────────────────────

  /// True section dividers only: "U CLUJ — THIS WEEK".
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: _body,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// Compact metadata — dates, venues (tabular so dates align).
  static const TextStyle meta = TextStyle(
    fontFamily: _body,
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    fontFeatures: _tabular,
  );

  /// Bottom nav labels.
  static const TextStyle navLabel = TextStyle(
    fontFamily: _body,
    fontSize: 10.5,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// Button / segment labels (sentence or title case, not shouty).
  static const TextStyle buttonLabel = TextStyle(
    fontFamily: _body,
    fontSize: 13,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  // ── Numeric / data (Inter, tabular) ──────────────────────────────────────────

  /// Numeric stats — scores, percentages in cards.
  static const TextStyle statValue = TextStyle(
    fontFamily: _body,
    fontSize: 24,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: _tabular,
  );

  /// Hero numbers — the win-probability percentage, big single figures.
  static const TextStyle statLarge = TextStyle(
    fontFamily: _body,
    fontSize: 40,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    fontFeatures: _tabular,
  );

  /// Inline data figures — table cells, deltas.
  static const TextStyle mono = TextStyle(
    fontFamily: _body,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );
}
