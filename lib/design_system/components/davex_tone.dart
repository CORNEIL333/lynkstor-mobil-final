import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Tons sémantiques de la maquette (`--lk-success/warning/danger/info`,
/// `.lk-status-badge--*`, `.lk-metric-card--*`).
enum DavexTone { info, success, warning, danger, neutral }

/// Résolution (fond, encre) d'un ton dans la palette courante.
/// Le ton « neutral » est hors charte metric-card : il retombe sur
/// surfaceMuted / textSecondary (comme `.lk-status-badge--neutral`).
({Color bg, Color fg}) davexToneColors(LkPalette p, DavexTone tone) =>
    switch (tone) {
      DavexTone.info => (bg: p.infoBg, fg: p.info),
      DavexTone.success => (bg: p.successBg, fg: p.success),
      DavexTone.warning => (bg: p.warningBg, fg: p.warning),
      DavexTone.danger => (bg: p.dangerBg, fg: p.danger),
      DavexTone.neutral => (bg: p.surfaceMuted, fg: p.textSecondary),
    };
