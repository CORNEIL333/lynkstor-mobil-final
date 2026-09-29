import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/permissions/permissions.dart';
import '../features/ai_assistant/davex_assistant_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/authentication/pin_lock_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/davex_accueil_screen.dart';
import '../features/debts/debts_screen.dart';
import '../features/deliveries/deliveries_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/invoices/invoices_screen.dart';
import '../features/onboarding/davex_onboarding_screen.dart';
import '../features/onboarding/davex_splash_screen.dart';
import '../features/onboarding/join_business_screen.dart';
import '../features/onboarding/restore_onboarding_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/products/product_form_screen.dart';
import '../features/products/products_screen.dart';
import '../features/products/sector_catalog_screen.dart';
import '../features/products/prototype_catalogue_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/quotes/quotes_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/sales/receipt_screen.dart';
import '../features/sales/return_receipt_screen.dart';
import '../features/sales/sale_return_screen.dart';
import '../features/sales/sales_list_screen.dart';
import '../features/sales/davex_vente_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/trial_analytics_screen.dart';
import '../features/stock/davex_stock_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import '../shared/widgets/permission_gate.dart';
import '../shared/widgets/davex_shell.dart';
import '../shared/widgets/shell_scaffold.dart';
import '../shared/services/analytics_service.dart';
import 'providers.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

Widget _gate(AppPermission p, Widget child, {String? module}) =>
    PermissionGate(permission: p, module: module, child: child);

