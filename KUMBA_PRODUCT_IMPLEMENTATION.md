# KUMBA — Suivi d’implémentation produit (GO production)

## État
Projet Flutter ERP offline-first **renforcé pour production pilote / mono-commerce**.

## Livré (vérifiable)

### Fondation
- [x] Flutter + Riverpod + go_router
- [x] Drift SQLite (~30 tables)
- [x] PIN hashé + secure storage
- [x] Biométrie optionnelle
- [x] Verrouillage auto après fond d’écran (2 min)
- [x] Thème clair/sombre + mode performance
- [x] File de sync (pending honnête sans faux backend)

### Sécurité & RBAC
- [x] `PermissionGuard` dans services (ventes, produits, dettes, dépenses, retours, stock)
- [x] `PermissionGate` sur routes sensibles
- [x] Menu « Plus » filtré par rôle **et** modules secteur
- [x] Invitations employé (code 8 car. / 7 jours)

### Métier
- [x] Ventes atomiques (stock + paiement + dette)
- [x] Retours / annulations **UI + service + audit + restock**
- [x] Clients, dettes, encaissement
- [x] Dépenses, achats, inventaire, devis, factures, livraisons
- [x] Scanner caméra (mobile_scanner)
- [x] Sauvegarde AES + checksum
- [x] Export **transfert téléphone** (transferKey)
- [x] Restauration first-launch (`/restore`)
- [x] Rejoindre commerce (`/join`)

### Qualité
- [x] `flutter analyze` : 0 erreur
- [x] `flutter test` : **25/25** passés
- [x] APK debug / release / AAB (voir `docs/ANDROID_RELEASE.md`)
- [x] Docs : USER_GUIDE, SECURITY, OFFLINE_FIRST, PRODUCTION_READY

## Limites restantes (non bloquantes pilote)
- Sync multi-appareils **distants** : file prête, serveur HTTP à brancher
- Keystore Play Store : encore signing debug → à remplacer avant store public
- OCR / API Mobile Money opérateur : hors scope volontaire
- i18n EN : architecture strings FR prête (`app_strings.dart`), pas de fichiers ARB complets

## Commandes
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```
