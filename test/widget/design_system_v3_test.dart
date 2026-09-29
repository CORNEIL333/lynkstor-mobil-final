import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kumba_business/design_system/components/lk_overlay.dart';
import 'package:kumba_business/design_system/components/lk_primitives.dart';
import 'package:kumba_business/design_system/components/lynkstor_bottom_navigation.dart';
import 'package:kumba_business/design_system/components/qr_client_order_banner.dart';
import 'package:kumba_business/design_system/components/sync_indicator.dart';

/// Harnais minimal : Material + Overlay pour les composants qui s'y adossent.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

const _destinations = <LkNavDestination>[
  LkNavDestination(
    label: 'Accueil',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  ),
  LkNavDestination(
    label: 'Vente',
    icon: Icons.shopping_bag_outlined,
    activeIcon: Icons.shopping_bag_rounded,
  ),
  LkNavDestination(
    label: 'Stock',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
  ),
  LkNavDestination(
    label: 'Assistant',
    icon: Icons.auto_awesome_outlined,
    activeIcon: Icons.auto_awesome_rounded,
  ),
];

void main() {
  group('LynkstorBottomNavigation', () {
    testWidgets('rend les 4 destinations et rapporte l index tape', (
      tester,
    ) async {
      int? tapped;
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          Align(
            alignment: Alignment.bottomCenter,
            child: LynkstorBottomNavigation(
              destinations: _destinations,
              selectedIndex: 0,
              onDestinationSelected: (i) => tapped = i,
            ),
          ),
        ),
      );

      for (final label in ['Accueil', 'Vente', 'Stock', 'Assistant']) {
        expect(find.text(label), findsOneWidget);
      }
      // Aucun 5e onglet.
      expect(find.byType(LynkstorBottomNavigation), findsOneWidget);
      expect(tester.widget<LynkstorBottomNavigation>(
        find.byType(LynkstorBottomNavigation),
      ).destinations.length, 4);

      await tester.tap(find.text('Stock'));
      await tester.pump();
      expect(tapped, 2);
    });
  });

  group('SyncIndicator', () {
    testWidgets('trois transports, libelles grand public', (tester) async {
      for (final (transport, label) in const [
        (LkSyncTransport.cloud, 'Cloud'),
        (LkSyncTransport.wifi, 'Wi-Fi'),
        (LkSyncTransport.local, 'Local'),
      ]) {
        await tester.pumpWidget(_host(SyncIndicator(transport: transport)));
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('QrClientOrderBanner', () {
    testWidgets('masquee si count <= 0', (tester) async {
      await tester.pumpWidget(
        _host(
          QrClientOrderBanner(
            count: 0,
            onSee: () {},
            autoDismissAfter: Duration.zero,
          ),
        ),
      );
      expect(find.text('Voir'), findsNothing);
    });

    testWidgets('Voir declenche onSee puis auto-dismiss apres delai', (
      tester,
    ) async {
      var saw = false;
      var dismissed = false;
      await tester.pumpWidget(
        _host(
          QrClientOrderBanner(
            count: 2,
            onSee: () => saw = true,
            onDismiss: () => dismissed = true,
            autoDismissAfter: const Duration(seconds: 8),
          ),
        ),
      );
      expect(find.text('2 nouvelles commandes en attente'), findsOneWidget);

      await tester.tap(find.text('Voir'));
      await tester.pump();
      expect(saw, isTrue);

      // Non bloquante : elle avertit le parent au bout de 8 s (le parent la
      // retire en passant count a 0 ; le widget ne se supprime pas lui-meme).
      await tester.pump(const Duration(seconds: 8));
      expect(dismissed, isTrue);
    });
  });

  group('LkButton', () {
    testWidgets('actif invoque onPressed, inactif si onPressed null', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(LkButton(label: 'Encaisser', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Encaisser'));
      await tester.pump();
      expect(taps, 1);

      await tester.pumpWidget(_host(const LkButton(label: 'Idle')));
      await tester.tap(find.text('Idle'));
      await tester.pump();
      // Aucune exception, rien a vérifier côté compteur.
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('loading affiche un indicateur et bloque', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          LkButton(label: 'Envoyer', loading: true, onPressed: () => taps++),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Envoyer'));
      await tester.pump();
      expect(taps, 0);
    });
  });

  group('LkField', () {
    testWidgets('affiche l erreur inline et la porte a l attention', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          LkField(
            label: 'Nom',
            error: 'Champ obligatoire',
            child: const TextField(),
          ),
        ),
      );
      expect(find.text('Champ obligatoire'), findsOneWidget);
    });
  });

  group('showLkToast', () {
    testWidgets('apparait en haut puis sauto-efface', (tester) async {
      final ctxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              key: ctxKey,
              builder: (context) => Align(
                alignment: Alignment.topCenter,
                child: TextButton(
                  onPressed: () => showLkToast(
                    context,
                    'Vente enregistrée',
                    tone: LkToastTone.success,
                    duration: const Duration(seconds: 3),
                  ),
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.text('Vente enregistrée'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Vente enregistrée'), findsNothing);
    });

    testWidgets('action optionnelle appelee onAction', (tester) async {
      var undone = false;
      final ctxKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              key: ctxKey,
              builder: (context) => TextButton(
                onPressed: () => showLkToast(
                  context,
                  'Ticket partagé',
                  actionLabel: 'Annuler',
                  onAction: () => undone = true,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      expect(undone, isTrue);
      expect(find.text('Ticket partagé'), findsNothing);
    });
  });
}
