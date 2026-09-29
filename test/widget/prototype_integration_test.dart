import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kumba_business/core/catalog/prototype_catalogue.dart';
import 'package:kumba_business/design_system/components/lynkstor_header.dart';
import 'package:kumba_business/features/products/prototype_catalogue_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'supplier snapshots parse with unique identifiers and safe price suggestions',
    () {
      for (final source in PrototypeCatalogue.sources.keys) {
        final rows =
            jsonDecode(File('assets/catalogue/$source.json').readAsStringSync())
                as List;
        final items = rows
            .map(
              (row) =>
                  PrototypeCatalogueItem.fromJson(row as Map<String, dynamic>),
            )
            .toList();
        expect(items, isNotEmpty);
        expect(items.map((item) => item.id).toSet().length, items.length);
        for (final item in items) {
          if (item.needsReview || item.priceStatus != 'published') {
            expect(item.suggestedPrice, isNull);
          }
        }
        expect(
          items.first.matches(items.first.name, items.first.category),
          isTrue,
        );
        expect(items.first.matches('no-matching-product-xyz', null), isFalse);
      }
    },
  );

  for (final width in [320.0, 1000.0]) {
    testWidgets('prototype header actions work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LynkstorHeader(
              title: 'Bonjour, commerçant',
              subtitle: 'Une boutique avec un nom très long · Hors ligne',
              shopName: 'Boutique Démo',
              actions: [
                LynkstorHeaderAction(
                  icon: Icons.menu,
                  label: 'Menu',
                  onTap: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Menu'));
      expect(opened, isTrue);
    });
  }

  testWidgets(
    'catalogue search hands selected product to the existing form route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final items = await tester.runAsync(
        () => PrototypeCatalogue.load('boulangerie'),
      );
      expect(items, isNotEmpty);
      final router = GoRouter(
        initialLocation: '/catalogue',
        routes: [
          GoRoute(
            path: '/catalogue',
            builder: (_, __) =>
                PrototypeCatalogueScreen(loadCatalogue: (_) async => items!),
          ),
          GoRoute(
            path: '/products/new',
            builder: (_, state) => Scaffold(
              body: Text('Product: ${state.uri.queryParameters['name']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Beignet fourré');
      await tester.pumpAndSettle();
      expect(find.text('Beignet fourré'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Beignet fourré'));
      await tester.pumpAndSettle();
      expect(find.text('Product: Beignet fourré'), findsOneWidget);
    },
  );
}
