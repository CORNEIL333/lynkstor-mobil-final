# Matrice de tests KUMBA

## Unitaires
| ID | Scénario | Fichier | Statut |
|----|----------|---------|--------|
| U1 | Format monétaire FCFA | `test/unit/money_format_test.dart` | Implémenté |
| U2 | Parse montant | idem | Implémenté |
| U3 | Vente cash diminue stock | `test/unit/sale_service_test.dart` | Implémenté |
| U4 | Crédit sans client refusé | idem | Implémenté |
| U5 | Stock insuffisant refusé | idem | Implémenté |

## Widgets
| ID | Scénario | Fichier | Statut |
|----|----------|---------|--------|
| W1 | Bouton label + tap | `test/widget_test.dart` | Implémenté |
| W2 | Empty state | idem | Implémenté |
| W3 | Status badge | idem | Implémenté |

## Métier (manuel / device)
| ID | Scénario | Priorité |
|----|----------|----------|
| M1 | Vente comptant mode avion | P0 |
| M2 | Vente crédit + encaissement dette | P0 |
| M3 | Paiement partiel | P0 |
| M4 | Inventaire écart | P0 |
| M5 | Sauvegarde fichier vérifiable | P0 |
| M6 | Redémarrage après vente | P0 |
| M7 | Mode performance | P1 |
| M8 | Dark mode lisibilité | P1 |

## Commandes
```bash
flutter test
flutter analyze
```
# Validation manuelle obligatoire — version 1.2.0

Ces contrôles restent des portes de sortie avant commercialisation publique.
Ils doivent être exécutés après le déploiement des trois migrations Supabase
en attente et de la fonction `lynkstor-api`.

- [ ] Mise à jour d’un téléphone contenant une ancienne base non chiffrée :
      ouverture, connexion, ventes et historique intacts.
- [ ] Installation neuve sur au moins deux versions Android prises en charge.
- [ ] Deux téléphones du même commerce : créer puis modifier fournisseur,
      achat, devis, facture, livraison, employé, pointage, inventaire et règle
      d’automatisation ; vérifier la réception sur l’autre appareil.
- [ ] Couper le réseau pendant plusieurs écritures, rétablir un réseau lent ou
      instable, puis vérifier qu’un lot unique est envoyé sans doublon.
- [ ] Créer une sauvegarde cloud avec mot de passe, la télécharger sur le
      second téléphone et effectuer une restauration exacte.
- [ ] Refuser volontairement un mauvais mot de passe et un fichier altéré :
      aucune donnée active ne doit être remplacée.
- [ ] Appairer une imprimante ESC/POS Bluetooth réelle, puis imprimer sur
      rouleau 58 mm et/ou 80 mm selon le matériel disponible.
- [ ] Vérifier que MTN/Orange Mobile Money sont affichés « bientôt » et ne
      peuvent jamais valider une transaction.
