import 'package:flutter/material.dart';

/// Theme-aware colour palette — Iteration N glossy + Iteration L+ scope merge.
///
/// The class structure is preserved from the earlier dark-theme migration
/// (constructor-based ``AppColorTokens`` distributed via the
/// ``AppColorsScope`` InheritedWidget) so the existing screens that read
/// ``c.textSecondary`` / ``c.cardGlow`` / ``c.negativeSubtle`` keep
/// compiling. The colour *values* and the additional glossy fields
/// (``primary``, ``primaryDeep``, ``chrome``, ``glow``, ``surface*Top/Bottom``,
/// gradient helpers) come from Iteration N — they replace the U Cluj gold
/// with the early-2000s sports-broadcast cobalt blue and expose the
/// gradient surfaces the glossy widgets consume.
class AppColorTokens {
  const AppColorTokens({
    // ── Surfaces (flat aliases for legacy call sites) ────────────────────
    required this.surface,
    required this.surfaceLow,
    required this.surfaceHigh,
    // ── Iteration N gradient endpoints ───────────────────────────────────
    required this.surfaceBaseTop,
    required this.surfaceBaseBottom,
    required this.surfaceElevatedTop,
    required this.surfaceElevatedBottom,
    // ── Primary / on-primary (legacy "accent" aliases follow) ─────────────
    required this.primary,
    required this.primaryDeep,
    required this.primaryGloss,
    required this.onPrimary,
    // ── Legacy gold-era aliases ──────────────────────────────────────────
    required this.accent,
    required this.accentStrong,
    required this.onAccent,
    required this.accentBlue,
    // ── Chrome + glow (Iteration N glossy primitives) ────────────────────
    required this.chrome,
    required this.chromeDeep,
    required this.glow,
    // ── Text ─────────────────────────────────────────────────────────────
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    // ── Status ───────────────────────────────────────────────────────────
    required this.negative,
    required this.negativeSubtle,
    required this.positive,
    required this.positiveSubtle,
    // ── Player-role family (cobalt pitch redesign) ───────────────────────
    // Four visually distinct tones for the GK / DEF / MID / FWD badges so
    // the two pitch widgets (Match Preview + Match Stats) agree, and so
    // no role collides with the cobalt CTA accent.
    required this.roleGoalkeeper,
    required this.roleDefender,
    required this.roleMidfielder,
    required this.roleForward,
    // ── Pitch surface, lines, halo ───────────────────────────────────────
    // Used by FifaPitchPainter. Replaces the hardcoded olive-green so the
    // pitch sits inside the Stoic Analyst layout instead of next to it.
    required this.pitchSurface,
    required this.pitchLine,
    required this.pitchHalo,
    // ── Iteration H legacy ───────────────────────────────────────────────
    required this.cardGlow,
    required this.brightness,
  });

  final Color surface;
  final Color surfaceLow;
  final Color surfaceHigh;

  final Color surfaceBaseTop;
  final Color surfaceBaseBottom;
  final Color surfaceElevatedTop;
  final Color surfaceElevatedBottom;

  final Color primary;
  final Color primaryDeep;
  final Color primaryGloss;
  final Color onPrimary;

  final Color accent;
  final Color accentStrong;
  final Color onAccent;
  final Color accentBlue;

  final Color chrome;
  final Color chromeDeep;
  final Color glow;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;

  final Color negative;
  final Color negativeSubtle;
  final Color positive;
  final Color positiveSubtle;

  final Color roleGoalkeeper;
  final Color roleDefender;
  final Color roleMidfielder;
  final Color roleForward;

  final Color pitchSurface;
  final Color pitchLine;
  final Color pitchHalo;

