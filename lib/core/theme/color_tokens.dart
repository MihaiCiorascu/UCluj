import 'package:flutter/material.dart';

/// Iteration N — early-2000s sports-broadcast palette.
///
/// Two palettes are defined here as raw constants: a *light* (default) and
/// a *dark* variant. Widgets should normally consume colours via
/// ``context.colors`` (see ``app_colors.dart``), which delegates to the
/// active palette based on the current ``Theme.of(context).brightness``;
/// the raw constants below are exposed for places that need a compile-time
/// value (e.g. ``MaterialApp.builder``'s background).
///
/// The legacy U Cluj black/gold constants (``surface``, ``accent``,
/// ``onAccent``, etc.) are kept under their original names — they now
/// resolve to the *light* palette's equivalent tokens so any unmigrated
/// call site renders in the new style instead of breaking.
class ColorTokens {
  const ColorTokens._();

  // ── Light palette ──────────────────────────────────────────────────────
  // The page background is a sky-blue gradient; cards are pale glassy
  // panels with a crisp white top edge; primary CTAs are deep cobalt.
  static const Color lightSurfaceBaseTop = Color(0xFFEBF3FF);
  static const Color lightSurfaceBaseBottom = Color(0xFFC7DDF5);
  static const Color lightSurfaceElevatedTop = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevatedBottom = Color(0xFFDCE8F8);

  /// Per-card pale solid (used where a gradient isn't required).
  static const Color lightSurfaceLow = Color(0xFFF4F8FE);
  static const Color lightSurfaceHigh = Color(0xFFE6EFFB);

  static const Color lightPrimary = Color(0xFF0047AB);
  static const Color lightPrimaryDeep = Color(0xFF003D99);
  static const Color lightPrimaryGloss = Color(0x66FFFFFF);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);

  static const Color lightChrome = Color(0xFFC0CCDA);
  static const Color lightChromeDeep = Color(0xFF8A98A8);
  static const Color lightGlow = Color(0xFF42A5F5);

  static const Color lightTextPrimary = Color(0xFF0A1929);
  static const Color lightTextMuted = Color(0xFF5A6B7C);
  static const Color lightDivider = Color(0x22000000);

  // ── Dark palette ───────────────────────────────────────────────────────
  static const Color darkSurfaceBaseTop = Color(0xFF0A1929);
  static const Color darkSurfaceBaseBottom = Color(0xFF050D17);
  static const Color darkSurfaceElevatedTop = Color(0xFF1A2942);
  static const Color darkSurfaceElevatedBottom = Color(0xFF0F1A2D);

  static const Color darkSurfaceLow = Color(0xFF0F1B2D);
  static const Color darkSurfaceHigh = Color(0xFF1A2942);

  static const Color darkPrimary = Color(0xFF1E88E5);
  static const Color darkPrimaryDeep = Color(0xFF0D47A1);
  static const Color darkPrimaryGloss = Color(0x55FFFFFF);
  static const Color darkOnPrimary = Color(0xFFFFFFFF);

  static const Color darkChrome = Color(0xFF5B6A7F);
  static const Color darkChromeDeep = Color(0xFF2C3645);
  static const Color darkGlow = Color(0xFF64B5F6);

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextMuted = Color(0xFF9FB0C0);
  static const Color darkDivider = Color(0x33FFFFFF);

  // ── Universal status colours ──────────────────────────────────────────
  static const Color positive = Color(0xFF2E7D32);
  static const Color negative = Color(0xFFC62828);
  static const Color warning = Color(0xFFF57C00);

  // ── Legacy aliases (Iteration N back-compat) ──────────────────────────
  // Unmigrated call sites still reference these names. They now resolve
  // to the LIGHT palette equivalents so the app keeps rendering even in
  // places we haven't refactored yet.
  static const Color surface = lightSurfaceBaseTop;
  static const Color surfaceLow = lightSurfaceLow;
  static const Color surfaceHigh = lightSurfaceHigh;
  static const Color accent = lightPrimary;
  static const Color accentStrong = lightPrimaryDeep;
  static const Color onAccent = lightOnPrimary;
  // Distinct steel-blue. Was `lightPrimary`, which made the legacy
  // `accentBlue` indistinguishable from `accent`. Same value as
  // `AppColorTokens.light.roleDefender`.
  static const Color accentBlue = Color(0xFF1A4F7A);
  static const Color textPrimary = lightTextPrimary;
  static const Color textMuted = lightTextMuted;
  static const Color divider = lightDivider;
}
