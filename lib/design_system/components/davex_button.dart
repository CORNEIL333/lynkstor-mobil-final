import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_pressable.dart';

/// Variantes de `.lk-ds-button--*` (components.css L288–333).
enum DavexButtonVariant { primary, secondary, danger, ghost }

/// RECRÉER depuis `lk-ds-button` (components.css) :
/// - min 44×44 (HIG touch target), radius 12 (--lk-radius-medium), w700 ;
/// - `:active { transform: scale(.97) }` 160 ms → [DavexPressable] ;
/// - primary : fond --lk-accent #FF9800.
///
/// ÉCART VOLONTAIRE DOCUMENTÉ (charte projet, seule entorse acceptée) :
/// l'encre sur orange est #3A2500 (LkPalette.onAction) au lieu du blanc CSS —
/// blanc sur #FF9800 = 2,16:1 (non conforme WCAG/HIG), encre = 8,3:1.
class DavexButton extends StatelessWidget {
  const DavexButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = DavexButtonVariant.primary,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final DavexButtonVariant variant;
  final IconData? icon;

  /// `width: 100%` des CTA pleine largeur de la maquette.
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final enabled = onPressed != null && !busy;

    final (Color bg, Color fg, Color? borderColor, List<BoxShadow> shadow) =
        switch (variant) {
          DavexButtonVariant.primary => enabled
              ? (
                  p.action,
                  p.onAction,
                  null,
                  const [
                    BoxShadow(
                      color: Color(0x3DFF9800),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                )
              : (p.disabledBg, p.disabledFg, null, const []),
          DavexButtonVariant.secondary => (
            p.surface,
            p.text,
            p.borderControl,
            const [],
          ),
          DavexButtonVariant.danger => (
            p.danger,
            Colors.white,
            null,
            const [],
          ),
          DavexButtonVariant.ghost => (Colors.transparent, p.text, null, const []),
        };

    return DavexPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: expand ? double.infinity : null,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(LkColors.radiusMedium),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor),
          boxShadow: shadow,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else if (icon != null)
              Icon(icon, size: 17, color: fg),
            if (busy || icon != null) const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
