import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/config/app_config.dart';
import 'package:kumba_business/core/theme/app_theme.dart';
import 'package:kumba_business/features/onboarding/davex_onboarding_screen.dart';
import 'package:kumba_business/l10n/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trial panel does not require an agent activation code', () {
    expect(AppConfig.requireAgentActivationCode, isFalse);
  });

  testWidgets('creating a business never asks for an activation key', (
    tester,
  ) async {
    S.currentLanguage = 'fr';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
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

    expect(find.text('Activer mon commerce'), findsNothing);
    expect(find.text('J’ai reçu un code Lynkstor'), findsNothing);
    expect(find.text('Créer mon commerce'), findsOneWidget);

    await tester.tap(find.text('Créer mon commerce'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Code d’activation'), findsNothing);
    expect(find.text('Vérifier le code'), findsNothing);
    expect(find.text('Activez cet appareil'), findsNothing);
    expect(find.textContaining('KMB-'), findsNothing);
  });
}
