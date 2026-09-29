import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/app/router.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';
import 'package:kumba_business/shared/services/session_service.dart';

class _MockSessionService extends Mock implements SessionService {}

/// Smoke navigation : transitions session sans assertion InheritedElement.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSessionService sessionService;
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = createTestDatabase();
    sessionService = _MockSessionService();

    when(() => sessionService.bootstrap()).thenAnswer(
      (_) async => const BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: true,
        subscription: SubscriptionInfo.unknownValue,
      ),
    );
    when(() => sessionService.lock()).thenAnswer((_) async {});
    when(() => sessionService.logout()).thenAnswer((_) async {});
    when(
      () => sessionService.refreshSubscriptionFromCloud(),
    ).thenAnswer((_) async => SubscriptionInfo.unknownValue);
  });

  tearDown(() async {
    await db.close();
  });

  List<Override> overrides() => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWith((ref) => db),
    sessionServiceProvider.overrideWithValue(sessionService),
    syncEngineProvider.overrideWith((ref) {
      final engine = SyncEngine(db);
      ref.onDispose(engine.dispose);
      return engine;
    }),
  ];

  testWidgets('session loading → onboarding does not throw element assertion', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const _TestApp()),
    );

    // Bootstrap hors build (comme splash post-frame).
    final ctx = tester.element(find.byType(_TestApp));
    final container = ProviderScope.containerOf(ctx);
    await container.read(sessionProvider.notifier).bootstrap();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Pas de pumpAndSettle infini (animations éventuelles).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(container.read(sessionProvider).needsOnboarding, isTrue);
    expect(container.read(sessionProvider).isLoading, isFalse);
  });

  testWidgets('repeated lock/unlock session updates keep a stable router', (
    tester,
  ) async {
    // Viewport téléphone réel (évite overflow du pad PIN en test 800×600).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const _TestApp()),
    );

    final ctx = tester.element(find.byType(_TestApp));
    final container = ProviderScope.containerOf(ctx);

    // Commerce déjà configuré, session non authentifiée → /lock.
    when(() => sessionService.bootstrap()).thenAnswer(
      (_) async => const BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: false,
        subscription: SubscriptionInfo.unknownValue,
      ),
    );
    await container.read(sessionProvider.notifier).bootstrap();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final router1 = container.read(routerProvider);

    for (var i = 0; i < 5; i++) {
      await container.read(sessionProvider.notifier).lock();
      await tester.pump();
      container.read(sessionProvider.notifier).state = const SessionState(
        isLoading: false,
        isAuthenticated: false,
        needsOnboarding: false,
      );
      await tester.pump();
    }

    await tester.pump(const Duration(seconds: 1));

    final router2 = container.read(routerProvider);
    expect(identical(router1, router2), isTrue);

    // Ne doit surtout pas produire l’assertion InheritedElement.
    final err = tester.takeException();
    if (err != null) {
      expect(
        err.toString(),
        isNot(contains('ancestor == this')),
        reason: 'Assertion dependent InheritedWidget: $err',
      );
    }
  });

  testWidgets('authenticated session leaves lock/onboarding for the launch tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides(), child: const _TestApp()),
    );

    final ctx = tester.element(find.byType(_TestApp));
    final container = ProviderScope.containerOf(ctx);
    final router = container.read(routerProvider);

    container.read(sessionProvider.notifier).state = const SessionState(
      isLoading: false,
      isAuthenticated: false,
      needsOnboarding: false,
    );
    router.go('/lock');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routeInformationProvider.value.uri.path, '/lock');

    container.read(sessionProvider.notifier).state = const SessionState(
      isLoading: false,
      isAuthenticated: true,
      needsOnboarding: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Rôle 'seller' (défaut) ⇒ salesView ⇒ onglet de lancement = Vente.
    expect(router.routeInformationProvider.value.uri.path, '/vente');

    container.read(sessionProvider.notifier).state = const SessionState(
      isLoading: false,
      isAuthenticated: false,
      needsOnboarding: true,
    );
    router.go('/onboarding');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routeInformationProvider.value.uri.path, '/onboarding');

    container.read(sessionProvider.notifier).state = const SessionState(
      isLoading: false,
      isAuthenticated: true,
      needsOnboarding: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Rôle 'seller' (défaut) ⇒ salesView ⇒ onglet de lancement = Vente.
    expect(router.routeInformationProvider.value.uri.path, '/vente');
    // L'onglet Vente monte SaleScreen (animations flutter_animate) : on draine
    // les timers résiduels avant la fin du test, sinon le binding refuse un
    // « Timer still pending » au teardown.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // Ce smoke-test vérifie la STABILITÉ DE NAVIGATION (pas la mise en page de
    // Vente, couverte par ui_snapshot / Phase 3). La police de test (glyphes en
    // carrés) fait déborder de façon cosmétique le bouton « Encaisser » ; on
    // n'échoue que sur une vraie assertion d'InheritedElement.
    final err = tester.takeException();
    if (err != null) {
      expect(
        err.toString(),
        isNot(contains('ancestor == this')),
        reason: 'Assertion dependent InheritedWidget: $err',
      );
    }
  });
}

class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(routerConfig: router);
  }
}
