/// Espacements & rayons DAVEX — tokens.css --lk-radius-*.
///
/// Échelle de rayons verrouillée par la maquette : 8 / 12 / 16 / 20.
/// Cibles tactiles : 44 px minimum (index.css `button { min-width/height:44 }`),
/// 48 px pour les actions principales.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  static const double pageHorizontal = 20;
  static const double pageVertical = 16;
  static const double sectionGap = 28;
  static const double cardPadding = 18;
  static const double listItemGap = 10;
  static const double gutter = 20;

  static const double inputHeight = 52;
  static const double buttonHeight = 52;
  static const double buttonHeightSm = 40;
  static const double touchTarget = 48;
  static const double navBarHeight = 64;
  static const double appBarHeight = 56;

  // ——— Rayons — scale tokens.css --lk-radius-* ———
  static const double radiusXs = 8;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 24;
  static const double radiusCapsule = 999;
  static const double radiusCircle = 9999;

  static const double elevationNone = 0;
  static const double elevationSm = 1;
  static const double elevationMd = 4;
  static const double elevationLg = 8;
  static const double elevationNav = 12;
}
