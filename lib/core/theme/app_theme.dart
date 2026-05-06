import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'typography_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData _build({required AppColorTokens c, required bool dark}) {
    final base = dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      splashFactory: NoSplash.splashFactory,
      colorScheme: dark
          ? ColorScheme.dark(
              primary: c.accent,
              onPrimary: c.onAccent,
              surface: c.surface,
              onSurface: c.textPrimary,
              error: c.negative,
            )
          : ColorScheme.light(
              primary: c.accent,
              onPrimary: c.onAccent,
              surface: c.surface,
              onSurface: c.textPrimary,
              error: c.negative,
            ),
      textTheme: base.textTheme.copyWith(
        displayLarge: TypographyTokens.displayHero,
        headlineLarge: TypographyTokens.headline,
        bodyMedium: TypographyTokens.body,
        labelSmall: TypographyTokens.sectionLabel,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: c.surfaceHigh,
        elevation: 0,
        shadowColor: c.cardGlow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: c.divider),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textMuted,
        elevation: 0,
      ),
    );
  }

  static ThemeData get darkThemeData =>
      _build(c: AppColorTokens.dark, dark: true);

  static ThemeData get lightThemeData =>
      _build(c: AppColorTokens.light, dark: false);

  // Keep for backward compatibility
  static ThemeData get themeData => darkThemeData;
}
