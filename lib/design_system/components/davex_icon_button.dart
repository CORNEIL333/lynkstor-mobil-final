import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_pressable.dart';

/// RECRÉER depuis `.lk-ds-icon-button` (components.css L288–333) et ses
/// déclinaisons : fond transparent par défaut ; variante « well » du header
/// maquette = cercle 44 px #16253A (`.lk-header-action`).
///
/// HIG : cible tactile 44×44 pt minimum, icône 20–24 px.
class DavexIconButton extends StatelessWidget {
  const DavexIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
    this.size = 44,
    this.iconSize = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Fond #16253A circulaire du header (sinon ghost transparent).
  final bool filled;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final fg = onPressed == null
        ? p.disabledFg
        : (filled ? const Color(0xFFE7EEF8) : p.text);
    return Tooltip(
      message: tooltip,
      child: DavexPressable(
        onTap: onPressed,
        semanticLabel: tooltip,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: filled ? const Color(0xFF16253A) : Colors.transparent,
            shape: filled ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: filled ? null : BorderRadius.circular(12),
          ),
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
  }
}
