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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _MockSessionService sessionService;
  late AppDatabase db;
  var bootstrapCalls = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = createTestDatabase();
    sessionService = _MockSessionService();
    bootstrapCalls = 0;

    when(() => sessionService.bootstrap()).thenAnswer((_) async {
      bootstrapCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return const BootstrapResult(
        isAuthenticated: false,
        needsOnboarding: true,
        subscription: SubscriptionInfo.unknownValue,
      );
    });
    when(
      () => sessionService.refreshSubscriptionFromCloud(),
    ).thenAnswer((_) async => SubscriptionInfo.unknownValue);
    when(() => sessionService.lock()).thenAnswer((_) async {});
    when(() => sessionService.logout()).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWith((ref) => db),
        sessionServiceProvider.overrideWithValue(sessionService),
        syncEngineProvider.overrideWith((ref) {
          final engine = SyncEngine(db);
          ref.onDispose(engine.dispose);
          return engine;
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'routerProvider keeps the same GoRouter across session updates',
    () async {
      final first = container.read(routerProvider);

      await container.read(sessionProvider.notifier).bootstrap();
      final afterBootstrap = container.read(routerProvider);

      await container.read(sessionProvider.notifier).lock();
      final afterLock = container.read(routerProvider);

      await container.read(sessionProvider.notifier).refresh();
      final afterRefresh = container.read(routerProvider);

      expect(identical(first, afterBootstrap), isTrue);
      expect(identical(first, afterLock), isTrue);
      expect(identical(first, afterRefresh), isTrue);
    },
  );

  test('concurrent bootstrap calls SessionService once', () async {
    final notifier = container.read(sessionProvider.notifier);
    final a = notifier.bootstrap();
    final b = notifier.bootstrap();
    final c = notifier.bootstrap();

    expect(identical(a, b), isTrue);
    expect(identical(a, c), isTrue);

    await Future.wait([a, b, c]);
    expect(bootstrapCalls, 1);
    expect(container.read(sessionProvider).isLoading, isFalse);
    expect(container.read(sessionProvider).needsOnboarding, isTrue);
  });

  test('refresh does not set isLoading (no splash flash)', () async {
    final notifier = container.read(sessionProvider.notifier);

    notifier.state = const SessionState(
      isLoading: false,
      isAuthenticated: true,
      needsOnboarding: false,
    );

    final refreshFuture = notifier.refresh();
    expect(container.read(sessionProvider).isLoading, isFalse);
    await refreshFuture;
    expect(container.read(sessionProvider).isLoading, isFalse);
  });

  test('bootstrap sets isLoading then clears it', () async {
    final notifier = container.read(sessionProvider.notifier);
    expect(container.read(sessionProvider).isLoading, isTrue);

    final future = notifier.bootstrap();
    expect(container.read(sessionProvider).isLoading, isTrue);
    await future;
    expect(container.read(sessionProvider).isLoading, isFalse);
  });
}
