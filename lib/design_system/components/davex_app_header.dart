import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'davex_pressable.dart';
import 'davex_sync_indicator.dart';
import 'sync_indicator.dart' show LkSyncTransport;

/// RECRÉER depuis `design-system/LynkstorHeader.tsx` + `.lk-header*`
/// (components.css L1–158). Chrome navy fixe des deux thèmes, comme la
/// barre d'onglets.
///
/// Spécifications maquette :
/// - fond dégradé 116 deg #08192D → #06101F 58 % → #071526, bord bas 1 px
///   borderDecorative ;
/// - blob `::before` 204×204 en (-102, -90), radial #FFB321 → #FF9800 56 %
///   → #E77D00, ombre 0 18/50 rgba(255,152,0,.22) ;
/// - main : min-height 112, padding 18/16/14, gap 12 ;
/// - profil 76 px, avatar 58 px cercle bord 3 px blanc 72 %, fond #EDF3FF,
///   encre #1D6BFF 22 px w800 ;
/// - titre blanc clamp(21, 6 vw, 30) w750 (→ w700) ls -0,04 em lh 1,08 ;
///   sous-titre #C5D0E1 13 px, une ligne, ellipsis ;
/// - actions [Panier][Bell][Menu] : ronds 44 px #16253A bord 1 px blanc 6 %,
///   active scale .94 + fond #203552 ; badge compte 20 px #FF9800 bord 2 px
///   #091829 ;
/// - slot contexte (children) : padding 0/10/14/16.
///
/// HIG : safe area status bar respectée (MediaQuery.padding.top), icônes
/// système blanches via `SystemUiOverlayStyle.light`, cibles 44×44 pt.
/// ÉCART VOLONTAIRE (charte) : chiffre du badge en encre #3A2500 sur orange
/// (le blanc CSS = 2,16:1, refusé par WCAG).
class DavexAppHeader extends StatelessWidget {
  const DavexAppHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.avatarInitials = 'LS',
    this.cartCount = 0,
    this.notificationCount = 0,
    this.showCart = true,
    this.onCart,
    this.showNotification = true,
    this.onNotification,
    this.showMenu = true,
    this.onMenu,
    this.showBack = false,
    this.onBack,
    this.online = true,
    this.pendingSync = 0,
    this.onStatusTap,
    this.syncTransport,
    this.contextSlot,
  });

  final String title;
  final String subtitle;
  final String avatarInitials;
  final int cartCount;
  final int notificationCount;
  final bool showCart;
  final VoidCallback? onCart;
  final bool showNotification;
  final VoidCallback? onNotification;
  final bool showMenu;
  final VoidCallback? onMenu;
  final bool showBack;
  final VoidCallback? onBack;

  /// Indicateur condensé d'état de connexion (remplace la bannière
  /// hors-ligne). [online] = connectivité, [pendingSync] = opérations en
  /// attente de synchronisation. Tapping → [onStatusTap] (fiche de détail).
  final bool online;
  final int pendingSync;
  final VoidCallback? onStatusTap;

  /// Pill de transport dans le slot contexte (barre d'accueil maquette).
  final LkSyncTransport? syncTransport;
  final Widget? contextSlot;

  static const _bgStops = [Color(0xFF08192D), Color(0xFF06101F), Color(0xFF071526)];

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.06).clamp(21.0, 30.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-0.85, -0.53),
            end: Alignment(0.85, 0.53),
            colors: _bgStops,
            stops: [0, 0.58, 1],
          ),
          border: Border(bottom: BorderSide(color: p.borderDecorative)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Blob orange décoratif `::before`.
            Positioned(
              top: -90,
              left: -102,
              child: Container(
                width: 204,
                height: 204,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(0.44, 0.3),
                    radius: 0.85,
                    colors: [Color(0xFFFFB321), Color(0xFFFF9800), Color(0xFFE77D00)],
                    stops: [0, 0.56, 1],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1FFF9800),
                      blurRadius: 34,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 112),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 76,
                            child: Center(
                              child: showBack
                                  ? _HeaderAction(
                                      size: 44,
                                      onTap: onBack,
                                      semanticLabel: 'Retour',
                                      child: const Icon(
                                        Icons.chevron_left,
                                        size: 25,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Container(
                                      width: 58,
                                      height: 58,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFFEDF3FF),
                                        border: Border.all(
                                          color: const Color(
                                            0xB8FFFFFF,
                                          ), // blanc 72 %
                                          width: 3,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x1F000000),
                                            blurRadius: 14,
                                            offset: Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        avatarInitials,
                                        style: const TextStyle(
                                          color: Color(0xFF1D6BFF),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: titleSize * -0.04,
                                    height: 1.08,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFC5D0E1),
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // `.lk-header-actions` — aligné en haut (flex-start).
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ConnectionStatusAction(
                                    online: online,
                                    pendingSync: pendingSync,
                                    onTap: onStatusTap,
                                  ),
                                  const SizedBox(width: 6),
                                  if (showCart)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _HeaderAction(
                                        size: 44,
                                        onTap: onCart,
                                        semanticLabel:
                                            'Panier, $cartCount article${cartCount > 1 ? 's' : ''}',
                                        badgeCount: cartCount,
                                        child: const Icon(
                                          Icons.shopping_cart_outlined,
                                          size: 22,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (showNotification)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _HeaderAction(
                                        size: 44,
                                        onTap: onNotification,
                                        semanticLabel:
                                            '$notificationCount notification${notificationCount > 1 ? 's' : ''}',
                                        badgeCount: notificationCount,
                                        child: const Icon(
                                          Icons.notifications_none,
                                          size: 21,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (showMenu)
                                    _HeaderAction(
                                      size: 44,
                                      onTap: onMenu,
                                      semanticLabel: 'Ouvrir le menu',
                                      child: const Icon(
                                        Icons.menu,
                                        size: 23,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (contextSlot != null || syncTransport != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 10, 14),
                      child:
                          contextSlot ??
                          (syncTransport != null
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: DavexSyncIndicator(
                                    transport: syncTransport!,
                                  ),
                                )
                              : const SizedBox.shrink()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.lk-header-action` : rond #16253A, bord blanc 6 %, active = scale .94
/// + fond #203552 ; badge compte `.lk-header-count`.
class _HeaderAction extends StatefulWidget {
  const _HeaderAction({
    required this.size,
    required this.onTap,
    required this.semanticLabel,
    required this.child,
    this.badgeCount = 0,
  });

  final double size;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Widget child;
  final int badgeCount;

  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: widget.size,
                height: widget.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed
                      ? const Color(0xFF203552)
                      : const Color(0xFF16253A),
                  border: Border.all(color: const Color(0x0FFFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0DFFFFFF),
                      blurRadius: 0,
                      offset: Offset(0, 1),
                      spreadRadius: -1,
                    ),
                  ],
                ),
                child: widget.child,
              ),
              if (widget.badgeCount > 0)
                Positioned(
                  top: -6,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFF091829), width: 2),
                    ),
                    child: Text(
                      widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                      style: const TextStyle(
                        color: Color(0xFF3A2500), // encre, écart WCAG assumé.
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicateur condensé d'état de connexion — remplace la bannière
/// hors-ligne pleine largeur. Conformité iOS (*Status & feedback*, restraint)
/// : glyphe cloud seul, sans fond, qui ne rivalise pas avec les 3 actions
/// primary. La teinte porte l'état (calme = synchro OK, ambre = attention /
/// file d'attente), une pastille chiffre le volume en attente. Le tout est
/// une cible tactile 44×44 pt (via [DavexPressable]) dont le tap ouvre la
/// fiche de détail. Never color-only : le libellé voix-de-lis le précise.
class _ConnectionStatusAction extends StatelessWidget {
  const _ConnectionStatusAction({
    required this.online,
    required this.pendingSync,
    this.onTap,
  });

  final bool online;
  final int pendingSync;
  final VoidCallback? onTap;

  static const _attention = Color(0xFFFFD58C);
  static const _calm = Color(0xB3FFFFFF); // white 70 %
  static const _offlineTint = Color(0xFFC5D0E1);

  @override
  Widget build(BuildContext context) {
    final pending = pendingSync > 0;
    final IconData icon;
    final Color tint;
    final String label;
    if (!online) {
      icon = Icons.cloud_off_outlined;
      tint = pending ? _attention : _offlineTint;
      label = pending
          ? 'Hors ligne · $pendingSync en attente de synchronisation'
          : 'Hors ligne · synchronisé dès le retour du réseau';
    } else if (pending) {
      icon = Icons.cloud_upload_outlined;
      tint = _attention;
      label = 'En ligne · $pendingSync en attente de synchronisation';
    } else {
      icon = Icons.cloud_done_outlined;
      tint = _calm;
      label = 'En ligne · synchronisé';
    }

    return DavexPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: tint),
              if (pending)
                Positioned(
                  top: -7,
                  right: -9,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF091829),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      pendingSync > 99 ? '99+' : '$pendingSync',
                      style: const TextStyle(
                        color: Color(0xFF3A2500), // encre, écart WCAG assumé.
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
