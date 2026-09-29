import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/permissions/permissions.dart';
import '../../design_system/components/lynkstor_bottom_navigation.dart';
import '../../design_system/components/lynkstor_header.dart';
import '../../design_system/components/kumba_states.dart';
import '../../design_system/components/kumba_subscription_banner.dart';
import '../../design_system/components/sync_indicator.dart';
import '../../l10n/app_strings.dart';

/// Shell DAVEX — 4 onglets loi produit : Accueil / Vente / Stock / Assistant.
///
/// Jamais de cinquième onglet : Notifications, Réglages, Rapports et la
/// création de boutique passent par le menu (bouton ☰ de l'en-tête).
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.child});
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
    // Index d'onglet actif depuis le chemin (les sous-routes de /vente
    // comptent pour l'onglet Vente, etc.) aligné sur [destinations].
    final tabKey =
        _tabForPath.entries
            .where((e) => location == e.key || location.startsWith('${e.key}/'))
            .toList()
            .firstOrNull
            ?.value;
    final active = activeIndexFor(
      tabKey: tabKey,
      canSell: session.can(AppPermission.salesView),
      canStock: session.can(AppPermission.stockView),
      canAi: session.can(AppPermission.aiUse),
    );

    final online = ref.watch(connectivityOnlineProvider).valueOrNull ?? false;
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final transport = !online
        ? LkSyncTransport.local
        : pending > 0
        ? LkSyncTransport.wifi
        : LkSyncTransport.cloud;
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
    final content = Column(
      children: [
        LynkstorHeader(
          title: title,
          shopName: session.business?.name ?? 'Lynkstor',
          subtitle: session.business?.name ?? 'Lynkstor',
          status: SyncIndicator(transport: transport),
          actions: [
            LynkstorHeaderAction(
              icon: Icons.search,
              label: S.tr('Rechercher', 'Search'),
              onTap: () => context.push('/search'),
            ),
            LynkstorHeaderAction(
              icon: Icons.notifications_outlined,
              label: S.tr('Notifications', 'Notifications'),
              count:
                  ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0,
              onTap: () => context.push('/notifications'),
            ),
            LynkstorHeaderAction(
              icon: Icons.menu,
              label: S.tr('Ouvrir le menu', 'Open menu'),
              onTap: () => context.go('/more'),
            ),
          ],
        ),
        if (!online) KumbaOfflineBanner(pendingCount: pending),
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
          if (session.can(AppPermission.salesView)) '/vente',
          if (session.can(AppPermission.stockView)) '/stock',
          if (session.can(AppPermission.aiUse)) '/ai',
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
}

/// Onglet par défaut au lancement : Vente (écran de travail du commerçant),
/// retombe sur Accueil si la session n'a pas la permission de vente.
String launchTabPathFor(bool canSell) => canSell ? '/vente' : '/home';

/// Index de l'onglet surligné dans [destinations] (Accueil occupe toujours
/// l'index 0 ; Vente/Stock/Assistant ne sont listés que si la permission
/// correspondante existe). [tabKey] vient de [_tabForPath] (0-3, nullable).
int activeIndexFor({
  required int? tabKey,
  required bool canSell,
  required bool canStock,
  required bool canAi,
}) {
  if (tabKey == null || tabKey == 0) return 0;
  var i = 1; // après Accueil
  if (canSell) {
    if (tabKey == 1) return i;
    i++;
  }
  if (canStock) {
    if (tabKey == 2) return i;
    i++;
  }
  if (canAi) {
    if (tabKey == 3) return i;
  }
  return 0; // onglet non accessible : retombe sur Accueil
}
