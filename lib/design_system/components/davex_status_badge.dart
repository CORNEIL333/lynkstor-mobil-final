import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_tone.dart';

/// RECRÉER depuis `LynkstorStatusBadge` (design-system/components.tsx) +
/// components.css `.lk-status-badge` :
/// inline-flex, min-height 26 px, padding 3×10, bord 1 px currentColor
/// (= encre du ton), radius 999, 12 px w700.
class DavexStatusBadge extends StatelessWidget {
  const DavexStatusBadge({
    super.key,
    required this.tone,
    required this.child,
  });

  DavexStatusBadge.text(String label, {super.key, required this.tone})
    : child = Text(label);

  final DavexTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final c = davexToneColors(p, tone);
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.fg),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: c.fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: c.fg, size: 13),
          child: child,
        ),
      ),
    );
  }
}
