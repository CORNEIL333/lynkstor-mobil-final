import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/theme/app_colors.dart';

/// Contraste WCAG 2.1 : (L1 + 0.05) / (L2 + 0.05), luminances sRGB linéaires.
double _relativeLuminance(Color color) =>
    0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b);

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double contrast(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('DAVEX tokens — source tokens.css', () {
    test('clair : roles exacts', () {
      const p = LkPalette.light;
      expect(p.accent, const Color(0xFFFF9800));
      expect(p.info, const Color(0xFF1D6BFF));
      expect(p.success, const Color(0xFF16C784));
      expect(p.warning, const Color(0xFFC96D00));
      expect(p.danger, const Color(0xFFFF3B4D));
      expect(p.canvas, const Color(0xFFF6F8FC));
      expect(p.surface, const Color(0xFFFFFFFF));
      expect(p.surfaceMuted, const Color(0xFFEEF2F6));
      expect(p.text, const Color(0xFF0F172A));
      expect(p.textSecondary, const Color(0xFF64748B));
      expect(p.borderDecorative, const Color(0xFFD8DEE7));
      expect(p.borderControl, const Color(0xFF778395));
      expect(p.actionHover, const Color(0xFFE88900));
      expect(p.actionPressed, const Color(0xFFCC7900));
      expect(p.link, const Color(0xFF1D6BFF));
      expect(p.selectedBg, const Color(0xFFEAF1FF));
      expect(p.selectedFg, const Color(0xFF1D6BFF));
      expect(p.successBg, const Color(0xFFECFDF3));
      expect(p.successFg, const Color(0xFF067647));
      expect(p.warningBg, const Color(0xFFFFFBEB));
      expect(p.warningFg, const Color(0xFF92400E));
      expect(p.dangerBg, const Color(0xFFFEF3F2));
      expect(p.dangerFg, const Color(0xFFB42318));
      expect(p.infoBg, const Color(0xFFEAF2FF));
      expect(p.infoFg, const Color(0xFF0046B8));
      expect(p.disabledBg, const Color(0xFFE4E7EC));
      expect(p.disabledFg, const Color(0xFF667085));
      expect(p.focus, const Color(0xFFFF9800));
      expect(p.charts, const [
        Color(0xFF0050FF),
        Color(0xFF067647),
        Color(0xFF9F3A0E),
        Color(0xFFC026D3),
        Color(0xFF7E22CE),
      ]);
      expect(p.overlay, const Color(0x730F172A));
    });

    test('sombre : roles exacts', () {
      const p = LkPalette.dark;
      expect(p.canvas, const Color(0xFF06101F));
      expect(p.surface, const Color(0xFF091829));
      expect(p.surfaceMuted, const Color(0xFF0B1C30));
      expect(p.surfaceElevated, const Color(0xFF102238));
      expect(p.text, const Color(0xFFFFFFFF));
      expect(p.textSecondary, const Color(0xFFAAB7CC));
      expect(p.borderDecorative, const Color(0xFF19324D));
      expect(p.borderControl, const Color(0xFF36516D));
      expect(p.action, const Color(0xFFFF9800));
      expect(p.actionHover, const Color(0xFFFFAD24));
      expect(p.actionPressed, const Color(0xFFE88900));
      expect(p.link, const Color(0xFF72A0FF));
      expect(p.selectedBg, const Color(0xFF132C51));
      expect(p.selectedFg, const Color(0xFF9AB8FF));
      expect(p.warning, const Color(0xFFFF9800));
      expect(p.successBg, const Color(0xFF0C392C));
      expect(p.successFg, const Color(0xFF16C784));
      expect(p.warningBg, const Color(0xFF402C10));
      expect(p.warningFg, const Color(0xFFFFB54C));
      expect(p.dangerBg, const Color(0xFF431923));
      expect(p.dangerFg, const Color(0xFFFF7180));
      expect(p.infoBg, const Color(0xFF142B56));
      expect(p.infoFg, const Color(0xFF72A0FF));
      expect(p.disabledBg, const Color(0xFF253247));
      expect(p.disabledFg, const Color(0xFF94A3B8));
      expect(p.charts, const [
        Color(0xFF8CB4FF),
        Color(0xFF75E0A7),
        Color(0xFFF8D477),
        Color(0xFFFFB1DA),
        Color(0xFFC4B5FD),
      ]);
      expect(p.overlay, const Color(0xA6000000));
    });
  });

  group('Contraste AA — paires verrouillées (les deux thèmes)', () {
    for (final (name, p) in [('clair', LkPalette.light), ('sombre', LkPalette.dark)]) {
      test('$name : texte d\'action sur orange >= 4,5:1', () {
        // Entorse validée à la maquette : le blanc sur #FF9800 (2,16:1)
        // est remplacé par l'encre #3A2500.
        expect(
          contrast(p.onAction, p.action),
          greaterThanOrEqualTo(4.5),
          reason: 'onAction/action',
        );
      });

      test('$name : paires sémantiques fg/bg >= 4,5:1', () {
        expect(contrast(p.successFg, p.successBg), greaterThanOrEqualTo(4.5),
            reason: 'success');
        expect(contrast(p.warningFg, p.warningBg), greaterThanOrEqualTo(4.5),
            reason: 'warning');
        expect(contrast(p.dangerFg, p.dangerBg), greaterThanOrEqualTo(4.5),
            reason: 'danger');
        expect(contrast(p.infoFg, p.infoBg), greaterThanOrEqualTo(4.5),
            reason: 'info');
      });

      test('$name : textes courants sur surfaces >= 4,5:1', () {
        expect(contrast(p.text, p.surface), greaterThanOrEqualTo(4.5),
            reason: 'text/surface');
        expect(contrast(p.text, p.canvas), greaterThanOrEqualTo(4.5),
            reason: 'text/canvas');
        expect(contrast(p.textSecondary, p.surface), greaterThanOrEqualTo(4.5),
            reason: 'textSecondary/surface');
        expect(contrast(p.link, p.surface), greaterThanOrEqualTo(4.5),
            reason: 'link/surface');
        // NB: textSecondary #64748B sur canvas #F6F8FC = 4,48:1 dans la
        // maquette (juste sous AA). Valeur fidèle conservée ; arbitrage
        // (assombrir ou réserver le canvas au texte primaire) en phase 7.
      });
    }
  });
}
