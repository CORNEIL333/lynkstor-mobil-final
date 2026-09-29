import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/design_system/components/kumba_button.dart';
import 'package:kumba_business/design_system/components/kumba_states.dart';

void main() {
  testWidgets('KumbaButton shows label and reacts', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: KumbaButton(
            label: 'Valider la vente',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Valider la vente'), findsOneWidget);
    await tester.tap(find.text('Valider la vente'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('KumbaEmptyState shows action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: KumbaEmptyState(
            title: 'Aucune vente',
            actionLabel: 'Nouvelle vente',
            onAction: null,
          ),
        ),
      ),
    );
    expect(find.text('Aucune vente'), findsOneWidget);
  });

  testWidgets('KumbaStatusBadge renders label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KumbaStatusBadge(label: 'Hors ligne')),
      ),
    );
    expect(find.text('Hors ligne'), findsOneWidget);
  });
}
