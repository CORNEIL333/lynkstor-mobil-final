import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typographie DAVEX — design-system.md §3.3 :
/// une seule famille sans-serif haute lisibilite (Inter, pile de la maquette
/// `index.css` : -apple-system / Segoe UI / Inter), DEUX graisses seulement :
/// reguliere (w400) et medium (w500). Jamais plus.
class AppTypography {
  AppTypography._();

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;

  static TextTheme lightTextTheme = _build(
    AppColors.text,
    AppColors.textSecondary,
  );
  static TextTheme darkTextTheme = _build(
    LkPalette.dark.text,
    LkPalette.dark.textSecondary,
  );

  static TextTheme _build(Color primary, Color secondary) {
    const base = TextTheme();
    return GoogleFonts.interTextTheme(
      base.copyWith(
        displayLarge: TextStyle(
          fontSize: 40,
          fontWeight: medium,
          letterSpacing: -0.8,
          height: 1.06,
          color: primary,
        ),
        displayMedium: TextStyle(
          fontSize: 32,
          fontWeight: medium,
          letterSpacing: -0.6,
          height: 1.1,
          color: primary,
        ),
        displaySmall: TextStyle(
          fontSize: 28,
          fontWeight: medium,
          letterSpacing: -0.5,
          height: 1.12,
          color: primary,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: medium,
          letterSpacing: -0.3,
          height: 1.2,
          color: primary,
        ),
        headlineMedium: TextStyle(
          fontSize: 19,
          fontWeight: medium,
          letterSpacing: -0.2,
          height: 1.25,
          color: primary,
        ),
        headlineSmall: TextStyle(
          fontSize: 17,
          fontWeight: medium,
          height: 1.3,
          color: primary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: medium,
          height: 1.32,
          color: primary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: medium,
          height: 1.35,
          color: primary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: medium,
          height: 1.35,
          color: primary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: regular,
          height: 1.5,
          color: primary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: regular,
          height: 1.48,
          color: primary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: regular,
          height: 1.42,
          color: secondary,
        ),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: medium,
          height: 1.28,
          color: primary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: medium,
          height: 1.3,
          color: primary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: medium,
          height: 1.3,
          color: secondary,
        ),
      ),
    );
  }

  /// Montants — chiffres tabulaires, graisse medium maximum (§3.3).
  static TextStyle amount({
    double fontSize = 24,
    FontWeight weight = medium,
    Color? color,
    bool tabular = true,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      color: color ?? AppColors.text,
      height: 1.12,
      letterSpacing: -0.4,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle amountLarge({Color? color}) =>
      amount(fontSize: 32, color: color);

  static TextStyle amountMedium({Color? color}) =>
      amount(fontSize: 20, color: color);

  static TextStyle amountSmall({Color? color}) =>
      amount(fontSize: 15, color: color);

  static TextStyle tableData({Color? color}) {
    return TextStyle(
      fontSize: 13,
      fontWeight: medium,
      color: color ?? AppColors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle overline({Color? color}) {
    return TextStyle(
      fontSize: 11,
      fontWeight: medium,
      letterSpacing: 0.4,
      height: 1.3,
      color: color ?? AppColors.textSecondary,
    );
  }
}
