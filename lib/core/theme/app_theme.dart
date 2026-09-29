import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Thème Material 3 — maquette DAVEX (tokens.css + design-system/components.css).
///
/// Géométrie reprise à l'identique :
/// - boutons/champs : radius `medium` 12, cible tactile ≥ 44 px ;
/// - cartes : radius `large` 16 + ombre `--lk-shadow-card` ;
/// - dialogues/sheets : radius `xl` 20 ;
/// - texte d'action sur orange : encre #3A2500 (correction AA validée).
class AppTheme {
  AppTheme._();

  static ThemeData light({
    bool reducedMotion = false,
    bool performanceMode = false,
  }) {
    return _build(
      palette: LkPalette.light,
      scheme: AppColors.lightScheme,
      textTheme: AppTypography.lightTextTheme,
      reducedMotion: reducedMotion,
      performanceMode: performanceMode,
    );
  }

  static ThemeData dark({
    bool reducedMotion = false,
    bool performanceMode = false,
  }) {
    return _build(
      palette: LkPalette.dark,
      scheme: AppColors.darkScheme,
      textTheme: AppTypography.darkTextTheme,
      reducedMotion: reducedMotion,
      performanceMode: performanceMode,
    );
  }

  static ThemeData _build({
    required LkPalette palette,
    required ColorScheme scheme,
    required TextTheme textTheme,
    required bool reducedMotion,
    required bool performanceMode,
  }) {
    final cardRadius = BorderRadius.circular(AppSpacing.radiusLg);
    final controlRadius = BorderRadius.circular(AppSpacing.radiusMd);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      cardColor: palette.surface,
      dividerColor: palette.borderDecorative,
      splashFactory: reducedMotion || performanceMode
          ? NoSplash.splashFactory
          : InkSparkle.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: reducedMotion
              ? const FadeUpwardsPageTransitionsBuilder()
              : const PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: performanceMode ? 0 : 0.5,
        centerTitle: false,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge,
        toolbarHeight: AppSpacing.appBarHeight,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(44, AppSpacing.buttonHeight),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, AppSpacing.buttonHeight),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: palette.borderControl, width: 1),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.link,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, AppSpacing.buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSpacing.touchTarget,
              AppSpacing.touchTarget),
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: palette.borderControl),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: palette.borderControl),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: palette.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: palette.dangerFg),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: palette.dangerFg, width: 2),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
        labelStyle: textTheme.bodyMedium,
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(
          color: palette.dangerFg,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceMuted,
        selectedColor: palette.selectedBg,
        labelStyle: textTheme.labelMedium!.copyWith(
          color: palette.text,
        ),
        side: BorderSide(color: palette.borderDecorative),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: palette.borderControl.withValues(alpha: 0.45),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.canvas,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: performanceMode ? 2 : 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: palette.textSecondary,
      ),
      dividerTheme: DividerThemeData(
        color: palette.borderDecorative,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.surfaceMuted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return palette.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.35);
          }
          return palette.borderControl;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: palette.borderControl),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return palette.borderControl;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppSpacing.navBarHeight,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.selectedBg,
        iconTheme: WidgetStateProperty.resolveWith((s) {
          return IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected)
                ? palette.selectedFg
                : palette.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          return textTheme.labelSmall!.copyWith(
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w500
                : FontWeight.w400,
            color: s.contains(WidgetState.selected)
                ? palette.selectedFg
                : palette.textSecondary,
          );
        }),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.text,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: palette.canvas),
      ),
    );
  }
}