/// GoRouter stable : **ne pas** `ref.watch(sessionProvider)` ici.
///
/// `watch` recréait un nouveau [GoRouter] à chaque tick de session (bootstrap,
/// lock, abonnement…). Le navigateur et les [Element] restaient liés à l’ancien
/// routeur → assertion Flutter :
/// `ancestor == this` (dependent hors de l’InheritedWidget).
///
/// Pattern correct : un seul GoRouter + [refreshListenable] + `ref.read` dans
/// [redirect].
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  // IMPORTANT : ne jamais notifier GoRouter pendant le frame où Riverpod
  // rebuild les InheritedWidgets (Theme, MediaQuery, ProviderScope…).
  // Un refresh synchrone ici provoque :
  //   Failed assertion: ancestor == this (dependent hors de l'arbre).
  // On décale la re-évaluation des redirects après le paint.
  var refreshScheduled = false;
  ref.listen(sessionProvider, (_, __) {
    if (refreshScheduled) return;
    refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshScheduled = false;
      // Provider peut être disposé entre-temps.
      try {
        refresh.value++;
      } catch (_) {}
    });
  });

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    observers: [_AnalyticsRouteObserver()],
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      if (session.isLoading && loc != '/splash') return '/splash';
      if (!session.isLoading && loc == '/splash') {
        if (session.needsOnboarding) return '/onboarding';
        if (!session.isAuthenticated) return '/lock';
        return launchTabPathFor(session.can(AppPermission.salesView));
      }
      final isEntryRoute =
          loc == '/lock' ||
          loc.startsWith('/onboarding') ||
          loc.startsWith('/join') ||
          loc.startsWith('/restore');
      if (!session.isLoading &&
          session.isAuthenticated &&
          !session.needsOnboarding &&
          isEntryRoute) {
        return launchTabPathFor(session.can(AppPermission.salesView));
      }
      if (!session.isLoading &&
          session.needsOnboarding &&
          !loc.startsWith('/onboarding') &&
          !loc.startsWith('/join') &&
          !loc.startsWith('/restore')) {
        return '/onboarding';
      }
      if (!session.isLoading &&
          !session.needsOnboarding &&
          !session.isAuthenticated &&
          loc != '/lock' &&
          !loc.startsWith('/onboarding') &&
          !loc.startsWith('/join') &&
          !loc.startsWith('/restore')) {
        return '/lock';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => NoTransitionPage<void>(
          key: state.pageKey,
          // Splash recréé depuis la maquette (a11) ; l'ancien SplashScreen est
          // déréférencé mais reste sur disque. Logique de boot inchangée.
          child: const DavexSplashScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) => NoTransitionPage<void>(
          key: state.pageKey,
          // Onboarding recréé depuis la maquette (a11) ; logique d'activation
          // et de création BusinessCreationInput identique à OnboardingShell.
          child: const DavexOnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/join',
        pageBuilder: (_, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const JoinBusinessScreen(),
        ),
      ),
      GoRoute(
        path: '/restore',
        pageBuilder: (_, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const RestoreOnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/lock',
        pageBuilder: (_, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const PinLockScreen(),
        ),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        pageBuilder: (context, state, child) => NoTransitionPage<void>(
          key: state.pageKey,
          child: DavexShell(child: child),
        ),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DavexAccueilScreen()),
          // Onglet Vente : l'écran de encaissement lui-même (écran de
          // lancement du commerçant), intégré au shell sans son chrome propre.
          // Recréé depuis la maquette (DavexVenteScreen) ; l'ancien
          // SaleScreen reste sur disque (fixtures de tests) mais n'est
          // plus référencé.
          GoRoute(
            path: '/vente',
            builder: (_, __) => _gate(
              AppPermission.salesView,
              const DavexVenteScreen(embedded: true),
              module: 'pos',
            ),
          ),
          GoRoute(
            path: '/sales',
            builder: (_, __) => _gate(
              AppPermission.salesView,
              const SalesListScreen(),
              module: 'pos',
            ),
          ),
          GoRoute(
            path: '/stock',
            // Onglet Stock : écran recréé depuis la maquette
            // (DavexStockScreen) ; l'ancien StockScreen reste sur disque
            // (fixtures de tests) mais n'est plus référencé.
            builder: (_, __) => _gate(
              AppPermission.stockView,
              const DavexStockScreen(),
              module: 'stock',
            ),
          ),
          GoRoute(
            path: '/more',
            builder: (_, __) => const SettingsScreen(isMoreMenu: true),
          ),
          GoRoute(
            path: '/ai',
            // Onglet Assistant : écran recréé depuis la maquette
            // (DavexAssistantScreen) ; l'ancien AiAssistantScreen reste sur
            // disque mais n'est plus référencé.
            builder: (_, __) => _gate(
              AppPermission.aiUse,
              const DavexAssistantScreen(),
              module: 'ia',
            ),
          ),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        ],
      ),
      GoRoute(
        path: '/sale/new',
        // Vente est désormais un onglet du shell ; on redirige l'ancienne
        // route de creation de vente vers l'onglet /vente.
        redirect: (_, __) => '/vente',
      ),
      GoRoute(
        path: '/sale/receipt/:id',
        builder: (_, state) => _gate(
          AppPermission.salesView,
          ReceiptScreen(saleId: state.pathParameters['id']!),
          module: 'pos',
        ),
      ),
      GoRoute(
        path: '/sale/return/:id',
        builder: (_, state) =>
            SaleReturnScreen(saleId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sale/return/receipt/:id',
        builder: (_, state) => _gate(
          AppPermission.salesView,
          ReturnReceiptScreen(returnId: state.pathParameters['id']!),
          module: 'pos',
        ),
      ),
      GoRoute(
        path: '/products',
        builder: (_, __) => _gate(
          AppPermission.stockView,
          const ProductsScreen(),
          module: 'stock',
        ),
      ),
      GoRoute(
        path: '/products/catalog',
        builder: (_, __) =>
            _gate(AppPermission.productsManage, const SectorCatalogScreen()),
      ),
      GoRoute(
        path: '/products/supplier-catalogues',
        builder: (_, __) => _gate(
          AppPermission.productsManage,
          const PrototypeCatalogueScreen(),
          module: 'stock',
        ),
      ),
      GoRoute(
        path: '/products/new',
        builder: (_, state) {
          final query = state.uri.queryParameters;
          return _gate(
            AppPermission.productsManage,
            ProductFormScreen(
              initialName: query['name'],
              initialPrice: double.tryParse(query['price'] ?? ''),
              initialUnit: query['unit'],
              sourceSaleId: query['saleId'],
              focusSupplier: query['supplier'] == '1',
            ),
            module: 'stock',
          );
        },
      ),
      GoRoute(
        path: '/products/:id',
        builder: (_, state) => _gate(
          AppPermission.productsManage,
          ProductFormScreen(
            productId: state.pathParameters['id'],
            focusSupplier: state.uri.queryParameters['supplier'] == '1',
          ),
          module: 'stock',
        ),
      ),
      GoRoute(
        path: '/customers',
        builder: (_, __) => _gate(
          AppPermission.customersManage,
          const CustomersScreen(),
          module: 'clients',
        ),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (_, state) => _gate(
          AppPermission.customersManage,
          CustomerDetailScreen(customerId: state.pathParameters['id']!),
          module: 'clients',
        ),
      ),
      GoRoute(
        path: '/debts',
        builder: (_, __) => _gate(
          AppPermission.debtsView,
          const DebtsScreen(),
          module: 'dettes',
        ),
      ),
      GoRoute(
        path: '/expenses',
        builder: (_, __) => _gate(
          AppPermission.expensesView,
          const ExpensesScreen(),
          module: 'depenses',
        ),
      ),
      GoRoute(
        path: '/suppliers',
        builder: (_, __) => _gate(
          AppPermission.suppliersManage,
          const SuppliersScreen(),
          module: 'fournisseurs',
        ),
      ),
      GoRoute(
        path: '/purchases',
        builder: (_, __) => _gate(
          AppPermission.purchasesManage,
          const PurchasesScreen(),
          module: 'achats',
        ),
      ),
      GoRoute(
        path: '/inventory',
        builder: (_, __) => _gate(
          AppPermission.inventoryManage,
          const InventoryScreen(),
          module: 'inventaire',
        ),
      ),
      GoRoute(
        path: '/quotes',
        builder: (_, __) => _gate(
          AppPermission.quotesManage,
          const QuotesScreen(),
          module: 'devis',
        ),
      ),
      GoRoute(
        path: '/invoices',
        builder: (_, __) => _gate(
          AppPermission.invoicesManage,
          const InvoicesScreen(),
          module: 'factures',
        ),
      ),
      GoRoute(
        path: '/deliveries',
        builder: (_, __) => _gate(
          AppPermission.deliveriesManage,
          const DeliveriesScreen(),
          module: 'livraisons',
        ),
      ),
      GoRoute(
        path: '/employees',
        builder: (_, __) => _gate(
          AppPermission.employeesManage,
          const EmployeesScreen(),
          module: 'employes',
        ),
      ),
      GoRoute(
        path: '/attendance',
        builder: (_, __) => _gate(
          AppPermission.attendanceManage,
          const AttendanceScreen(),
          module: 'pointage',
        ),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, __) => _gate(
          AppPermission.reportsView,
          const ReportsScreen(),
          module: 'rapports',
        ),
      ),
      GoRoute(
        path: '/backup',
        builder: (_, __) => _gate(
          AppPermission.backupManage,
          const BackupScreen(),
          module: 'sauvegardes',
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/settings/analytics',
        builder: (_, __) => const TrialAnalyticsScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

class _AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _track(newRoute);
  }

  void _track(Route<dynamic>? route) {
    final path = route?.settings.name;
    if (path == null || path.isEmpty || path == '/splash') return;
    AppAnalytics.track('screen.viewed', properties: {'path': path});
  }
}
