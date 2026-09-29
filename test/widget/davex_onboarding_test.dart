import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/onboarding/davex_onboarding_screen.dart';
import 'package:kumba_business/l10n/app_strings.dart';

/// Test de parcours de l'onboarding recréé (a11) : la maquette ne change
/// rien au contrat réel — sans politique d'activation, la wizard fait 3
/// étapes (identité → secteur → sécurité) et AUCUNE étape de code
/// d'activation n'apparaît. On vérifie aussi les validations réelles
/// (champs requis, mot de passe ≥ 8) qui bloquent la création.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configuration de test : pas de code agent requis', () {
    expect(AppConfig.requireAgentActivationCode, isFalse);
  });

  testWidgets('wizard complète : identité → secteur → sécurité, sans code', (
    tester,
  ) async {
    S.currentLanguage = 'fr';
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 1200),
            disableAnimations: true,
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(performanceMode: true),
            home: const DavexOnboardingScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Accueil : entrée principale « Créer mon commerce » (pas d'activation).
    expect(find.text('Créer mon commerce'), findsOneWidget);
    expect(find.text('Activer mon commerce'), findsNothing);
    await tester.tap(find.text('Créer mon commerce'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Étape 1 / 3 : identité. Aucune référence au code d'activation.
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(find.text('Présentez votre commerce'), findsOneWidget);
    expect(find.text('Code d’activation'), findsNothing);

    // Champs requis vides → erreur réelle, on reste à l'étape 1.
    var cta = find.text('Continuer');
    await tester.ensureVisible(cta);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('Nom du commerce, propriétaire et téléphone sont requis.'),
      findsOneWidget,
    );

    // Renseigne nom / propriétaire / téléphone (3 premiers TextField).
    for (final index in [0, 1, 2]) {
      final field = find.byType(TextField).at(index);
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byType(TextField).at(0), 'Boutique Test');
    await tester.enterText(find.byType(TextField).at(1), 'Paul Loge');
    await tester.enterText(find.byType(TextField).at(2), '699112233');
    cta = find.text('Continuer');
    await tester.ensureVisible(cta);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Étape 2 / 3 : grille secteurs (8 secteurs réels, pas les 9 de la
    // maquette) + résumé informatif des modules du secteur sélectionné.
    expect(find.text('Étape 2 sur 3'), findsOneWidget);
    expect(find.text('Boutique générale'), findsOneWidget);
    expect(find.text('Supérette'), findsOneWidget);
    expect(find.text('Salon'), findsOneWidget);
    // Boutique générale = 11 modules (SectorModules.forSector).
    expect(find.text('11 modules inclus'), findsOneWidget);

    await tester.tap(find.text('Supérette'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('11 modules inclus'), findsOneWidget);
    expect(find.text('Caisse'), findsWidgets);

    cta = find.text('Continuer');
    await tester.ensureVisible(cta);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Étape 3 / 3 : sécurité — mot de passe trop court → erreur réelle,
    // la création (BusinessCreationInput) n'est jamais tentée.
    expect(find.text('Étape 3 sur 3'), findsOneWidget);
    expect(find.text('Protégez votre accès'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'abc123');
    final create = find.text('Créer le commerce');
    await tester.ensureVisible(create);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('Le mot de passe doit contenir au moins 8 caractères.'),
      findsOneWidget,
    );
  });
}
