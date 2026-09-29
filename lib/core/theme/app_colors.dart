import 'package:flutter/material.dart';

/// Tokens DAVEX/Lynkstor — source de vérité :
/// `docs/reference/figma_export/PrototypeApplicationDesign-main/src/ui/tokens.css`
/// (rôles sémantiques, clair et sombre).
///
/// Seule entorse validée à la copie fidèle : [LkPalette.onAction].
/// Le blanc sur #FF9800 = 2,16:1 (défaut WCAG signalé par
/// docs/UI_UX_AUDIT_2026-09-22.md) ; remplacé par l'encre foncée #3A2500
/// → 6,7:1 sur #FF9800, conforme AA pour du texte normal, dans les 2 thèmes.
///
/// Les écrans encore non revus consomment [AppColors] (passerelle de compat
/// dépréciée, éliminée vague par vague). Les composants de la V3 consomment
/// [LkPalette.of] (courbe 150 ms entre thèmes, cf. index.css).
class LkPalette {
  const LkPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.text,
    required this.textSecondary,
    required this.borderDecorative,
    required this.borderControl,
    required this.action,
    required this.onAction,
    required this.actionHover,
    required this.actionPressed,
    required this.link,
    required this.selectedBg,
    required this.selectedFg,
    required this.success,
    required this.successBg,
    required this.successFg,
    required this.warning,
    required this.warningBg,
    required this.warningFg,
    required this.danger,
    required this.dangerBg,
    required this.dangerFg,
    required this.info,
    required this.infoBg,
    required this.infoFg,
    required this.disabledBg,
    required this.disabledFg,
    required this.focus,
    required this.charts,
    required this.overlay,
    required this.shadowCard,
  });

  /// Rôle « accent » de la maquette (toujours #FF9800).
  Color get accent => action;

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color text;
  final Color textSecondary;
  final Color borderDecorative;
  final Color borderControl;
  final Color action;

  /// Texte d'action sur aplat orange — correction AA (#3A2500, jamais blanc).
  final Color onAction;
  final Color actionHover;
  final Color actionPressed;
  final Color link;
  final Color selectedBg;
  final Color selectedFg;
  final Color success;
  final Color successBg;
  final Color successFg;
  final Color warning;
  final Color warningBg;
  final Color warningFg;
  final Color danger;
  final Color dangerBg;
  final Color dangerFg;
  final Color info;
  final Color infoBg;
  final Color infoFg;
  final Color disabledBg;
  final Color disabledFg;
  final Color focus;
  final List<Color> charts;
  final Color overlay;
  final BoxShadow shadowCard;

  static LkPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // ——— Clair : tokens.css [data-theme="light"] ———
  static const LkPalette light = LkPalette(
    canvas: Color(0xFFF6F8FC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF2F6),
    surfaceElevated: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    borderDecorative: Color(0xFFD8DEE7),
    borderControl: Color(0xFF778395),
    action: Color(0xFFFF9800),
    onAction: Color(0xFF3A2500),
    actionHover: Color(0xFFE88900),
    actionPressed: Color(0xFFCC7900),
    link: Color(0xFF1D6BFF),
    selectedBg: Color(0xFFEAF1FF),
    selectedFg: Color(0xFF1D6BFF),
    success: Color(0xFF16C784),
    successBg: Color(0xFFECFDF3),
    successFg: Color(0xFF067647),
    warning: Color(0xFFC96D00),
    warningBg: Color(0xFFFFFBEB),
    warningFg: Color(0xFF92400E),
    danger: Color(0xFFFF3B4D),
    dangerBg: Color(0xFFFEF3F2),
    dangerFg: Color(0xFFB42318),
    info: Color(0xFF1D6BFF),
    infoBg: Color(0xFFEAF2FF),
    infoFg: Color(0xFF0046B8),
    disabledBg: Color(0xFFE4E7EC),
    disabledFg: Color(0xFF667085),
    focus: Color(0xFFFF9800),
    charts: [
      Color(0xFF0050FF),
      Color(0xFF067647),
      Color(0xFF9F3A0E),
      Color(0xFFC026D3),
      Color(0xFF7E22CE),
    ],
    overlay: Color(0x730F172A),
    shadowCard: BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  );

  // ——— Sombre : tokens.css [data-theme="dark"] ———
  static const LkPalette dark = LkPalette(
    canvas: Color(0xFF06101F),
    surface: Color(0xFF091829),
    surfaceMuted: Color(0xFF0B1C30),
    surfaceElevated: Color(0xFF102238),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFAAB7CC),
    borderDecorative: Color(0xFF19324D),
    borderControl: Color(0xFF36516D),
    action: Color(0xFFFF9800),
    onAction: Color(0xFF3A2500),
    actionHover: Color(0xFFFFAD24),
    actionPressed: Color(0xFFE88900),
    link: Color(0xFF72A0FF),
    selectedBg: Color(0xFF132C51),
    selectedFg: Color(0xFF9AB8FF),
    success: Color(0xFF16C784),
    successBg: Color(0xFF0C392C),
    successFg: Color(0xFF16C784),
    warning: Color(0xFFFF9800),
    warningBg: Color(0xFF402C10),
    warningFg: Color(0xFFFFB54C),
    danger: Color(0xFFFF3B4D),
    dangerBg: Color(0xFF431923),
    dangerFg: Color(0xFFFF7180),
    info: Color(0xFF1D6BFF),
    infoBg: Color(0xFF142B56),
    infoFg: Color(0xFF72A0FF),
    disabledBg: Color(0xFF253247),
    disabledFg: Color(0xFF94A3B8),
    focus: Color(0xFFFF9800),
    charts: [
      Color(0xFF8CB4FF),
      Color(0xFF75E0A7),
      Color(0xFFF8D477),
      Color(0xFFFFB1DA),
      Color(0xFFC4B5FD),
    ],
    overlay: Color(0xA6000000),
    shadowCard: BoxShadow(
      color: Color(0x38000000),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  );
}

