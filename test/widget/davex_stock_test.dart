// Test de régression a9 : DavexStockScreen (recréé depuis la maquette) —
// rendu des données RÉELLES (Drift in-memory), ajustement staged express
// appliqué avec motif, et mouvement typé (assistant → achat → +stock).
// Chaque action doit écrire un vrai mouvement dans StockMovements.
import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/stock/davex_stock_screen.dart';
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

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db) async {
  final business = MockBusiness();
  when(() => business.id).thenReturn('ui-business');
  when(() => business.name).thenReturn('Boutique Amina');
  when(() => business.city).thenReturn('Abidjan');
  final user = MockUser();
  when(() => user.id).thenReturn('ui-user');
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
        home: const DavexStockScreen(embedded: true),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _seedBusiness(AppDatabase db) => db
    .into(db.businesses)
    .insert(
      BusinessesCompanion.insert(
        id: 'ui-business',
        name: 'Boutique Amina',
        ownerName: 'Amina Diallo',
        phone: '690000000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

void main() {
  testWidgets('stock: rendu réel → staged express appliqué avec motif', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    await _seedBusiness(db);
    await db.insertProduct(
      ProductsCompanion.insert(
        id: 'pepsi-1',
        businessId: 'ui-business',
        name: 'Pepsi 33cl',
        salePrice: const Value(500),
        costPrice: const Value(400),
        stockQty: const Value(3),
        lowStockThreshold: const Value(5),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _pumpScreen(tester, db);
    expect(tester.takeException(), isNull);

    // Données réelles : carte produit + métriques maquette.
    expect(find.text('Pepsi 33cl'), findsOneWidget);
    expect(find.text('CRITIQUE'), findsOneWidget);
    expect(find.text('BAS'), findsOneWidget);
    expect(find.text('Bas'), findsOneWidget); // badge alerte de la carte

    // Express : ±1 mis en attente (staged), RIEN n'est écrit avant motif.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Augmenter la quantité'));
      await tester.pump();
    }
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('unité(s) modifiée(s)'), findsOneWidget);
    expect(find.text('Appliquer 1 modification(s)'), findsOneWidget);

    // Sheet motif obligatoire.
    await tester.tap(find.text('Appliquer 1 modification(s)'));
    await tester.pumpAndSettle();
    final motifField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(motifField.first, 'Réception fournisseur');
    await tester.pump();
    final confirm = find.text('Appliquer 1 modification(s)').last;
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Écriture RÉELLE : stock 3 → 6 + mouvement 'adjustment' de +3.
    final product = await db.getProduct('pepsi-1');
    expect(product!.stockQty, 6);
    final movements = await (db.select(
      db.stockMovements,
    )).get();
    expect(movements, hasLength(1));
    expect(movements.single.type, 'adjustment');
    expect(movements.single.quantity, 3);
    expect(movements.single.note, 'Réception fournisseur');

    // Rechargement : l'alerte « Bas » a disparu (6 > seuil 5).
    expect(find.text('Pepsi 33cl'), findsOneWidget);
    expect(find.text('Disponible'), findsOneWidget);

    // Consommer le timer d'auto-dismiss du toast (3,2 s) avant la fin.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('stock: mouvement typé (assisté → Entrée) écrit un achat', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    await _seedBusiness(db);
    await db.insertProduct(
      ProductsCompanion.insert(
        id: 'riz-1',
        businessId: 'ui-business',
        name: 'Riz 5kg',
        salePrice: const Value(3800),
        stockQty: const Value(10),
        lowStockThreshold: const Value(5),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _pumpScreen(tester, db);
    expect(tester.takeException(), isNull);
    expect(find.text('Riz 5kg'), findsOneWidget);

    // Bascule assisté (BarChart3 maquette) → carte valorisation navy.
    await tester.tap(find.byIcon(Icons.show_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Valeur totale du stock'), findsOneWidget);

    // Mouvement typé : motif par défaut « Entrée » (type réel purchase).
    await tester.tap(find.text('+ Mouvement typé'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '10'); // quantité
    await tester.pump();
    expect(find.textContaining('10 → 20'), findsOneWidget);
    final validate = find.text('Valider le mouvement de stock');
    await tester.ensureVisible(validate);
    await tester.pumpAndSettle();
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final product = await db.getProduct('riz-1');
    expect(product!.stockQty, 20);
    final movements = await (db.select(db.stockMovements)).get();
    expect(movements, hasLength(1));
    expect(movements.single.type, 'purchase');
    expect(movements.single.quantity, 10);

    // Consommer le timer d'auto-dismiss du toast (3,2 s) avant la fin.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
