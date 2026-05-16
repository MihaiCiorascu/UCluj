import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'color_tokens.dart';
import 'typography_tokens.dart';

/// Iteration N — light + dark Material 3 themes for the early-2000s
/// glossy aesthetic. Both share the same typography scale; the colour
/// scheme differs per palette so widgets that consume
/// ``Theme.of(context).colorScheme`` render the right tones.
///
/// The legacy ``themeData`` getter is preserved (as an alias to
/// ``lightTheme``) for any call site that has not migrated yet.
class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme => _build(AppColorTokens.light);
  static ThemeData get darkTheme => _build(AppColorTokens.dark);

  /// Back-compat alias.
  static ThemeData get themeData => lightTheme;

  static ThemeData _build(AppColorTokens p) {
    final isDark = p.isDark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.glow,
            surface: p.surfaceBaseTop,
            onSurface: p.textPrimary,
            error: ColorTokens.negative,
          )
        : ColorScheme.light(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.glow,
            surface: p.surfaceBaseTop,
            onSurface: p.textPrimary,
            error: ColorTokens.negative,
          );

    return base.copyWith(
      scaffoldBackgroundColor: p.surfaceBaseTop,
      canvasColor: p.surfaceBaseTop,
      colorScheme: colorScheme,
      brightness: p.brightness,
      splashFactory: InkRipple.splashFactory,
      textTheme: base.textTheme.copyWith(
        displayLarge:
            TypographyTokens.displayHero.copyWith(color: p.textPrimary),
        headlineLarge:
            TypographyTokens.headline.copyWith(color: p.textPrimary),
        bodyMedium: TypographyTokens.body.copyWith(color: p.textPrimary),
        labelSmall:
            TypographyTokens.sectionLabel.copyWith(color: p.textMuted),
      ),
      iconTheme: IconThemeData(color: p.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: p.surfaceElevatedTop,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: p.chrome, width: 0.8),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surfaceElevatedTop,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textMuted,
        elevation: 4,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TypographyTokens.body.copyWith(color: p.textPrimary),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surfaceElevatedTop),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.chrome, width: 0.8),
          )),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    );
  }
}
