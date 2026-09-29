import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import '../../core/theme/app_colors.dart';

/// CRÉER — présentation modale de toutes les fiches/modales de la maquette
/// (dépenses, reporting, clôture Z, carnet, détail produit…).
///
/// Conformité HIG (*Panels* / *Sheets*, Apple HIG « Views → Panels ») :
/// - poignée de préhension visible (36×5, centered, top) ;
/// - drag-to-dismiss natif (`isScrollControlled` + `DraggableScrollableSheet`
///   avec `scrollController` fourni au builder) ;
/// - detents : hauteur initiale [initialChildSize] (défaut 0,85 ≈ « large »
///   iOS), min 0,5 ;
/// - safe area bas respectée ; fond surface + radius haut 20 (maquette,
///   écart volontaire documenté avec le material systemBackground natif).
Future<T?> showDavexSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, ScrollController controller)
      builder,
  double initialChildSize = 0.85,
}) {
  final p = LkPalette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: p.borderDecorative)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Poignée HIG.
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: p.borderControl.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700, // HIG: headliné de sheet.
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                  color: p.textSecondary,
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: DraggableScrollableSheet(
              initialChildSize: initialChildSize.clamp(0.5, 0.95),
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, controller) =>
                  builder(context, controller),
            ),
          ),
        ],
      ),
    ),
  );
}
