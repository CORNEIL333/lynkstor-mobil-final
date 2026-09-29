# KUMBA Business

ERP mobile africain premium, **offline-first**, multisectoriel — conçu pour les petits commerces qui n’ont pas toujours d’ordinateur ni d’Internet permanent.

> *Votre commerce, dans votre téléphone.*

## Fonctionnalités

- **Caisse / POS** : vente rapide, panier, espèces, MTN MoMo, Orange Money, crédit, paiement partiel
- **Stock** : mouvements tracés, inventaire, alertes seuil
- **Clients & dettes** : carnet de crédit, encaissement, historique des mouvements
- **Dépenses, fournisseurs, achats** (réception → stock)
- **Devis, factures, livraisons, employés, pointage**
- **Rapports journaliers** calculés sur données réelles
- **Sauvegarde chiffrée** `.kumba` + HMAC anti-altération ; export téléphone protégé par mot de passe
- **Assistant IA conversationnel local** Qwen3‑0.6B Q4_K_M (lecture seule, aucune action financière automatique)
- **Photos produit** depuis la caméra ou la galerie, stockées dans l’espace privé de l’application
- **Mode hors ligne** complet pour les opérations métier critiques

## Prérequis

- Flutter 3.35+ / Dart 3.9+
- Android SDK (minSdk 26), téléphone ARM64 pour l’assistant IA

## Démarrage

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Démonstration

À l’ouverture : **Découvrir avec une démonstration** — boutique préremplie (produits, clients, dettes).

PIN démo : `1234` · mot de passe : `demo1234`

## Builds Android

```bash
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

Les builds Release exigent `android/key.properties` et une vraie clé de
signature. Le projet refuse volontairement de produire une Release signée avec
la clé de debug.

Sorties :
- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

## Architecture

Voir `KUMBA_TECHNICAL_ARCHITECTURE.md`.

Stack : Flutter · Riverpod · go_router · Drift/SQLite · secure storage.

L’assistant télécharge une seule fois le modèle GGUF (~480 Mo), contrôle son
SHA‑256, puis fonctionne sans réseau. Voir `docs/LOCAL_AI.md`.

## Tests

```bash
flutter test
flutter analyze
```

## Documentation

| Fichier | Contenu |
|---------|---------|
| `docs/SUPABASE_CLOUDFLARE_DEPLOYMENT.md` | **Déploiement cloud admin + API** |
| `docs/DEPLOYMENT_GUIDE.md` | Node monolithe / Docker / Render |
| `docs/LOCAL_AI.md` | Modèle IA local, sécurité, téléchargement et limites |
| `KUMBA_PRODUCT_IMPLEMENTATION.md` | État d’implémentation |
| `KUMBA_UX_FLOWS.md` | Parcours utilisateurs |
| `KUMBA_DESIGN_SYSTEM.md` | Tokens & composants |
| `KUMBA_TECHNICAL_ARCHITECTURE.md` | Architecture |
| `KUMBA_TEST_MATRIX.md` | Matrice de tests |
| `docs/` | Guides utilisateur, admin, sécurité, offline |

## Invariants métier

1. Une vente validée est écrite en base **avant** l’écran de succès.
2. Une dette ne change que via un mouvement.
3. Un stock ne change que via un mouvement.
4. Une sauvegarde « réussie » implique un fichier vérifiable + checksum.
5. Jamais de demande de PIN Mobile Money opérateur.

## Licence

Projet client — usage privé.
