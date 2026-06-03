import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'color_tokens.dart';
import 'shape_tokens.dart';
import 'typography_tokens.dart';

/// Light + dark Material 3 themes for the redesign.
///
/// The colour scheme is the documented cobalt-on-navy "Stoic Analyst" palette;
/// the type system is Inter (default family for all text) with Epilogue on the
/// display, headline, and title roles. Numeric roles inherit tabular figures
/// from the tokens. Both themes share the scale; only the palette differs.
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

    final colorScheme = (isDark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.glow,
      surface: p.surfaceBaseTop,
      onSurface: p.textPrimary,
      error: ColorTokens.negative,
    );

    // Inter as the default family for every text role, then Epilogue on the
    // editorial roles and explicit colours per role.
    final t = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: TypographyTokens.displayHero.copyWith(color: p.textPrimary),
      headlineLarge: TypographyTokens.headline.copyWith(color: p.textPrimary),
      headlineMedium: TypographyTokens.headline.copyWith(color: p.textPrimary),
      titleLarge: TypographyTokens.title.copyWith(color: p.textPrimary),
      titleMedium: TypographyTokens.cardTitle.copyWith(color: p.textPrimary),
      bodyLarge: TypographyTokens.body.copyWith(color: p.textPrimary),
      bodyMedium: TypographyTokens.body.copyWith(color: p.textPrimary),
      bodySmall: TypographyTokens.bodySmall.copyWith(color: p.textSecondary),
      labelLarge: TypographyTokens.buttonLabel.copyWith(color: p.textPrimary),
      labelMedium: TypographyTokens.meta.copyWith(color: p.textMuted),
      labelSmall: TypographyTokens.sectionLabel.copyWith(color: p.textMuted),
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.surfaceBaseTop,
      canvasColor: p.surfaceBaseTop,
      colorScheme: colorScheme,
      brightness: p.brightness,
      splashFactory: InkRipple.splashFactory,
      textTheme: t,
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
          borderRadius: ShapeTokens.card,
          side: BorderSide(color: p.divider),
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
            borderRadius: ShapeTokens.control,
            side: BorderSide(color: p.chrome, width: 0.8),
          )),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle:
            TypographyTokens.bodySmall.copyWith(color: p.textPrimary),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: ShapeTokens.control,
          side: BorderSide(color: p.divider),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: ShapeTokens.control,
          border: Border.all(color: p.divider),
        ),
        textStyle: TypographyTokens.bodySmall.copyWith(color: p.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    );
  }
}