/// Valeurs partagées hors tokens (marque Lynk / géométrie).
class LkColors {
  LkColors._();

  /// Rayons — tokens.css --lk-radius-*.
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusXl = 20;

  /// Orange marque, identique dans les deux thèmes.
  static const Color accent = Color(0xFFFF9800);

  /// Violet Lynk (assistant IA) — hors tokens.css, identité de marque existante.
  static const Color lynkViolet = Color(0xFF5B16ED);
  static const Color lynkVioletSoft = Color(0xFFEFE8FF);
  static const Color lynkStar = Color(0xFFFAAD13);

  static LkPalette of(BuildContext context) => LkPalette.of(context);
}

/// Passerelle de compat — NE PAS ETENDRE.
///
/// Les ecrans non encore revus (phases 2-6) continuent de compiler ; chaque
/// valeur renvoie desormais un role de la maquette DAVEX. Les valeurs sont
/// alignees sur [LkPalette.light] (ou paires sémantiques) ; les helpers
/// taking un BuildContext resolvent clair/sombre.
class AppColors {
  AppColors._();

  // ——— Rôles action / marque ———
  static const Color action = Color(0xFFFF9800);
  static const Color onAction = Color(0xFF3A2500); // AA : 6,7:1 sur #FF9800
  static const Color primary = action;
  static const Color fab = action;
  static const Color onPrimary = onAction;
  static const Color primaryContainer = Color(0xFFFFFBEB);
  static const Color primaryFixed = Color(0xFFEAF1FF);
  static const Color secondary = Color(0xFF1D6BFF);
  static const Color tertiary = Color(0xFF0046B8);
  static const Color tertiaryFixed = Color(0xFFEAF2FF);
  static const Color punch = action;

  // ——— Textes ———
  static const Color text = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color inkFaint = Color(0xFF64748B);
  static const Color onSurface = ink;
  static const Color onSurfaceVariant = inkMuted;
  static const Color white = Color(0xFFFFFFFF);

  // ——— Surfaces ———
  static const Color canvas = Color(0xFFF6F8FC);
  static const Color pageBg = canvas;
  static const Color background = canvas;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceBright = surface;
  static const Color creamCard = surface;
  static const Color dock = surface;
  static const Color surfaceMuted = Color(0xFFEEF2F6);
  static const Color surfaceContainerLowest = surface;
  static const Color surfaceContainerLow = Color(0xFFF6F8FC);
  static const Color surfaceContainer = surfaceMuted;
  static const Color surfaceContainerHighest = Color(0xFFE4E7EC);
  static const Color outline = Color(0xFF778395);
  static const Color outlineVariant = Color(0xFFD8DEE7);
  static const Color grey500 = textSecondary;

