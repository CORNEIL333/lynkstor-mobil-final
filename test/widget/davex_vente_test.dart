// Test de régression a8 : DavexVenteScreen (recréé depuis la maquette) —
// rendu catalogue, ajout d'une ligne libre hors catalogue, passage au panier.
// Données RÉELLES via Drift in-memory (aucun produit seeded → état vide
// authentique puis saisie adHoc réelle).
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/sales/davex_cart.dart';
import 'package:kumba_business/features/sales/davex_vente_screen.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';
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

void main() {
  testWidgets('vente: catalogue vide → ligne libre → panier', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final business = MockBusiness();
    when(() => business.id).thenReturn('ui-business');
    when(() => business.name).thenReturn('Boutique Amina');
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
          connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
          pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const DavexVenteScreen(embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    // Vue catalogue maquette : titre de section + carte pointillée.
    expect(find.textContaining('Produits pour'), findsOneWidget);
    expect(find.text('Produit hors catalogue'), findsOneWidget);
    expect(find.text('Aucun produit'), findsOneWidget);

    // Modale hors catalogue → ligne libre réelle dans le panier.
    await tester.tap(find.text('Produit hors catalogue'));
    await tester.pumpAndSettle();
    expect(find.text('Produit hors catalogue'), findsWidgets); // carte + titre sheet

    final sheet = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(BottomSheet),
    );
    expect(sheet, findsWidgets);
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    // Champs : désignation, prix, qté, unité.
    await tester.enterText(fields.at(0), 'Cahier 200 pages');
    await tester.enterText(fields.at(1), '750');
    await tester.pump();
    await tester.tap(find.text('Ajouter au panier'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Barre « VOIR LE PANIER » apparie (panier non vide).
    expect(find.text('VOIR LE PANIER'), findsOneWidget);

    // Passage en vue panier plein écran.
    await tester.tap(find.text('VOIR LE PANIER'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cahier 200 pages'), findsOneWidget);
    expect(find.textContaining('Total Net'), findsOneWidget);
    expect(find.text('750 FCFA'), findsWidgets);
  });

  testWidgets('vente: badge du provider panier suit les articles',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final business = MockBusiness();
    when(() => business.id).thenReturn('ui-business');
    when(() => business.name).thenReturn('Boutique');
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
          connectivityOnlineProvider.overrideWith((ref) => Stream.value(true)),
          pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    final ctx = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox).first),
    );
    expect(ctx.read(davexCartBadgeProvider), 0);
    ctx.read(davexCartProvider.notifier).addAdHoc(
          name: 'Stylo',
          unitPrice: 200,
          quantity: 3,
          unit: 'pièce',
        );
    expect(ctx.read(davexCartBadgeProvider), 3);
  });
}
