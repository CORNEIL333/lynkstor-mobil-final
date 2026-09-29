// Test widget DavexAssistantScreen (a10) -
// rendu avec donnees REELLES (Drift in-memory) :
// 1. message d'accueil personnalise (prenom utilisateur),
// 2. banniere Carnet de Dette avec total client balance > 0,
// 3. puces de suggestions (5 chips),
// 4. barre de saisie visible,
// 5. tap sur puce -> reponse ancoree locale (source 'local', pas de reseau).
import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/ai_assistant/davex_assistant_screen.dart';
import 'package:kumba_business/features/ai_assistant/data/lynk_brain_service.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';
import 'package:kumba_business/shared/services/session_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockBusiness extends Mock implements Business {}
class MockUser extends Mock implements User {}
class MockSession extends Mock implements SessionService {}

class FixtureSession extends SessionNotifier {
  FixtureSession(SessionState initial) : super(MockSession()) {
    state = initial;
  }
}

class _UnconfiguredBrain extends LynkBrainService {
  _UnconfiguredBrain() : super(endpoint: '');
}

Future<void> _pumpAssistant(
  WidgetTester tester,
  AppDatabase db,
  SharedPreferences prefs,
) async {
  final business = MockBusiness();
  when(() => business.id).thenReturn('test-business');
  when(() => business.name).thenReturn('Boutique Test');
  when(() => business.city).thenReturn('Abidjan');

  final user = MockUser();
  when(() => user.id).thenReturn('test-user');
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
        connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
        lynkBrainProvider.overrideWithValue(_UnconfiguredBrain()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: DavexAssistantScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _seedBusiness(AppDatabase db) => db
    .into(db.businesses)
    .insert(
      BusinessesCompanion.insert(
        id: 'test-business',
        name: 'Boutique Test',
        ownerName: 'Amina Diallo',
        phone: '690000000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

Future<void> _seedDebtor(AppDatabase db) => db
    .into(db.customers)
    .insert(
      CustomersCompanion.insert(
        id: 'cust-owe',
        businessId: 'test-business',
        name: 'Moussa Traore',
        balance: const Value(47300),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    await _seedBusiness(db);
    await _seedDebtor(db);
  });

  tearDown(() async => db.close());

  testWidgets('assistant : accueil + chips + banniere dette visible', (
    tester,
  ) async {
    await _pumpAssistant(tester, db, prefs);

    expect(find.textContaining('Amina'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.textContaining('47'), findsWidgets);

    expect(find.textContaining('chiffre'), findsWidgets);

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('assistant : tap puce CA -> reponse ancoree locale (source: local)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAssistant(tester, db, prefs);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final chip = find.textContaining('chiffre');
    expect(chip, findsWidgets);
    await tester.tap(chip.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.textContaining('Calcul local'), findsWidgets);
  });
}
