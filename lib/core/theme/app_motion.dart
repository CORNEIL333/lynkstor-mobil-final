import 'package:flutter/material.dart';

/// Motion DAVEX — valeurs de `index.css` de la maquette :
/// easing standard cubic-bezier(0.16, 1, 0.3, 1), transitions 160-280 ms,
/// cascade d'entree 380 ms avec stagger 40 ms, press scale 0.95/0.97.
/// Jamais `scale(0)` ; toute animation raccourcit le temps percu, jamais
/// l'inverse (design-system.md §6).
class AppMotion {
  AppMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 280);
  static const Duration entrance = Duration(milliseconds: 380);
  static const Duration chip = Duration(milliseconds: 180);
  static const Duration ticker = Duration(milliseconds: 720);

  /// Délai entre éléments d'une même séquence (stagger .stagger-N = 40 ms).
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// Ease-out signature de la maquette (slide/cascade/press).
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);
  /// Pop-in avec micro-overshoot (confirmation de vente, îlots).
  static const Curve pop = Curves.easeOutBack;
  static const Curve springy = Cubic(0.16, 1, 0.3, 1);

  /// Distances d'entrée — index.css : slide 28 px, cascade 18 px.
  static const double slideDistance = 28;
  static const double cascadeDistance = 18;

  /// Press scale — .lk-ds-button:active scale(.97), .active-press scale(.95).
  static const double pressScale = 0.97;
  static const double pressScaleStrong = 0.95;
  static const double enterScale = 0.97;

  static Duration of(
    BuildContext context,
    Duration d, {
    bool performanceMode = false,
  }) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || performanceMode) return Duration.zero;
    return d;
  }
}
