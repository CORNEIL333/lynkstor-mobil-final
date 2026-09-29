import 'package:flutter/material.dart';

/// LynkstorBottomNavigation — port fidèle de
/// `src/design-system/components.css` (.lk-bottom-navigation) et
/// `LynkstorBottomNavigation.tsx`.
///
/// Quatre destinations maximum — loi produit : Accueil / Vente / Stock /
/// Assistant. Jamais de cinquième onglet ; notifications, réglages, rapports
/// et création de boutique passent par le menu (bouton ☰ de l'en-tête).
///
/// La barre est **fixe navy** (#091829) dans les deux thèmes. Onglet actif :
/// pastille TONALE calme (accent ~20 % + glyphe/label ambre), sans halo radial
/// ni bloom — patron iOS/Material 3. L'orange saturé est réservé à l'action
/// primaire unique de l'app, pas à la navigation.

/// Valeurs figées de la maquette (indépendantes du thème clair/sombre).
const Color _kBarBg = Color(0xFF091829);
const Color _kBarBorder = Color(0xFF142B45);
const Color _kInactive = Color(0xFFAAB7CC);
const Color _kActiveFg = Color(0xFFFFAD24);
const Color _kActiveTonal = Color(0x33FF9800); // accent ~20 % — pastille calme.

class LkNavDestination {
  const LkNavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class LynkstorBottomNavigation extends StatelessWidget {
  const LynkstorBottomNavigation({
    super.key,
    required this.destinations,
    required this.onDestinationSelected,
    this.selectedIndex = 0,
  });

  final List<LkNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kBarBg,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _kBarBorder)),
          ),
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                for (final (i, d) in destinations.indexed)
                  Expanded(
                    child: _NavButton(
                      destination: d,
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final LkNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _kActiveFg : _kInactive;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pastille tonale calme (patron iOS / Material 3) — sans halo ni
              // bloom : l'accent est réservé au contenu, pas à la navigation.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 60,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _kActiveTonal : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  selected ? destination.activeIcon : destination.icon,
                  size: 22,
                  color: selected ? _kActiveFg : _kInactive,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
