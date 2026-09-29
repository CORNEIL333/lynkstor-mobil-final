import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_icon_button.dart';

/// RECRÉER depuis `LynkstorQuantitySelector` (components.tsx L12) +
/// `.lk-quantity-selector` (components.css L418–429) :
/// icône-boutons − / + (44 px natifs), valeur centrale min-width 28,
/// w750 (→ w700), gap 6. Accessibilité : sémantique « Diminuer/Augmenter
/// la quantité » reprise mot pour mot de la maquette.
class DavexQuantitySelector extends StatelessWidget {
  const DavexQuantitySelector({
    super.key,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.canDecrease = true,
    this.canIncrease = true,
  });

  final num value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool canDecrease;
  final bool canIncrease;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final display = value is int
        ? '$value'
        : (value % 1 == 0 ? value.toInt().toString() : '$value');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DavexIconButton(
          icon: Icons.remove,
          tooltip: 'Diminuer la quantité',
          onPressed: canDecrease ? onDecrease : null,
          size: 44,
          iconSize: 18,
        ),
        SizedBox(
          width: 34,
          child: Text(
            display,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        DavexIconButton(
          icon: Icons.add,
          tooltip: 'Augmenter la quantité',
          onPressed: canIncrease ? onIncrease : null,
          size: 44,
          iconSize: 18,
        ),
      ],
    );
  }
}
