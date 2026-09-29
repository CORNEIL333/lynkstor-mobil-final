import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/dashboard/dashboard_screen.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';
import 'package:kumba_business/shared/services/customer_service.dart';
import 'package:kumba_business/shared/services/product_service.dart';
import 'package:kumba_business/shared/services/report_service.dart';
import 'package:kumba_business/shared/services/session_service.dart';
import 'package:kumba_business/shared/widgets/shell_scaffold.dart';

class MockProducts extends Mock implements ProductService {}
class MockCustomers extends Mock implements CustomerService {}
class MockReports extends Mock implements ReportService {}
class MockSession extends Mock implements SessionService {}
class MockBusiness extends Mock implements Business {}
class MockUser extends Mock implements User {}

class FixtureSession extends SessionNotifier {
  FixtureSession(SessionState initial) : super(MockSession()) { state = initial; }
}

class UiFixture {
  UiFixture({String role = 'owner', this.performance = true}) {
    GoogleFonts.config.allowRuntimeFetching = false;
    when(() => business.id).thenReturn('ui-business');
    when(() => business.name).thenReturn('Chez Amina');
    when(() => user.role).thenReturn(role);
    when(() => user.fullName).thenReturn('Amina Diallo');
    when(() => products.list('ui-business', lowStock: true)).thenAnswer((_) async => []);
    when(() => products.list('ui-business')).thenAnswer((_) async => []);
    when(() => customers.list('ui-business')).thenAnswer((_) async => []);
    when(() => reports.daily('ui-business')).thenAnswer((_) async => DailyReport(
      sold: 128500, collected: 96500, credit: 32000, expenses: 12500,
      profitEstimate: 84000, salesCount: 18, expectedCash: 84000,
    ));
  }
  final bool performance;
  final business = MockBusiness();
  final user = MockUser();
  final products = MockProducts();
  final customers = MockCustomers();
  final reports = MockReports();

  List<Override> get overrides => [
    sessionProvider.overrideWith((ref) => FixtureSession(SessionState(
      isLoading: false, isAuthenticated: true, needsOnboarding: false,
      business: business, user: user, performanceMode: performance,
      subscription: SubscriptionInfo.demoValue,
    ))),
    productServiceProvider.overrideWithValue(products),
    customerServiceProvider.overrideWithValue(customers),
    reportServiceProvider.overrideWithValue(reports),
    connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
    pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
    unreadNotificationCountProvider.overrideWith((ref) => Stream.value(2)),
  ];

  GoRouter router({Widget home = const DashboardScreen(), bool shell = true}) => GoRouter(
    initialLocation: '/home',
    routes: [
      if (shell) ShellRoute(builder: (_, __, child) => ShellScaffold(child: child),
        routes: [GoRoute(path: '/home', builder: (_, __) => home)])
      else GoRoute(path: '/home', builder: (_, __) => home),
      for (final path in ['/sale/new', '/debts', '/expenses', '/sales', '/stock', '/products', '/customers', '/reports', '/ai', '/more'])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text('route:$path'))),
    ],
  );

  Widget app(GoRouter router, {bool dark = false, double scale = 1, bool reduce = true, Key? captureKey}) {
    return ProviderScope(overrides: overrides, child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(), darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reduce),
        child: RepaintBoundary(key: captureKey, child: child!),
      ),
    ));
  }
}
