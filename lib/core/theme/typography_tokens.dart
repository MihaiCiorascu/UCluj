import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale for UmbraRo.
///
/// Two families, one job each: **Epilogue** for display and headings
/// (editorial, confident) and **Inter** for body, labels, and data (clean and
/// legible at small sizes). Every numeric style enables tabular figures so
/// scores, percentages, and table columns align and never reflow as digits
/// change. Colours are applied at the call site via `context.colors` so styles
/// respond to the active theme.
///
/// Styles are `static final` (not `const`) because the Google Fonts loader
/// resolves them lazily on first use; no call site uses them in a const
/// context, so this is API-compatible with the previous const tokens.
class TypographyTokens {
  const TypographyTokens._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  // ── Display / headings (Epilogue) ──────────────────────────────────────────
  static final TextStyle displayHero = GoogleFonts.epilogue(
    fontSize: 46,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
  );

  static final TextStyle headline = GoogleFonts.epilogue(
    fontSize: 26,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// Section / sheet title.
  static final TextStyle title = GoogleFonts.epilogue(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  // ── Content (Inter) ─────────────────────────────────────────────────────────

  /// Card / panel title — team names, match headings.
  static final TextStyle cardTitle = GoogleFonts.inter(
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
  );

  /// Standard body text.
  static final TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Supporting body text — secondary stats, captions.
  static final TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  // ── Labels & meta (Inter) ────────────────────────────────────────────────────

  /// True section dividers only: "U CLUJ — THIS WEEK".
  static final TextStyle sectionLabel = GoogleFonts.inter(
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// Compact metadata — dates, venues (tabular so dates align).
  static final TextStyle meta = GoogleFonts.inter(
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    fontFeatures: _tabular,
  );

  /// Bottom nav labels.
  static final TextStyle navLabel = GoogleFonts.inter(
    fontSize: 10.5,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// Button / segment labels (sentence or title case, not shouty).
  static final TextStyle buttonLabel = GoogleFonts.inter(
    fontSize: 13,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  // ── Numeric / data (Inter, tabular) ──────────────────────────────────────────

  /// Numeric stats — scores, percentages in cards.
  static final TextStyle statValue = GoogleFonts.inter(
    fontSize: 24,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: _tabular,
  );

  /// Hero numbers — the win-probability percentage, big single figures.
  static final TextStyle statLarge = GoogleFonts.inter(
    fontSize: 40,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    fontFeatures: _tabular,
  );

  /// Inline data figures — table cells, deltas.
  static final TextStyle mono = GoogleFonts.inter(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );
}
