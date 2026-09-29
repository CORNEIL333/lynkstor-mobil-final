import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kumba_business/app/providers.dart';
import 'package:kumba_business/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to onboarding or splash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const KumbaApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    // Splash or onboarding should render without crash
    expect(find.byType(MaterialApp), findsNothing); // MaterialApp.router
    expect(find.byType(KumbaApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    // After bootstrap, welcome or lock text likely present
    final welcome = find.textContaining('Bienvenue');
    final pin = find.textContaining('PIN');
    expect(welcome.evaluate().isNotEmpty || pin.evaluate().isNotEmpty || find.textContaining('KUMBA').evaluate().isNotEmpty, isTrue);
  });
}
