import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/permissions/permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../design_system/components/davex_app_header.dart';
import '../../design_system/components/davex_sheet.dart';
import '../../design_system/components/lynkstor_bottom_navigation.dart';
import '../../l10n/app_strings.dart';
import 'shell_scaffold.dart' show activeIndexFor;
import '../../design_system/components/kumba_subscription_banner.dart';
import '../../features/sales/davex_cart.dart';

/// Shell DAVEX recréé (audit docs/UI_AUDIT_MAQUETTE_HIG.md §1) —
/// 4 onglets loi produit : Accueil / Vente / Stock / Assistant, jamais de
/// cinquième. Utilise [DavexAppHeader] (actions maquette Panier/Cloche/Menu)
/// et la barre d'onglets navy+orange recréée.
///
/// Logique RÉUTILISÉE TELLE QUEL (justifié : comportement maquette + tests
/// existants) : [_tabForPath], [activeIndexFor], [launchTabPathFor],
/// résolution du transport depuis connectivité/file d'attente.
///
/// Adaptations projet documentées :
/// - la pill de synchronisation vit dans la barre de salutation de l'Accueil
///   (comme la maquette), pas dans le header ;
/// - le badge Panier vient du provider `davexCartProvider` (étape a8b) :
///   live, il suit les articles ajoutés à la caisse ; le bouton ouvre /vente ;
/// - bannières hors-ligne et abonnement = fonctionnalités projet (garde-fous
///   réels), conservées sous le header.
class DavexShell extends ConsumerWidget {
  const DavexShell({super.key, required this.child});

  final Widget child;

  static const _tabForPath = <String, int>{
    '/home': 0,
    '/vente': 1,
    '/sales': 1,
    '/sale': 1,
    '/stock': 2,
    '/products': 2,
    '/inventory': 2,
    '/ai': 3,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final location = GoRouterState.of(context).uri.path;

    final destinations = <LkNavDestination>[
      LkNavDestination(
        label: S.tr('Accueil', 'Home'),
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
      ),
      if (session.can(AppPermission.salesView))
        LkNavDestination(
          label: S.tr('Vente', 'Sell'),
          icon: Icons.shopping_bag_outlined,
          activeIcon: Icons.shopping_bag_rounded,
        ),
      if (session.can(AppPermission.stockView))
        LkNavDestination(
          label: S.tr('Stock', 'Stock'),
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
        ),
      if (session.can(AppPermission.aiUse))
        LkNavDestination(
          label: S.tr('Assistant', 'Assistant'),
          icon: Icons.auto_awesome_outlined,
          activeIcon: Icons.auto_awesome_rounded,
        ),
    ];
    final tabKey = _tabForPath.entries
        .where((e) => location == e.key || location.startsWith('${e.key}/'))
        .toList()
        .firstOrNull
        ?.value;
    final canSell = session.can(AppPermission.salesView);
    final canStock = session.can(AppPermission.stockView);
    final canAi = session.can(AppPermission.aiUse);
    final active = activeIndexFor(
      tabKey: tabKey,
      canSell: canSell,
      canStock: canStock,
      canAi: canAi,
    );

    final online = ref.watch(connectivityOnlineProvider).valueOrNull ?? false;
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final name =
        session.user?.fullName.split(' ').first ??
        S.tr('commerçant', 'merchant');
    final title = location == '/home'
        ? S.tr('Bonjour, $name', 'Hello, $name')
        : switch (tabKey) {
            1 => S.tr('Vente', 'Sell'),
            2 => S.tr('Stock', 'Stock'),
            3 => S.tr('Assistant', 'Assistant'),
            _ => S.more,
          };
    final shopName = session.business?.name ?? 'Lynkstor';
    final initials = shopName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final content = Column(
      children: [
        DavexAppHeader(
          title: title,
          subtitle: shopName,
          avatarInitials: initials.isEmpty ? 'LS' : initials,
          showCart: canSell,
          cartCount: ref.watch(davexCartBadgeProvider),
          onCart: () => context.go('/vente'),
          notificationCount:
              ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0,
          onNotification: () => context.push('/notifications'),
          onMenu: () => context.go('/more'),
          online: online,
          pendingSync: pendingSync,
          onStatusTap: () =>
              _showConnectionSheet(context, online: online, pending: pendingSync),
        ),
        const KumbaSubscriptionBanner(),
        Expanded(child: child),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final showNav = destinations.length > 1;
        final paths = <String>[
          '/home',
          if (canSell) '/vente',
          if (canStock) '/stock',
          if (canAi) '/ai',
        ];
        return Scaffold(
          body: Row(
            children: [
              if (wide && showNav)
                NavigationRail(
                  selectedIndex: active < paths.length ? active : 0,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) => context.go(paths[index]),
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.activeIcon),
                        label: Text(item.label),
                      ),
                  ],
                ),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: wide || !showNav
              ? null
              : LynkstorBottomNavigation(
                  destinations: destinations,
                  selectedIndex: active < paths.length ? active : 0,
                  onDestinationSelected: (index) => context.go(paths[index]),
                ),
        );
      },
    );
  }

  /// Fiche de détail condensée, ouverte par l'icône d'état du header.
  /// Information 100 % réelle (connectivité + file d'attente) — aucune action
  /// bidon : l'app est offline-first, la synchro se reprend seule.
  void _showConnectionSheet(
    BuildContext context, {
    required bool online,
    required int pending,
  }) {
    final p = LkPalette.of(context);
    showDavexSheet<void>(
      context,
      title: S.tr('Synchronisation', 'Sync'),
      initialChildSize: 0.5,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _StatusRow(
            color: online ? p.successFg : p.warningFg,
            icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            title: online
                ? S.tr('Vous êtes en ligne', 'You are online')
                : S.tr('Vous êtes hors ligne', 'You are offline'),
            subtitle: online
                ? S.tr(
                    'Les données partent vers le cloud automatiquement.',
                    'Data syncs to the cloud automatically.',
                  )
                : S.tr(
                    'Tout est enregistré sur cet appareil et se synchronisera au retour du réseau.',
                    'Everything is saved on this device and syncs when the network returns.',
                  ),
          ),
          const SizedBox(height: 18),
          _StatusRow(
            color: pending > 0 ? p.warningFg : p.textSecondary,
            icon: Icons.sync_rounded,
            title: pending > 0
                ? S.tr(
                    '$pending opération(s) en attente',
                    '$pending operation(s) pending',
                  )
                : S.tr(
                    'Aucune opération en attente',
                    'Nothing pending',
                  ),
            subtitle: S.tr(
              'Synchronisées dès que la connexion revient.',
              'Synced as soon as the connection returns.',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