  final Color cardGlow;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  // ── Iteration N gradient helpers ─────────────────────────────────────────
  LinearGradient get surfaceBaseGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [surfaceBaseTop, surfaceBaseBottom],
      );

  LinearGradient get surfaceElevatedGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [surfaceElevatedTop, surfaceElevatedBottom],
      );

  LinearGradient primaryGlossGradient([double sheen = 1.0]) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.5, 1.0],
        colors: [
          Color.alphaBlend(
              primaryGloss.withValues(alpha: 0.7 * sheen), primary),
          primary,
          primaryDeep,
        ],
      );

  // ── Light palette (Iteration N — cobalt blue + chrome + pale-blue base) ─
  static const AppColorTokens light = AppColorTokens(
    surface:              Color(0xFFEBF3FF),
    surfaceLow:           Color(0xFFF4F8FE),
    surfaceHigh:          Color(0xFFE6EFFB),
    surfaceBaseTop:       Color(0xFFEBF3FF),
    surfaceBaseBottom:    Color(0xFFC7DDF5),
    surfaceElevatedTop:   Color(0xFFFFFFFF),
    surfaceElevatedBottom:Color(0xFFDCE8F8),
    primary:              Color(0xFF0047AB),
    primaryDeep:          Color(0xFF003D99),
    primaryGloss:         Color(0x66FFFFFF),
    onPrimary:            Color(0xFFFFFFFF),
    accent:               Color(0xFF0047AB),
    accentStrong:         Color(0xFF003D99),
    onAccent:             Color(0xFFFFFFFF),
    // accentBlue is now a distinct steel-blue so the legacy aliases stop
    // colliding with `accent`. Most call sites that wanted "the DEF role
    // colour" should migrate to `roleDefender` (same value, clearer intent).
    accentBlue:           Color(0xFF1A4F7A),
    chrome:               Color(0xFFC0CCDA),
    chromeDeep:           Color(0xFF8A98A8),
    glow:                 Color(0xFF42A5F5),
    textPrimary:          Color(0xFF0A1929),
    textSecondary:        Color(0xFF1F3147),
    textMuted:            Color(0xFF5A6B7C),
    divider:              Color(0x22000000),
    negative:             Color(0xFFC62828),
    negativeSubtle:       Color(0x1AC62828),
    positive:             Color(0xFF2E7D32),
    positiveSubtle:       Color(0x1A2E7D32),
    // Player roles ── warm amber for GK, steel for DEF, green for MID, red
    // for FWD. Each pair distinct in hue + lightness so the eye separates
    // them at thumb distance.
    roleGoalkeeper:       Color(0xFFB47B00),
    roleDefender:         Color(0xFF1A4F7A),
    roleMidfielder:       Color(0xFF2E7D32),
    roleForward:          Color(0xFFC62828),
    // Pitch surface stays deep navy across both themes so the pitch reads
    // as a single product element regardless of the page palette.
    pitchSurface:         Color(0xFF0A1929),
    pitchLine:            Color(0xB3FFFFFF),
    pitchHalo:            Color(0x141E88E5),
    cardGlow:             Color(0x080047AB),
    brightness:           Brightness.light,
  );

  // ── Dark palette (Iteration N — deep navy + brighter cobalt) ────────────
  static const AppColorTokens dark = AppColorTokens(
    surface:              Color(0xFF0A1929),
    surfaceLow:           Color(0xFF0F1B2D),
    surfaceHigh:          Color(0xFF1A2942),
    surfaceBaseTop:       Color(0xFF0A1929),
    surfaceBaseBottom:    Color(0xFF050D17),
    surfaceElevatedTop:   Color(0xFF1A2942),
    surfaceElevatedBottom:Color(0xFF0F1A2D),
    primary:              Color(0xFF1E88E5),
    primaryDeep:          Color(0xFF0D47A1),
    primaryGloss:         Color(0x55FFFFFF),
    onPrimary:            Color(0xFFFFFFFF),
    accent:               Color(0xFF1E88E5),
    accentStrong:         Color(0xFF0D47A1),
    onAccent:             Color(0xFFFFFFFF),
    // Distinct steel-blue, see comment on the light palette.
    accentBlue:           Color(0xFF5B8DBE),
    chrome:               Color(0xFF5B6A7F),
    chromeDeep:           Color(0xFF2C3645),
    glow:                 Color(0xFF64B5F6),
    textPrimary:          Color(0xFFF2F6FB),
    textSecondary:        Color(0xFFB8C5D6),
    textMuted:            Color(0xFF9FB0C0),
    divider:              Color(0x33FFFFFF),
    negative:             Color(0xFFFF5252),
    negativeSubtle:       Color(0x1AFF5252),
    positive:             Color(0xFF4ADE80),
    positiveSubtle:       Color(0x1A4ADE80),
    // Player roles ── warm amber for GK, steel for DEF, bright green for
    // MID, bright red for FWD. Lifted vs the light theme so they read on
    // the deep navy surface.
    roleGoalkeeper:       Color(0xFFF2C94C),
    roleDefender:         Color(0xFF5B8DBE),
    roleMidfielder:       Color(0xFF4ADE80),
    roleForward:          Color(0xFFFF5252),
    pitchSurface:         Color(0xFF0A1929),
    pitchLine:            Color(0x99FFFFFF),
    pitchHalo:            Color(0x141E88E5),
    cardGlow:             Color(0x141E88E5),
    brightness:           Brightness.dark,
  );

  static AppColorTokens fromBrightness(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

// ── InheritedWidget (preserved from umbraro for back-compat) ────────────────

class _AppColorsScope extends InheritedWidget {
  const _AppColorsScope({required this.colors, required super.child});
  final AppColorTokens colors;

  @override
  bool updateShouldNotify(_AppColorsScope old) => colors != old.colors;
}

class AppColorsScope extends StatelessWidget {
  const AppColorsScope({
    super.key,
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AppColorsScope(
      colors: isDark ? AppColorTokens.dark : AppColorTokens.light,
      child: child,
    );
  }
}

extension AppColorsX on BuildContext {
  /// Returns the active palette: prefers an enclosing ``AppColorsScope`` and
  /// falls back to ``Theme.of(context).brightness`` so widgets work even if
  /// the scope isn't present (e.g. inside isolated tests).
  AppColorTokens get colors {
    final scoped =
        dependOnInheritedWidgetOfExactType<_AppColorsScope>()?.colors;
    if (scoped != null) return scoped;
    return AppColorTokens.fromBrightness(Theme.of(this).brightness);
  }
}