  // ——— Sémantiques (rôles maquette) ———
  static const Color success = Color(0xFF16C784);
  static const Color successBg = Color(0xFFECFDF3);
  static const Color successFg = Color(0xFF067647);
  static const Color successSoft = successBg;
  static const Color warning = Color(0xFFC96D00);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningFg = Color(0xFF92400E);
  static const Color warningSoft = warningBg;
  static const Color danger = Color(0xFFFF3B4D);
  static const Color dangerBg = Color(0xFFFEF3F2);
  static const Color dangerFg = Color(0xFFB42318);
  static const Color error = dangerFg; // texte lisible sur blanc #FEF3F2
  static const Color errorSoft = dangerBg;
  static const Color info = Color(0xFF1D6BFF);
  static const Color infoBg = Color(0xFFEAF2FF);
  static const Color infoFg = Color(0xFF0046B8);
  static const Color infoSoft = infoBg;
  static const Color selectedBg = Color(0xFFEAF1FF);
  static const Color selectedFg = Color(0xFF1D6BFF);

  // ——— Etats metier ———
  static const Color draft = outline;
  static const Color pending = warning;
  static const Color synced = success;
  static const Color offline = outline;
  static const Color unpaid = danger;
  static const Color lowStock = warning;
  static const Color debt = dangerFg;
  static const Color refund = info;

  // ——— Alias KPI (cartes Accueil) ———
  static const Color kpiSales = successFg;
  static const Color kpiSalesBg = successBg;
  static const Color kpiCollect = link;
  static const Color kpiCollectBg = infoBg;
  static const Color kpiDebt = dangerFg;
  static const Color kpiDebtBg = dangerBg;
  static const Color kpiDeposit = Color(0xFFC026D3); // chart-4
  static const Color kpiDepositBg = Color(0xFFE8F0FE);

  // ——— Alias hérités → rôles DAVEX ———
  static const Color link = Color(0xFF1D6BFF);
  static const Color amber = warning;
  static const Color rose = danger;
  static const Color coral = warning;
  static const Color coralSoft = warningBg;
  static const Color clay = Color(0xFF9F3A0E); // chart-3
  static const Color terracotta = clay;
  static const Color terracottaSoft = Color(0xFFFFFBEB);
  static const Color emerald = success;
  static const Color forest = successFg;
  static const Color forestSoft = successBg;
  static const Color turquoise = success;
  static const Color turquoiseSoft = successBg;
  static const Color turquoiseDeep = successFg;
  static const Color sahelGold = success;
  static const Color sahelSand = infoBg;
  static const Color ice = infoBg;
  static const Color skyMist = infoBg;
  static const Color navy = infoFg;
  static const Color ocean = Color(0xFF06101F);
  static const Color sky = link;
  static const Color indigoDeep = action;

  // ——— Lynk / IA (hors tokens.css, identité marque) ———
  static const Color lynkViolet = LkColors.lynkViolet;
  static const Color lynkVioletSoft = LkColors.lynkVioletSoft;
  static const Color lynkStar = LkColors.lynkStar;
  static const Color lynkBody = link;
  static const Color lynkOnline = success;
  static const Color aiViolet = lynkViolet;
  static const Color aiCyan = Color(0xFF8CB4FF);
  static const Color aiGlow = Color(0xFF7B8CFF);
  static const Color headerStart = Color(0xFF06101F);
  static const Color collectEnd = lynkViolet;

