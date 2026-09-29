// Test de diagnostic (jetable) : rend DavexAccueilScreen avec une DB in-memory
// pour capturer la stack complète de l'erreur « BoxConstraints forces an
// infinite height » observée sur l'Infinix.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/dashboard/davex_accueil_screen.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';
import 'package:kumba_business/shared/services/report_service.dart';
import 'package:kumba_business/shared/services/session_service.dart';
import 'package:mocktail/mocktail.dart';

class MockBusiness extends Mock implements Business {}

class MockUser extends Mock implements User {}

class MockSession extends Mock implements SessionService {}

class FixtureSession extends SessionNotifier {
  FixtureSession(SessionState initial) : super(MockSession()) {
    state = initial;
  }
}

class FakeReports extends ReportService {
  FakeReports({required super.db});

  @override
  Future<DailyReport> daily(String businessId, {DateTime? day}) async => DailyReport(
    sold: 128500,
    collected: 96500,
    credit: 32000,
    expenses: 12500,
    profitEstimate: 84000,
    salesCount: 18,
    expectedCash: 84000,
  );

  @override
  Future<Map<String, double>> stockValue(String businessId) async => {
    'cost_value': 0,
    'sale_value': 0,
    'low_count': 0,
    'out_count': 0,
    'product_count': 0,
  };
}

void main() {
  testWidgets('davex accueil renders without layout errors', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final business = MockBusiness();
    when(() => business.id).thenReturn('ui-business');
    when(() => business.name).thenReturn('Chez Amina');
    when(() => business.city).thenReturn('Abidjan');
    final user = MockUser();
    when(() => user.role).thenReturn('owner');
    when(() => user.fullName).thenReturn('Amina Diallo');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            (ref) => FixtureSession(
              SessionState(
                isLoading: false,
                isAuthenticated: true,
                needsOnboarding: false,
                business: business,
                user: user,
                subscription: SubscriptionInfo.demoValue,
              ),
            ),
          ),
          reportServiceProvider.overrideWith((ref) => FakeReports(db: db)),
          connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
          pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const DavexAccueilScreen(),
        ),
      ),
    );
    // Laisse le FutureProvider se résoudre + un frame de layout.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Chez Amina'), findsOneWidget);
  });
}
