# Builds Android — Lynkstor Business

## Chemins

| Artefact | Chemin |
|----------|--------|
| APK debug | `build/app/outputs/flutter-apk/app-debug.apk` |
| APK release | `build/app/outputs/flutter-apk/app-release.apk` |
| AAB release | `build/app/outputs/bundle/release/app-release.aab` |
| Copies + SHA | `build/release-artifacts/` |

## Configuration

- `applicationId` : `com.kumba.kumba_business`
- `minSdk` : 24
- Signature release : `android/key.properties` + `android/kumba_release.jks`
- Sans `key.properties`, Gradle signe en **debug** (pilote uniquement, **pas** Play Store)

Fichiers secrets **ignorés par git** : `key.properties`, `*.jks`, `secrets/`

---

## P0 — Keystore release (une seule fois)

```powershell
# Depuis la racine du projet
powershell -ExecutionPolicy Bypass -File tool/create_release_keystore.ps1
```

Cela crée :

1. `android/kumba_release.jks`
2. `android/key.properties`
3. `secrets/keystore-backup.txt` ← **copier hors machine** (USB chiffré / password manager)

> Perdre le `.jks` + mots de passe = impossible de mettre à jour la même app sur le Play Store.

---

## Build release (recommandé)

```powershell
# Refuse le build si pas de keystore (prod)
powershell -ExecutionPolicy Bypass -File tool/build_release_apk.ps1

# + AAB Play Store
powershell -ExecutionPolicy Bypass -File tool/build_release_apk.ps1 -Bundle

# Pilote sans keystore (signature debug) — explicite
powershell -ExecutionPolicy Bypass -File tool/build_release_apk.ps1 -AllowDebugSigning
```

Le script :

1. `flutter pub get`
2. `flutter test` (bloque si échec)
3. `flutter build apk --release`
4. Copie APK + SHA-256 dans `build/release-artifacts/`

### Commandes manuelles

```bash
flutter build apk --release
flutter build appbundle --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## Checksums

Générés à chaque run de `tool/build_release_apk.ps1` dans `build/release-artifacts/build-report-*.txt`.

Dernier APK connu (pilote, peut être debug-signed) : voir dossier `build/app/outputs/flutter-apk/`.

---

## Play Store (après terrain)

1. Keystore P0 OK + backup hors machine  
2. Checklist `docs/FIELD_CHECKLIST.md` 🔴 tous OK  
3. AAB : `tool/build_release_apk.ps1 -Bundle`  
4. Privacy policy : `docs/PRIVACY_POLICY.md`  
5. Crash reporting (Sentry/Firebase) recommandé  