  // ——— Mode sombre (tokens.css [data-theme="dark"]) ———
  static const Color darkBg = Color(0xFF06101F);
  static const Color darkSurface = Color(0xFF091829);
  static const Color darkCard = Color(0xFF102238);
  static const Color darkBorder = Color(0xFF19324D);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFAAB7CC);

  // ——— Helpers theme-aware ———
  static bool isDark(BuildContext context) => LkPalette.isDark(context);

  static LkPalette palette(BuildContext context) => LkPalette.of(context);

  static Color card(BuildContext context) =>
      isDark(context) ? LkPalette.dark.surfaceElevated : LkPalette.light.surface;

  static Color elevated(BuildContext context) =>
      isDark(context) ? LkPalette.dark.surface : LkPalette.light.surface;

  static Color mutedFill(BuildContext context) =>
      isDark(context)
      ? LkPalette.dark.surfaceMuted
      : LkPalette.light.surfaceMuted;

  static List<BoxShadow> cardShadow({
    double opacity = 0.08,
    bool dark = false,
  }) => [
    BoxShadow(
      color: (dark ? Colors.black : const Color(0xFF0F172A)).withValues(
        alpha: opacity,
      ),
      blurRadius: dark ? 28 : 24,
      offset: Offset(0, dark ? 10 : 8),
    ),
  ];

  static List<BoxShadow> tintedShadow(
    Color color, {
    double opacity = 0.26,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: 20,
      offset: const Offset(0, 10),
      spreadRadius: -8,
    ),
  ];

  static const List<Color> catalogBlocks = [
    Color(0xFFEEF2F6), // surface-muted
    Color(0xFFEAF1FF), // selected-bg
    Color(0xFFFFFBEB), // warning-bg
    Color(0xFFECFDF3), // success-bg
    Color(0xFFEAF2FF), // info-bg
    Color(0xFFFEF3F2), // danger-bg
  ];

  static Color catalogBlock(int index) =>
      catalogBlocks[index.abs() % catalogBlocks.length];

  // ——— Schemes Material 3, construits sur les tokens ———
  static ColorScheme lightScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFFF9800),
    onPrimary: Color(0xFF3A2500),
    primaryContainer: Color(0xFFFFFBEB),
    onPrimaryContainer: Color(0xFF92400E),
    secondary: Color(0xFF1D6BFF),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEAF1FF),
    onSecondaryContainer: Color(0xFF1D6BFF),
    tertiary: Color(0xFF0046B8),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEAF2FF),
    onTertiaryContainer: Color(0xFF0046B8),
    error: Color(0xFFB42318),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEF3F2),
    onErrorContainer: Color(0xFFB42318),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0F172A),
    onSurfaceVariant: Color(0xFF64748B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F8FC),
    surfaceContainer: Color(0xFFEEF2F6),
    surfaceContainerHigh: Color(0xFFE4E7EC),
    surfaceContainerHighest: Color(0xFFE4E7EC),
    outline: Color(0xFF778395),
    outlineVariant: Color(0xFFD8DEE7),
    shadow: Color(0xFF0F172A),
    scrim: Color(0xFF0F172A),
    inverseSurface: Color(0xFF0F172A),
    onInverseSurface: Color(0xFFF6F8FC),
    inversePrimary: Color(0xFFFFAD24),
  );

  static ColorScheme darkScheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFF9800),
    onPrimary: Color(0xFF3A2500),
    primaryContainer: Color(0xFF402C10),
    onPrimaryContainer: Color(0xFFFFB54C),
    secondary: Color(0xFF72A0FF),
    onSecondary: Color(0xFF06101F),
    secondaryContainer: Color(0xFF132C51),
    onSecondaryContainer: Color(0xFF9AB8FF),
    tertiary: Color(0xFF72A0FF),
    onTertiary: Color(0xFF06101F),
    tertiaryContainer: Color(0xFF142B56),
    onTertiaryContainer: Color(0xFF72A0FF),
    error: Color(0xFFFF7180),
    onError: Color(0xFF431923),
    errorContainer: Color(0xFF431923),
    onErrorContainer: Color(0xFFFF7180),
    surface: Color(0xFF091829),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFAAB7CC),
    surfaceContainerLowest: Color(0xFF06101F),
    surfaceContainerLow: Color(0xFF091829),
    surfaceContainer: Color(0xFF0B1C30),
    surfaceContainerHigh: Color(0xFF102238),
    surfaceContainerHighest: Color(0xFF102238),
    outline: Color(0xFF36516D),
    outlineVariant: Color(0xFF19324D),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF6F8FC),
    onInverseSurface: Color(0xFF0F172A),
    inversePrimary: Color(0xFFE88900),
  );
}
