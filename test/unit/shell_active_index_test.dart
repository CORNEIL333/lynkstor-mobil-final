import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/shared/widgets/shell_scaffold.dart';

/// Régression : l'onglet surligné doit correspondre à la route courante.
/// Bug corrigé : /vente surlignait Accueil (compteur démarré à 0 alors
/// qu'Accueil occupe l'index 0 de la liste des destinations).
void main() {
  group('activeIndexFor', () {
    test('route /vente (tabKey 1) surligne Vente (index 1)', () {
      expect(
        activeIndexFor(tabKey: 1, canSell: true, canStock: true, canAi: true),
        1,
      );
    });

    test('route /stock (tabKey 2) surligne Stock (index 2)', () {
      expect(
        activeIndexFor(tabKey: 2, canSell: true, canStock: true, canAi: true),
        2,
      );
    });

    test('route /ai (tabKey 3) surligne Assistant (index 3)', () {
      expect(
        activeIndexFor(tabKey: 3, canSell: true, canStock: true, canAi: true),
        3,
      );
    });

    test('/home et chemin inconnu retombent sur Accueil (0)', () {
      expect(
        activeIndexFor(tabKey: 0, canSell: true, canStock: true, canAi: true),
        0,
      );
      expect(
        activeIndexFor(tabKey: null, canSell: true, canStock: true, canAi: true),
        0,
      );
    });

    test('sans ventes : /stock (tabKey 2) => index 1 dans la liste filtrée', () {
      // destinations = [Accueil, Stock, Assistant]
      expect(
        activeIndexFor(
          tabKey: 2,
          canSell: false,
          canStock: true,
          canAi: true,
        ),
        1,
      );
      expect(
        activeIndexFor(
          tabKey: 3,
          canSell: false,
          canStock: true,
          canAi: true,
        ),
        2,
      );
    });

    test('onglet inaccessible (permission refusée) retombe sur Accueil', () {
      expect(
        activeIndexFor(
          tabKey: 1,
          canSell: false,
          canStock: true,
          canAi: true,
        ),
        0,
      );
    });

    test('session minimale : seul Accueil, tout retombe sur 0', () {
      for (final key in [0, 1, 2, 3, null]) {
        expect(
          activeIndexFor(
            tabKey: key,
            canSell: false,
            canStock: false,
            canAi: false,
          ),
          0,
        );
      }
    });
  });
}
