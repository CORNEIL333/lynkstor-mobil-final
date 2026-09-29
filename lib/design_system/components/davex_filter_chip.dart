import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_pressable.dart';

/// RECRÉER depuis `.lk-filter-chip` (components.css L401–416) :
/// min-height 38, padding 6×13, bord 1 px borderControl, radius 999,
/// 13 px w650 (→ w600, seule graisse standard la plus proche),
/// encre textSecondary ; actif : fond accent + bord accent.
///
/// ÉCART VOLONTAIRE (charte) : encre sur orange = #3A2500 (onAction),
/// jamais le blanc CSS (contraste 2,16:1 refusé par WCAG/HIG).
/// HIG : cible tactile portée à 44 pt de haut malgré le visuel 38 px.
class DavexFilterChip extends StatelessWidget {
  const DavexFilterChip({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
    this.leading,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final fg = active ? p.onAction : p.textSecondary;
    return DavexPressable(
      onTap: onTap,
      minTouchTarget: 44,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? p.action : p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? p.action : p.borderControl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
