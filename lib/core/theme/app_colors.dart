import 'package:flutter/material.dart';

/// Theme-aware color palette.
/// Access via [BuildContext.colors] inside any widget build method.
class AppColorTokens {
  const AppColorTokens({
    required this.surface,
    required this.surfaceLow,
    required this.surfaceHigh,
    required this.accent,
    required this.accentStrong,
    required this.onAccent,
    required this.accentBlue,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.negative,
    required this.negativeSubtle,
    required this.positive,
    required this.positiveSubtle,
    required this.cardGlow,
  });

  final Color surface;
  final Color surfaceLow;
  final Color surfaceHigh;
  final Color accent;
  final Color accentStrong;
  final Color onAccent;
  final Color accentBlue;
  final Color textPrimary;
  /// Between primary and muted — card titles, secondary headings
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color negative;
  /// Subtle negative tint — error backgrounds, danger zones
  final Color negativeSubtle;
  final Color positive;
  /// Subtle positive tint — success backgrounds
  final Color positiveSubtle;
  /// Gold-tinted ambient shadow for elevated cards
  final Color cardGlow;

  // ── Dark palette (U Cluj — deep charcoal + gold) ──────────────────────────
  static const AppColorTokens dark = AppColorTokens(
    surface:      Color(0xFF0D0D0D), // near-black — true base
    surfaceLow:   Color(0xFF111111), // subtle recess (inputs, pressed states)
    surfaceHigh:  Color(0xFF1C1C1E), // cards — 12 steps above surface, visible depth
    accent:       Color(0xFFF5C518), // U Cluj gold — reserved for primary actions
    accentStrong: Color(0xFFD4A800), // pressed / active gold
    onAccent:     Color(0xFF0D0D0D),
    accentBlue:   Color(0xFF1A56DB), // brightened blue — legible on dark
    textPrimary:    Color(0xFFF2F2F2), // off-white — softer than pure white, less eye strain
    textSecondary:  Color(0xFFCCCCCC), // card titles, sub-headings
    textMuted:      Color(0xFFAAAAAA), // lifted from #9A → #AA for better contrast
    divider:        Color(0x1FFFFFFF), // 12% white — visible but not harsh
    negative:       Color(0xFFFF453A), // iOS-style red — warmer, less neon
    negativeSubtle: Color(0x1AFF453A), // 10% red tint for backgrounds
    positive:       Color(0xFF4ADE80), // slightly warmer green — harmonises with gold
    positiveSubtle: Color(0x1A4ADE80), // 10% green tint for backgrounds
    cardGlow:       Color(0x0CF5C518), // gold ambient glow — subtle elevation cue
  );

  // ── Light palette (clean white + U Cluj gold) ─────────────────────────────
  static const AppColorTokens light = AppColorTokens(
    surface:        Color(0xFFF5F5F5),
    surfaceLow:     Color(0xFFEDEDED),
    surfaceHigh:    Color(0xFFFFFFFF),
    accent:         Color(0xFFD4A800), // darker gold — legible on white
    accentStrong:   Color(0xFFB08900),
    onAccent:       Color(0xFFFFFFFF),
    accentBlue:     Color(0xFF1A56DB),
    textPrimary:    Color(0xFF111111),
    textSecondary:  Color(0xFF444444),
    textMuted:      Color(0xFF777777),
    divider:        Color(0x1A000000), // 10% black
    negative:       Color(0xFFDC2626),
    negativeSubtle: Color(0x1ADC2626),
    positive:       Color(0xFF16A34A),
    positiveSubtle: Color(0x1A16A34A),
    cardGlow:       Color(0x08D4A800),
  );
}

// ── InheritedWidget ───────────────────────────────────────────────────────────

class _AppColorsScope extends InheritedWidget {
  const _AppColorsScope({required this.colors, required super.child});
  final AppColorTokens colors;

  @override
  bool updateShouldNotify(_AppColorsScope old) => colors != old.colors;
}

/// Place above [MaterialApp] (or any subtree) to provide theme-aware colors.
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

// ── BuildContext extension ────────────────────────────────────────────────────

extension AppColorsX on BuildContext {
  /// Returns the active [AppColorTokens] for the current theme.
  AppColorTokens get colors =>
      dependOnInheritedWidgetOfExactType<_AppColorsScope>()?.colors ??
      AppColorTokens.dark;
}
