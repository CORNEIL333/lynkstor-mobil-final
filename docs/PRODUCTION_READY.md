# KUMBA Business — Checklist GO Production

## Critères bloquants traités

| Exigence | Statut |
|----------|--------|
| RBAC appliqué services + UI | ✅ PermissionGuard + PermissionGate |
| Modules par secteur | ✅ SectorModules + filtrage menu |
| Retours / annulations UI | ✅ `/sale/return/:id` + audit |
| Restauration first-launch | ✅ `/restore` + export transfert |
| Rejoindre commerce | ✅ invitations locales + code |
| Scanner caméra | ✅ mobile_scanner |
| Biométrie + verrouillage fond | ✅ local_auth + lifecycle 2 min |
| Sauvegarde vérifiable + transfert | ✅ AES + checksum + transferKey |
| Tests métier étendus | ✅ **25 tests** (permissions, dettes, retours, dépenses, ventes, sectors) |
| Analyze 0 erreur | ✅ |
| Builds APK/AAB | ✅ |
| Chaînes UI centralisées | ✅ `lib/l10n/app_strings.dart` |

## Verdict (2026-07)

| Scénario | Décision |
|----------|----------|
| Pilote terrain mono-appareil offline-first | **GO** |
| Multi-appareils cloud + admin | **GO conditionnel** (stack live, valider terrain) |
| Play Store / scale massif | **NO GO** tant que P0 ci-dessous non bouclé |

**GO pilote** pour : caisse, stock, dettes, backup AES, PIN, code agent cloud.  
**NO GO store** tant que : keystore release, checklist terrain 🔴, monitoring.

## P0 avant GO production élargi

| # | Action | Statut | Outil / doc |
|---|--------|--------|-------------|
| 1 | Keystore release + backup hors machine | ☐ à faire | `tool/create_release_keystore.ps1` |
| 2 | Build signé + SHA | ☐ | `tool/build_release_apk.ps1` |
| 3 | Test terrain 7 jours (mode avion) | ☐ | `docs/FIELD_CHECKLIST.md` |
| 4 | Privacy policy revue | 📄 présent | `docs/PRIVACY_POLICY.md` |
| 5 | Crash monitoring (Sentry/Firebase) | ☐ optionnel budget | — |
| 6 | Sync 2 appareils (si vendu multi-pos) | ☐ | Admin + Supabase |

Cloud déjà en place : Edge `lynkstor-api` + admin Cloudflare Pages.

## Avant mise en boutique publique

1. **Keystore release** (`tool/create_release_keystore.ps1`) — ne plus signer en debug
2. **Checklist terrain** tous items 🔴 OK
3. **AAB** : `tool/build_release_apk.ps1 -Bundle`
4. **Politique de confidentialité** publiée (URL store)
5. Monitoring crash si budget

## Commandes validation

```bash
flutter analyze
flutter test
# Keystore une fois :
powershell -ExecutionPolicy Bypass -File tool/create_release_keystore.ps1
# Build signé (tests inclus) :
powershell -ExecutionPolicy Bypass -File tool/build_release_apk.ps1
# Pilote sans keystore :
powershell -ExecutionPolicy Bypass -File tool/build_release_apk.ps1 -AllowDebugSigning
```

## Rôles vérifiés

- owner : tout
- manager : presque tout sauf sync admin extrême
- seller : ventes, clients, dettes collect, pas backup/retours
- delivery : livraisons uniquement
- accountant : rapports / factures / dépenses lecture
