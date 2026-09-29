# Audit de mise en production — Lynkstor Business
**Date : 24 septembre 2026 — objectif : déploiement sous 5 jours**

Méthode : lecture directe du code Flutter (123 fichiers / 77 154 lignes), de la passerelle Deno (`supabase/functions/lynkstor-api/index.ts`, 2 047 lignes), du serveur Express, des 8 migrations SQL, de la config Android, plus exécution réelle de `flutter analyze` et `flutter test` ce jour, plus interrogation en ligne de l'API (`/health`). Les chiffres de pricing ont été revérifiés auprès des sources officielles (Neon, Firebase, agrégateurs) en date de septembre 2026.

---

## 0. Verdict en un coup d'œil

| Domaine | État réel | Risque de lancement |
|---|---|---|
| Code Flutter / structure | ✅ Très solide (33 features, `flutter analyze` = 0 erreur) | Faible |
| Tests automatisés | ⚠️ 102 réussis / 5 échoués / 1 ignoré | Moyen |
| UI/UX | ⚠️ Débordements prouvés + contraste insuffisant + navigation incohérente | Moyen |
| Sécurité | 🔴 13 points dont 5 critiques | **Élevé** |
| Backend | ⚠️ Fonctionnel mais en double exemplaire, sans rate limiting, sans migration | Moyen/Élevé |
| Monétisation (abonnement) | 🔴 **Non enforceable** : l'app tourne à vie sans jamais payer | **Bloquant business** |
| IA locale | ✅ Bonne conception (offline, grounded, lecture seule) | Faible |
| Distribution Play Store | 🔴 206 Mo de GGUF embarqué + `minify` désactivé | **Élevé** |
| Auth OTP mobile | ❌ Inexistante (code d'activation + PIN local seulement) | À créer |
| Paiement récurrent | ❌ Inexistant (`MobileMoneyService` = saisie manuelle, statut `comingSoon`) | À créer |
| Dashboard admin | ⚠️ Existant mais « Lite » (9 onglets, aucun CRUD plan, zéro revenus, zéro versions) | À refondre |
| Hygiène projet | 🔴 **Aucun dépôt Git** + keystore non sauvegardé hors machine | **Élevé** |

**Conclusion honnête** : en 5 jours on ne migre pas tout le backend *et* on ne refait pas l'UI *et* on ne signe pas un contrat agrégateur. En 5 jours on peut **livrer une V1 réellement en production** en faisant les 6 bons arbitrages (§4 et §8). Ce qui ne tient pas est listé explicitement (§8, « sorti du périmètre ») avec un plan B de lancement qui ne bloque pas l'encaissement.

---

## 1. Ce qui est déjà bien (à ne pas casser)

- **Offline-first réel** : Drift + SQLCipher, `PRAGMA cipher_version` vérifié au démarrage, `cipher_memory_security = ON`, clé de base **aléatoire** logée dans le Keystore Android (`getOrCreateDatabaseKey`) — pas un chiffrement « maison » faible, et pas dérivé du PIN à 4 chiffres (bonne décision : 10 000 combinaisons autrement).
- **Sauvegardes** AES + PBKDF2-SHA256 120 000 itérations + sel aléatoire pour l'export de transfert.
- **Sync bidirectionnelle événementielle propre** : `sync_events`, `sync_entities`, `device_sync_cursors`, batches atomiques (`record_sync_batch`), `X-Idempotency-Key`, et **jeton d'appareil dédié** (`device_sync_tokens`, hash SHA-256, champ `revoked_at`) → le multi-tenant est bien pensé dans son principe.
- **RLS fermé sur toutes les tables cloud** : aucun accès direct `anon`/`authenticated`, tout passe par la passerelle.
- **Moteur de facturation métier sérieux** : `billing_engine.dart`, 771 lignes, règles documentées (arrondi à la ligne, prix catalogue TTC, remise globale au prorata, coût figé à la vente).
- **Permissions réelles** filtrant la navigation ; bilingue FR/EN complet ; NavigationRail ≥ 840 dp ; chiffres tabulaires sur les KPI.
- **IA locale bien garde-fouée** : Qwen 2.5 0.5B, réponses déterministes sur les questions chiffrées, lecture seule stricte, zéro donnée sortante.
- **Audit UI/UX du 22/09 déjà écrit** et de bonne qualité — ses constats restent valables (re-vérifiés dans le code ce jour).
- **Webhook de paiement idempotent** côté SQL (`process_payment_webhook`) avec HMAC sur le corps brut → base saine pour brancher un agrégateur.
- **La passerelle est en ligne et saine** : `GET /health` répond ce jour (`{"status":"ok",...}`). `deploy/NEXT_STEPS.md` qui dit « répond encore 404 → pas déployée » est **périmé** : à corriger, sinon un futur déployeur va casser ce qui marche.

---

## 2. UI / UX — audit détaillé

### 2.1 Anomalies bloquantes, reproduites par les tests ce jour

| # | Constat | Preuve (vérifiée) | Impact |
|---|---|---|---|
| U1 | **`RenderFlex overflowed by 87 pixels` sur le dashboard**, en thème clair ET sombre | `test/widget/ui_snapshot_test.dart` → 2 échecs | Écrans cassés sur petit écran / texte agrandi ; bloque la release |
| U2 | **Contraste blanc sur orange `#FF9800` = 2,16:1** sur le bouton principal et la carte « Vendre » | `lib/core/theme/app_colors.dart:34` (`fab == primary`, `onPrimary = blanc`) + `kumba_button.dart` | Illisible ; échec WCAG AA même en grand texte (seuil 3:1) |
| U3 | **Navigation fantôme** : `KumbaFloatingNavBar` (action centrale Vendre + entrée Plus) n'est appelé nulle part ; la barre affichée est construite par `ShellScaffold` | `lib/app/router.dart:168` ; aucun appel dans `lib/` | L'UX conçue n'est pas l'UX livrée : toute décision prise sur la barre flottante serait fausse |
| U4 | **Indicateurs financiers inventés** : carte « Acomptes » figée sur `MoneyFormat.formatCompact(0)` avec libellé fixe, et courbe `spark: true` dessinée sans aucune série de données | `dashboard_screen.dart:176,224` + `kumba_ornament.dart:103` | **Grave pour un outil de caisse** : on affiche une tendance qui n'est pas calculée |
| U5 | **Caisse sans récupération d'erreur** : attente produits + clients sans `try/catch` ni contrôle `mounted` | `sale_screen.dart:68`, `_loading` ligne 357 | Spinner à vie si le service échoue ; `setState` sur un écran détruit |
| U6 | **Mode sombre partiel** : la caisse force `AppColors.pageBg` même quand `dark == true` ; l'accueil garde des cartes blanches | audit 22/09, confirmé | Incohérence + contrastes non vérifiés |
| U7 | **Reduced-motion peut rendre le contenu invisible** : `.animate(target: reduce ? 0 : 1).fadeIn(...)` | audit 22/09 | En animations réduites, retour à l'état initial → transparence possible |
| U8 | Goldens onboarding premium **hors référence : 76,68 % de pixels de différence** (252 385 px) | `premium_entry_visual_test.dart` | La direction visuelle livrée n'est pas celle validée |
| U9 | Test de parcours catalogue **non conclusionnel** : `find.text('Beignet fourré')` matche le champ de recherche ET le résultat | `prototype_integration_test.dart:106` | Le parcours recherche → formulaire n'est pas prouvé fonctionnel |
| U10 | **Échec du test de migration : attendu 3, obtenu 4** | `test/core/database/app_database_migration_test.dart` → `repairs a partially applied v1 to v2 migration` | **Risque de perte de données** au upgrade depuis une version déjà installée |

### 2.2 Manques non couverts par l'audit du 22/09 (et qui comptent au lancement)

- **U11 — Aucun écran de licence expirée ni de parcours de renouvellement.** `allowsSales` renvoie un booléen, mais l'expérience « abonnement terminé → choisir un forfait → payer → débloqué » n'existe pas. **C'est le cœur du revenu : il doit être aussi soigné que la caisse.**
- **U12 — Aucun écran de mise à jour obligatoire** (voir S8) : rien n'empêche une version buggée de continuer à vendre.
- **U13 — Aucun écran d'erreur OTP actionnable** (numéro invalide, envoi raté, quota atteint, opérateur indisponible) — à concevoir dès maintenant car c'est la première impression du client.
- **U14 — Pas de récupération de compte par numéro de téléphone** après changement d'appareil : la reprise repose aujourd'hui sur un fichier + mot de passe de transfert (`restore_onboarding_screen.dart`), ce que beaucoup de gérants ne sauront pas faire.
- **U15 — Pas d'état « dégradé » explicite** : `performanceMode` existe, mais rien n'annonce à la vendeuse que la session tourne hors ligne depuis 9 jours et que la licence n'a pas pu être re-vérifiée.
- **U16 — Cibles tactiles et focus** : `kumba_pressable.dart:33` repose sur `GestureDetector` sans contrat d'accessibilité (focus, activation clavier, rôle bouton) ; le bouton de repli Lynk fait 40×40 sans libellé (seuil Android : 48×48).

### 2.3 Ordre de correction, par ROI

1. **U1, U10, U5** — ce qui casse et ce qui perd des données (Jour 1).
2. **U4** — brancher sur une agrégation Drift réelle avec période affichée, sinon remplacer par « Indisponible » ou retirer la carte. Un ERP qui ment sur les chiffres perd son client au 2ᵉ jour.
3. **U2** — créer des couples sémantiques (`actionSurface` / `onActionSurface`) : encre `#0F172A` sur orange = **8,28:1**, on garde la couleur de marque. Propager dans `KumbaButton`, cartes d'accueil, bannières ; ne pas se contenter de changer `onPrimary` (certains composants forcent encore `Colors.white`).
4. **U3** — décider **une** navigation, supprimer ou brancher `KumbaFloatingNavBar`.
5. **U7** — en reduced-motion, rendre l'état final visible immédiatement ; ne jamais retarder une action de caisse pour une animation d'entrée.
6. **U11→U15** — écrans licence/OTP/mise à jour (liés à §4.4, §4.5, S8).
7. U6, U8, U9, U16 — second pass après lancement (V1.1).

---

## 3. Sécurité — audit détaillé

### 3.1 🔴 Critique

**S1 — La licence est auto-conservée sur l'appareil et non vérifiable de force.**
`flutter_secure_storage` (EncryptedSharedPreferences ; lisible sur appareil rooté ou par extraction de backup) contient `licenseActive`, `source`, `status`, `expiresAt`. Or :
- `lib/shared/models/subscription_info.dart:53` → `if (source == 'local' || source == 'unknown') return true;`
- `lib/shared/services/business_service.dart:171-176` → pour une inscription sans code agent, écrit `planName: 'TEST', status: 'active', licenseActive: true, source: 'local'`

**Conséquence business directe** : quiconque reste hors ligne, ou écrit `source=local`, vend à vie sans payer. **L'abonnement n'est pas applicable en l'état** — c'est le point le plus grave de tout l'audit, avant même les sujets de sécurité technique.

**Corrigé (4 mesures, toutes nécessaires)**
a. Supprimer le chemin `source == 'local' → autorisé` dès qu'un appareil est lié au cloud.
b. **Signature serveur** du statut de licence : `POST /v1/license/verify` renvoie `{plan, status, expiresAt, maxOfflineDays, iat, nonce, sig}` signé HMAC ; l'app stocke le blob **signé**, plus des champs séparés modifiables.
c. **Grâce offline bornée** : 7 jours max (la valeur `isVerificationStale` existe déjà) — mais au-delà, verrouillage progressif réel (module vente coupé, données intactes), au lieu du comportement actuel.
d. **Horloge serveur** : la comparaison d'expiration doit utiliser le temps du serveur (sinon un appareil à date fausse passe). + journaliser côté serveur la date de dernière vérification par appareil → visible dans le dashboard (détection des non-payeurs).

**S2 — Une seule clé partagée autorise la sync de tous les commerces.**
`supabase/functions/lynkstor-api/index.ts:955` : `if (await isSyncToken(token)) return { authorized: true, privileged: true, businessId: null }` ; et `isSyncToken` (`_shared/auth.ts:123-128`) accepte `SYNC_API_KEY` **ou, à défaut, `ADMIN_API_KEY`**. `deploy/NEXT_STEPS.md:75` instructions explicites au mobile : « Bearer : `SYNC_API_KEY` ou `ADMIN_API_KEY` ».
**Conséquence** : un seul APK décompilé (et `isMinifyEnabled = false`, voir S9) expose la lecture et l'écriture du CA, des clients et des dettes de **tout le parc**.
**Corrigé** : supprimer `privileged` pour tout appel venant d'un mobile ; le mobile n'utilise que `device_sync_tokens` (par appareil, expirant, révocable) ; l'administration passe par une session courte distincte.

**S3 — `requireAgentActivationCode = false` + `allowDemoMode = true` en production.**
`lib/core/config/app_config.dart:68-72`, commentaire : « Désactivé pour le panel boutiques test : inscription libre sans clé ». Soit c'est un choix d'acquisition (alors l'assumer : essai gratuit **daté côté serveur**), soit c'est un reste de panel de test à inverser avant le build de release.

**S4 — CORS `Access-Control-Allow-Origin: *` sur la passerelle, routes admin incluses** (`supabase/functions/_shared/cors.ts:2`). Combiné à S5, n'importe quelle page web peut appeler `/api/v1/admin/*`. À restreindre à l'origine réelle du dashboard.

**S5 — `ADMIN_API_KEY` sert à la fois de secret de signature ET de jeton d'accès à vie.**
`_shared/auth.ts:91` : si le bearer `=== adminApiKey` → session `super_admin` (et ce même sans expiration réelle : `exp` est remis à +60 s à chaque appel). Le dashboard publicitaire (`server/public/config.js`) est servi publiquement.
**Corrigé** : la clé ne sert plus qu'à signer ; sessions 12 h avec révocation côté serveur (table `admin_sessions`) ; MFA TOTP pour `super_admin` ; limitation de débit sur `/auth/login` (S6).

### 3.2 🟠 Élevé

- **S6 — Zéro limitation de débit, zéro verrouillage.** Aucune occurrence de `rate`/`throttle`/`attempt`/`lockout` dans toute la passerelle. Sont exposés : `/auth/login`, `/register/validate`, `/activation/validate` (non consommable → sonde d'énumération de codes), `/register` (bourrage de la base), `/payments/webhook`.
  → Compteur par (IP + numéro + action) dans Neon (`rate_limits`) ou Upstash Ratelimit (gratuit) ; verrouillage progressif + exponentiel ; table `admin_login_attempts`.
- **S7 — Repli en clair dans `verifyPassword`** (`_shared/auth.ts:189-194`) : si le hash stocké n'est pas au format `pbkdf2-sha256$…`, la comparaison devient `safeEqual(password, stored)` → un compte « legacy » = mot de passe en clair dans la base. À supprimer après inventaire des comptes.
- **S8 — Aucun mécanisme de mise à jour obligatoire ni de kill switch.** Aucune occurrence de `forceUpdate` / `min_version` / `update_available` dans `lib/`, et `AppConfig.analyticsIngestUrl` est vide (`app_config.dart:60`). Un bug distant = parc entièrement bloqué sans recours.
  → `GET /v1/config` (Neon → cache edge) avec `minSupportedVersion`, `latestVersion`, `updateMessage`, `killModules[]`, `announcement`, `maxOfflineDays` ; l'app refuse la caisse sous `minSupportedVersion`.
- **S9 — `isMinifyEnabled = false`, `isShrinkResources = false`** (`android/app/build.gradle.kts:72-73`) : code non obfusqué, extraction de secrets triviale. À activer + `proguard-rules.pro` avec garde des classes de MethodChannel (impression Bluetooth, llama, analytics) — et re-tester impression + IA **après** R8.
- **S10 — Secrets de test en dur dans `server/.env`** : `ADMIN_PASSWORD=TestAdmin!2026`, `WEBHOOK_SECRET=test-webhook-secret-kumba`, `ADMIN_API_KEY=test-admin-key-kumba-2026`. À faire expirer et à ne plus faire exister de `.env` réel dans l'arborescence livrée (garder `.env.example`).
- **S11 — `android/key.properties` + `android/kumba_release.jks` dans le dossier de travail**, sans copie chiffrée hors machine. Perte = **impossibilité définitive** de mettre à jour l'app sur Play Store. À archiver dans un coffre chiffré hors poste, avec la passphrase notée séparément.
- **S12 — Aucune télémétrie de plantage** : aucune occurrence de `sentry`/`crashlytics`/`firebase` dans `pubspec.yaml` (vérifié par grep). Vous apprenez les bugs par les avis du store.
  → Sentry (gratuit 5k événements/mois) ou Crashlytics, avec le `buildNumber` comme tag.
- **S13 — Aucune configuration TLS durable** : pas de `network_security_config.xml`, pas de pinning. À minima : forcer TLS 1.2+, interdire le cleartext (`cleartextTrafficPermitted="false"`), et prévoir une exception limitée au debug.

### 3.3 Bas-medium (à traiter dans le même élan)

- **S14 — `PUT /admin/subscriptions/:id`** (`index.ts:1807`) n'exige qu'un rôle `supervisor` : un commercial promu peut prolonger n'importe quelle licence, **sans motif obligatoire ni journal d'audit**. → champ `reason` requis + table `admin_audit_log`.
- **S15 — Aucune route de suppression de commerce/utilisateur** (vérifié dans la liste complète des routes admin). Obligatoire pour le formulaire de sécurité des données Play **et** pour la loi 2023-010 (CI) / RGPD.
- **S16 — Génération de codes d'activation en boucle applicative** avec 5 tentatives (`index.ts:1347`) : correct fonctionnellement, mais un index unique sur `code` dans SQL + `INSERT ... ON CONFLICT` est plus sûr.
- **S17 — Jeton admin par défaut codé en dur** : `staff_id: "st-04"`, `full_name: "Super Admin Lynkstor"` apparaissent dans 3 endroits. À remplacer par l'identité réellement authentifiée.
- **S18 — Permissions Android** : l'app demande `WRITE_EXTERNAL_STORAGE` (≤28) et `READ_EXTERNAL_STORAGE` (≤32) avec `requestLegacyExternalStorage="true"` alors que la doc de sécurité ne liste qu'INTERNET/CAMERA/BiOMETRIC (`docs/SECURITY.md:20-23`) → les sauvegardes peuvent atterrir dans un stockage partagé lisible par d'autres apps. À re-cibler sur le stockage privé + `MediaStore` explicite, et à déclarer correctement dans le Play Data Safety form.

### 3.4 Conformité / distribution

- Formulaire **Data Safety** Play : déclarer chiffrement (AES/SQLCipher, clé Keystore), sauvegardes, données envoyées au cloud, absence d'ID publicitaire, et fournir **suppression de compte** dans l'app (S15).
- **Play Billing & méthodes de paiement alternatives** : pour un abonnement payé hors Google Play (mobile money), Google impose le formulaire d'inclusion dédié + l'appel au système de facturation en surface. À préparer avec un texte exact, sinon rejet à la revue.
- `docs/PRIVACY_POLICY.md` existe mais doit être **publié sur une URL stable** (Cloudflare Pages) et mis à jour pour le nouveau stack (Firebase, agrégateur, OTP/SMS, push).
- **Aucune clause de licence / CGU / politique de résiliation** dans `docs/` (seule la politique de confidentialité existe) : à écrire avant d'encaisser un abonnement.
- Formalités **ARTCI (Côte d'Ivoire)** / **ANINF (Cameroun)** pour le traitement de données personnelles à préparer (non bloquant techniquement).
- `docs/SECURITY.md` et `docs/KNOWN_LIMITATIONS.md` sont **optimistes** (« ✅ Sync multi-appareils », « ✅ Paiement Mobile Money » alors que `MobileMoneyService.initiatePayment` renvoie `MobileMoneyStatus.comingSoon` et `'coming-soon'` comme `transactionId`). À réécrire à jour avant le lancement : une doc qui annonce une fonctionnalité inexistante finit en promesse commerciale.

---

## 4. Architecture cloud cible : Supabase → Neon + Firebase

### 4.1 Chiffres vérifiés ce jour (septembre 2026)

| Service | Gratuit réel | Piège pour Lynkstor |
|---|---|---|
| **Neon** | 100 projets ; **100 CU-heures/projet/mois** ; **0,5 Go stockage** ; autoscale jusqu'à 2 CU ; scale-to-zero ; 10 branches | `sync_events` en croissance **infinie** : 0,5 Go = quelques dizaines de milliers de lignes → **obligation d'agréger + purger à 90 j**, sinon dépassement facturé (Launch = 0,106 $/CU-h) |
| **Firebase Auth — OTP SMS** | **Blaze uniquement** (carte bancaire obligatoire) ; 3 000 SMS/jour/projet ; 150 demandes/h/IP ; 50 SMS/min et 500/h par IP ; facturé **par SMS envoyé** | **Phone Number Verification indisponible en Afrique de l'Ouest** — la liste officielle ne couvre que FI, FR, DE, GB, GR, ID, IE, MY, NL, PK, RO, ES. Donc pas de vérification « gratuite » ni d'attestation opérateur pour `+225`/`+237` |
| **Firestore (Spark)** | 50k lectures, **20k écritures**, 20k suppressions/jour ; 1 GiB ; 10 GiB egress | **Inacceptable comme couche de sync** : 20 commerces × 1 000 événements/jour = 20 000 écritures = quota explosé le premier jour |
| **Cloud Functions** | 2 M invocations/mois, puis 0,40 $/M | Correct pour OTP + webhooks (les webhooks agrégateur sont rares) |
| **Firebase Storage** | 5 Go | Les backups de tout le parc le dépassent vite → à déplacer vers R2 |
| **Cloudflare Workers / Pages / R2** | 100k req/j ; Pages sans limite de bande passante ; **R2 10 Go et egress 0 $** | Meilleure option pour l'API + les fichiers |
| **Sentry** | 5k événements/mois | Suffisant pour quelques centaines de commerces |

### 4.2 Cible recommandée — **Neon = vérité, Firebase = identité + push, Cloudflare = calcul + fichiers**

```
                    ┌───────────────────────────────────────────┐
App Flutter ──────► │ Cloudflare Worker = API Lynkstor          │
 (Drift + SQLCipher,│  sync push/pull · licence signée · plans  │
  Riverpod, FCM)    │  paiements/webhooks · OTP verify · admin  │
     │               └───────┬───────────────────┬─────────────┘
     │                       │                   │
     └─ OTP / custom token ─►│             ┌─────▼──────────────┐
       (session Firebase)    │             │ Firebase (Spark)    │
                    ┌────────▼────────┐    │ Auth · FCM · Crash  │
                    │ Neon Postgres   │    │ Analytics           │
                    │ source de vérité│    └────────────────────┘
                    └─────────────────┘
                    Cloudflare R2      backups chiffrés + catalogue + modèle IA (egress 0 $)
                    Cloudflare Pages   dashboard admin + site + politique de confidentialité
                    Upstash / Neon     limitation de débit
```

**Règle de séparation, à ne pas négocier**
> **Neon est l'unique source de vérité** (sync, licences, plans, paiements, appareils, admin, audit). **Firebase ne fait que l'identité (sessions), le push, le crash et l'analytics.** Pas de sync dans Firestore (quota + modèle document inadapté à votre protocole). Pas de facturation dans Firebase (incapable d'assurer un multi-tenant relationnel et audité).

### 4.3 Pourquoi « Firebase à la place de Supabase pour la sync » est une mauvaise idée ici
Firestore imposerait de réécrire `sync_engine.dart` + `remote_event_applier.dart` (≈ 26 Ko de logique d'application d'événements, de curseurs et de conflits) et casserait le quota d'écritures gratuit. Votre contrat actuel — *batch atomique + cursor monotone + idempotence + périmètre `business_id`* — est **relationnel par nature**. **On garde le protocole, on change le magasin.** C'est aussi ce qui rend le portage court (§4.7).

### 4.4 OTP mobile : le design qui reste maîtrisable en coût

1. `POST /v1/auth/otp/request {phoneNumber}` → le Worker normalise en E.164, applique la limitation de débit (60 s entre deux envois, 3 tentatives/numéro/heure, plafond journalier par IP), génère un **code de 6 chiffres CSPRNG**, le stocke **haché** dans Neon (`otp_challenges`, expiration 5 min, compteur de tentatives 5).
2. **Livraison**, par ordre de coût/fiabilité pour CI + Cameroun :
   - **A. WhatsApp Business (modèle `authentication`)** — souvent moins cher que le SMS et bien meilleur taux de livraison ;
   - **B. Passerelle SMS régionale prépayée** (crédit, **sans carte bancaire**, routage local) — à comparer sur devis : SMS Partner Africa, SMSPro Africa, Sendexa, Africa's Talking, Unifonic ;
   - **C. Firebase Auth Phone natif** — si vous acceptez Blaze + carte + coût par SMS et que Google livre bien sur les opérateurs locaux.
3. `POST /v1/auth/otp/verify` → si valide, le Worker/Function **mint un Firebase Custom Token** : `admin.auth().createCustomToken(uid, { businessId, role, deviceId })` ; l'app fait `signInWithCustomToken`.
4. **Pourquoi c'est mieux que le provider Phone natif** : vous gardez Firebase Auth comme autorité de session/jetons/expiration (et donc FCM, Règles de sécurité, Storage, Analytics), mais **vous contrôlez le canal et le coût d'envoi**, et vous changez de fournisseur SMS sans retoucher l'app. Bonus : pas de dépendance à une region PNV indisponible.
5. **Liaison identité ↔ métier** : colonne `auth_uid` sur `users` / `staff_accounts` dans Neon ; l'OTP devient la clé de récupération du commerce sur un nouvel appareil (résout **U14**).
6. **Garde-fous** : `ADMIN` test numbers désactivés en production, messages FR/EN localisés, **plan de secours hors OTP** (numéro perdu / portabilité : code agent + pièce), et sessions longues pour limiter les nouvelles vérifications SMS payantes.

### 4.5 Paiement des abonnements — la réalité du terrain

**Il n'existe pas de prélèvement récurrent natif fiable en mobile money dans l'espace UDMA/CEMAC sans mandat opérateur direct** (contractuel, long, réservé aux gros marchands). Toute architecture qui suppose « Google Recurring Billing, mais sur Orange Money » ne tient pas. Les agrégateurs offrent un **paiement à l'initiative** + `notify_url`.

**Modèle recommandé — renouvellement à l'initiative, vérifié par webhook, avec relances**
```
Licence expire à J
J-7 / J-3 / J0 / J+3 : push FCM (+ SMS/WhatsApp) « votre Lynkstor expire »
Le gérant tape « Renouveler » → payment_intent → checkout agrégateur (ou push direct sur son numéro)
   → il confirme sur son téléphone
→ Webhook (HMAC + timestamp frais + idempotence par transaction_id)
   → Neon prolonge subscriptions.expires_at → push de confirmation + l'app polled
```
Le **reçu PDF d'abonnement** doit être généré (les paquets `pdf` et `printing` sont déjà dans `pubspec.yaml`) : vos clients B2B en ont besoin pour leur comptabilité.

**Agrégateurs candidats (à présélectionner aujourd'hui, pas dans 5 jours)**

| Acteur | Pays | Mobile money | Carte | Récurrent | Commission indicative | Intégration |
|---|---|---|---|---|---|---|
| **CinetPay** 🇨🇮 | CI, SN, ML, BF, TG, BJ, CM, GA… | ✅ Orange/MTN/Wave/Moov | ✅ | ❌ (Checkout + `notify_url`) | ~2–4 % | ⭐ la plus documentée en français ; hub unique pour la zone |
| **SenePay** 🇸🇳 | multi-pays | ✅ Orange/MTN/Moov/Wave/Airtel | ✅ | ❌ (à l'initiative) | **3,6 %** affiché | REST simple, « en 5 minutes » |
| **KkiaPay** 🇧🇯 | BJ + francophone | ✅ | partiel | ❌ | ~1,5–3 % | webhooks documentés |
| **ElyonPay** | CI, CM, SN | ✅ MTN/Orange | ✅ | à confirmer | ~2,5 % | API + API « Direct » (transferts) |
| **Flutterwave** | 30+ dont CI/CM | ✅ | ✅ | ✅ (selon pays) | ~2,5–3,8 % | plus lourd, KYC soutenu |
| **Paystack** | NG, GH, ZA (**pas CI/CM**) | ❌ | ✅ | ✅ Plans | 1,5 % local | à garder pour une extension Nigéria |
| **FedaPay / Monetbil / Tranzak / GoPhone** | BJ / Cameroun | ✅ | partiel | ❌ | variable | replis locaux |

**Décision pragmatique** : **1 principal (CinetPay ou SenePay — celui dont le KYC est obtainable sous 5 jours) + 1 repli** selon le pays cible, et **jamais de code spécifique à un agrégateur** : une interface `PaymentProvider` (créé, initiate, webhook `verify`, refund) avec adaptateurs → changer de fournisseur en une ligne.

**⚠️ Le risque n°1 de votre lancement n'est pas technique : c'est le KYC de l'agrégateur.** Compte marchand = RCCM/statuts, compte bancaire, pièce du dirigeant, et **3 à 10 jours ouvrés** de validation. **Déposez le dossier aujourd'hui.**
**Plan B de lancement (le seul qui garantisse un encaissement à J+5)** : codes d'activation (déjà implémentés) + **« credit licence » manuel dans le dashboard**, avec champ preuve de transaction + identité de l'agent. Vous encaissez par Orange Money de compte à compte, vous prolongez la licence ; l'automatisation arrive en V1.1 quand l'agrégateur est validé.

### 4.6 Le « vrai ultra dashboard admin » — spécification

**Existant** : `server/public/index.html` + `admin.js` (1 035 lignes), 9 onglets (dashboard, carte, abonnés, équipe, codes, utilisateurs, sync, essais, réglages). **Routes API réellement présentes** : `GET /stats`, `GET /map-data`, `GET|POST /staff`, `POST /commercial/activate|ping`, `GET /field-activities`, `GET /users`, `GET /subscriptions` + `PUT /subscriptions/:id`, `GET /analytics/summary|export`, `GET /sync-logs`, activation codes (`GET`, `POST /generate`, `POST /revoke`).
**Verdict** : c'est un tableau de **consultation** avec deux pointes d'écriture — pas un outil de gestion d'app. Les **prix des forfaits sont codés en dur dans le code** (`index.ts:1325-1329` : 150 000 / 15 000 / 5 000) : changer un tarif impose une redéploiement de la Edge Function.

**Modules à construire (avec les routes qui manquent)**

1. **Vue d'ensemble temps réel** — MRR/ARR, encaissé par période, cohortes d'activation J7/J30, taux de renouvellement, taux de churn, top zones (carte), santé de la sync (latence, conflits, appareils non synchronisés > 7 j), file de webhooks. → `GET /admin/overview`, `GET /admin/cohorts`.
2. **Commerces (CRM)** — liste filtrable (plan, statut, pays, agent, dernière connexion, CA), fiche 360 (appareils, membres + permissions, historique d'abonnements, paiements, sync récente, sauvegardes, notes commerciales, journal des actions subies). Actions : suspendre/réactiver, changer de propriétaire, **révoquer un appareil** (la colonne `revoked_at` existe — il manque l'écran), forcer une déconnexion, **effacer un compte** (S15), fusionner deux doublons.
3. **Abonnés & cycle de vie** — essais paramétrables, expiration imminente, grâce, relances automatiques (FCM/SMS/WhatsApp), reports, avoirs, codes promo (% ou montant, plafond d'usage et de date), file de litiges (« je paye depuis 3 mois et je suis bloqué ») avec preuve de transaction.
4. **Plans & forfaits** — CRUD complet (fin des prix codés en dur), tarification par pays/devise, paliers (nb d'appareils, nb d'utilisateurs, modules par secteur), remises, cycles mensuel/trimestriel/annuel avec décote, **versionnage des plans**, et les champs consommés par l'app : `trialDays`, `gracePeriodDays`, `maxOfflineDays`.
5. **Paiements** — table `transactions`, rapprochement par fournisseur, re-jeu d'un webhook, statuts pending/failed/refunded, import manuel (encaissement espèces terrain + photo de preuve), export comptable CSV, tableau d'impayés.
6. **Application & versions** — publication d'une version (`versionCode`, canal, notes, rollout progressif en %), **`minSupportedVersion` = mise à jour obligatoire**, **feature flags + kill switch par module** (couper l'IA, couper un agrégateur, couper un secteur), annonces/bannières in-app, liens de téléchargement, taux d'adoption par version, plantages par version (Sentry). → `GET/POST /v1/config`, `GET/POST /admin/versions`, `POST /admin/flags`.
7. **Équipe & accès** — invitations, rôles fins (`super_admin`, `supervisor`, `commercial`, `support`, `comptable`, `lecture`), **MFA TOTP**, sessions actives + révocation, périmètre géographique des commerciaux, **journal d'audit des consultations** (pas seulement des écritures).
8. **Contenu & acquisition** — catalogues sectoriels **publishables/purgés à distance** (aujourd'hui bundlés dans `assets/catalogue/`, avec `minSectorCatalogSize = 1000` par secteur → poids de l'APK ; à devenir un paquet versionné sur R2), codes de parrainage, campagnes de push segmentées, messages in-app localisés.
9. **Sécurité & conformité** — alertes (N échecs de login, pic de sync, webhook invalide, taux d'erreur anormal), rotation de secrets tracée, registre des suppressions demandées, état des backups, export Data Safety.
10. **Exploitation** — health des dépendances (Neon, agrégateur, SMS, FCM), file de jobs + rejeu idempotent, remontée de logs d'appareil sur opt-in explicite, bascule « mode dégradé », qualité des réponses de l'assistant IA (pouce↑/↓ anonymisé, cf. I3).

**Choix technique du dashboard (gratuit, scalable), par ordre de recommandation**
- **A. Cloudflare Pages + SPA** (React, ou enrichissement du `admin.js` existant) consommant l'API Worker, session courte + TOTP. Coût 0 $, contrôle total, réutilise l'existant. **C'est ce que je retiens.**
- **B. Directus headless posé sur Neon** : CRUD, rôles, médias, webhooks et audit **sans les écrire**. Idéal si le temps de dev est votre contrainte n°1. Contrepartie : un petit serveur à maintenir (Fly/Render, 0–5 $).
- **C. Metabase (self-host gratuit)** par-dessus Neon pour les graphiques métier (MRR, cohortes, churn) : ~30 minutes de mise en place pour 80 % de la valeur BI.
→ **Combinaison conseillée : A (écrans métier) + C (analyse).** B si vous voulez décharger la construction des CRUD.

### 4.7 Migration Supabase → Neon, méthode sans coupure

1. **J1** — `pg_dump --schema-only` depuis Supabase, nettoyage (retirer `auth.`, `storage.`, `realtime`, la plomberie RLS `anon`/`authenticated` inutile puisque l'accès passe par un seul rôle applicatif via le pooler). → `neon_schema.sql`, versionné.
2. **J1** — Projet Neon (gratuit, **région Francfort** = le plus proche de l'Afrique de l'Ouest), pooler PgBouncer en mode transaction, connexion TLS obligatoire. Second projet Neon pour le **staging** (B6).
3. **J2** — Port des 8 migrations existantes. **Point clé : `register_business_atomic`, `record_sync_event`, `record_sync_batch` et `process_payment_webhook` sont des fonctions PL/pgSQL standard → portables telles quelles.** C'est là qu'est l'essentiel de la valeur du portage, et c'est ce qui rend l'étape courte.
4. **J2** — Import des données (`--data-only`, 8 tables métier) + **double vérification** : comptage de lignes et empreinte des `sync_events` récents.
5. **J2-J3** — Réécrire la passerelle **une seule fois** : traduction mécanique des handlers `handleRegister`, `handleValidateCode`, `authorizeSync`, `handleSubscriptionStatus`, `handleAnalyticsIngest`, `handleAdmin`, `handleWebhook` — on remplace `supabase-js` par un client Postgres, **et on supprime `privileged: true` (S2)**. Les contrats de réponse restent identiques → le code Dart du mobile ne change pas (sauf licence et OTP).
6. **J3** — Cohabitation : les appareils déjà installés gardent leur `syncEndpoint` stocké et continuent sur Supabase ; les nouvelles installations pointent sur l'URL Worker. Vous êtes en **pré-lancement** → cette contrainte est quasi nulle aujourd'hui, et deviendra très coûteuse dès le premier client. **Profitez-en maintenant.**
7. **J3** — Basculer `AppConfig.cloudApiBase`, tester la sync **sur un appareil physique**, y compris les scénarios conflit / perte réseau / coupure en plein batch.
8. **J4-J5** — Backups : `pg_dump` quotidien → **R2** (egress 0), chiffré (age ou SSE), **restauration testée et chronométrée** ; + **agrégation et purge de `sync_events` à 90 jours** (sinon le Neon gratuit meurt en ~3 semaines).
9. **J5** — Supabase maintenu **30 jours en lecture seule** comme roll-back, puis suppression.

**Ce que vous perdez, et par quoi c'est remplacé**

| Supabase | Remplacement | Coût |
|---|---|---|
| Auth (de fait **non utilisée** par le mobile) | Firebase Auth + OTP auto-hébergé (§4.4) | 0 $ hors envoi |
| Edge Functions | Cloudflare Worker (ou Function Firebase) | 0 $ (100k req/j) |
| Storage (backups chiffrés) | Cloudflare R2 | 0 $ (10 Go, egress gratuit) |
| PostgREST auto-API | vous ne l'utilisiez pas (tout passait par la fonction) | — |
| Realtime | FCM (push) + polling de sync | 0 $ |
| Studio, logs, SQL editor | console Neon + Metabase + Sentry | 0 $ |
| RLS | **périmètre `business_id` explicite dans le Worker + tests d'intrusion croisée** | 0 $ |

**Traduction honnête** : vous échangez « une brique tout-en-un commode mais facturée à l'usage et opaque » contre « 4 briques gratuites qu'il faut assembler et surveiller vous-même ». À votre échelle (pré-lancement, < 1 000 commerces), c'est le bon choix — à condition d'accepter que **vous** serez l'opérateur de 4 comptes : 2FA + e-mail de secours + alertes de quota sur chacun, dès le jour 1.

---

## 5. Backend & API — autres constats

- **B1 — Deux backends concurrents** : `server/` (Express + SQLite, `routes_admin.js`, `apply_remote.js`, `sync_server.dart`) **et** `supabase/functions/lynkstor-api/index.ts` (2 047 lignes). Chacun a sa propre implémentation de la sync, de l'admin et des webhooks → dérive fonctionnelle inévitable, et l'un des deux n'est de fait jamais testé. **Décision** : garder **une** passerelle (celle qui tourne réellement → la Edge Function, portée sur Neon) ; `server/public/` devient le front d'administration, le reste d'`server/` est archivé.
- **B2 — `service_role` détenue uniquement par la passerelle** : correct. Mais la passerelle ne restreint pas assez (S14) et utilise un `ADMIN_API_KEY` à vie (S5).
- **B3 — `/api/v1/analytics/ingest` en clé anon** : conforme (pas de PII), **mais** à valider par schéma strict + quota, sinon vos statistiques d'essai se laissent polluer depuis l'extérieur.
- **B4 — Webhook `x-webhook-signature: sha256=<hex>`** avec HMAC sur le corps **brut** et `process_payment_webhook` idempotent : bonne base à conserver telle quelle ; y ajouter le contrôle de **fraîcheur du timestamp** (anti-rejeu).
- **B5 — `analyticsIngestUrl` vide** (`app_config.dart:60`) : la collecte Drive est silencieusement inopérante ; le folder Drive et le `_headers` Cloudflare sont publiés en dur dans le code client (`analyticsDriveFolderId`) — à ne pas considérer comme un secret, et à documenter.
- **B6 — Aucun environnement `staging`** : tout est en dur dans `AppConfig`, un seul projet cloud. Sans séparation, chaque test salit vos vraies données et votre futur tableau de bord. → `--dart-define=API_BASE,ENV` + un 2ᵉ projet Neon.
- **B7 — MethodChannel Android jamais validé sur matériel réel** : `KNOWN_LIMITATIONS.md:6` dit lui-même « valider **imprimante réelle** sur terrain ». L'impression 58/80 mm ESC/POS est un argument de vente : à tester avec l'imprimante que vos clients achèteront.
- **B8 — `AppConfig.packageId = com.kumba.kumba_business` et le projet s'appelle encore `kumba_business`** partout (pubspec, namespace Android, `kumba_business_android.iml`) alors que la marque est Lynkstor. **C'est maintenant, avant le premier dépôt Play Store, que c'est gratuit** : après, changer l'`applicationId` = republier une nouvelle app et perdre l'historique/les avis.
- **B9 — La doc technique (`docs/`) contient 25 fichiers dont beaucoup se contredisent** (3 directions de design, `KUMBA_*` vs `Lynkstor_*`, `MASTER PROMPT .md` avec espace dans le nom). À consolider : une `README` de vérité + un `docs/STATUS.md`, le reste archivé. Une doc fausse est plus dangereuse qu'une absence de doc.

---

## 6. IA locale & assistant Lynk

**Le seul domaine où il y a peu à changer — protège-le.**

- ✅ Lecture seule stricte ; réponses déterministes branchées sur la base locale pour les questions chiffrées (CA, dettes, stock, bénéfice) : le modèle **ne peut pas inventer un chiffre critique**. C'est exactement le bon architecture de garde-fou.
- ✅ Zéro appel réseau → aucun risque de fuite de données clients, et un argument commercial fort (« vos chiffres ne quittent jamais le téléphone ») à exploiter dans la fiche Play.
- ⚠️ **I1 — 206 Mo de GGUF dans `assets/models/` + `noCompress += "gguf"`** (donc **non compressés**) → le module de base de l'AAB dépasse la limite Play (≈ 200 Mo compressés ; 206 Mo non compressés suffisent à la faire sauter). **Risque d'échec d'upload.** Trois options :
  1. **Play Asset Delivery**, pack *install-time* ou *on-demand* (Google héberge et livre ; jusqu'à 1,5 Go par pack) — propre, mais lié à Play.
  2. **Cloudflare R2 + téléchargement à la demande** (egress 0 $, CDN, pause/reprise, vérification SHA-256) → **celle que je recommande** : l'APK retombe à ~35 Mo, et le même mécanisme sert au catalogue sectoriel (§4.6 module 8).
  3. Modèle plus petit embarqué (Q4_K_S/0,5B réduit) + Q2_K en téléchargement optionnel.
- ⚠️ **I2 — Copie en streaming depuis les assets au 1ᵉʳ lancement** : 206 Mo sur un téléphone d'entrée de gamme = longue, interrompable ; `_downloadProgress` est déclaré mais **non utilisé** (`flutter analyze` : `unused_field`, ligne 39) → pas d'indicateur de progression réel. Reprendre sur un flux partiel R2 + checksum est plus robuste.
- ⚠️ **I3 — Aucune mesure de qualité des réponses** : pouce↑/↓ local + agrégat anonyme dans `trial_analytics_events`, visible dans le dashboard (module 10). Sinon vous ne saurez jamais si Lynk se trompe.
- ⚠️ **I4 — Pas de repli** : si l'utilisateur refuse le téléchargement du modèle, ou si le device n'a pas assez de RAM, l'écran assistant doit offrir une alternative (FAQ déterministe + guide), pas un bouton mort.
- ⚠️ **I5 — Mémoire/perf non mesurées** : un modèle de 0,5B quantifié Q2_K avec `llama_flutter_android` sur un téléphone à 3 Go de RAM (cœur du marché cible) doit être **profilé en release sur l'appareil le plus faible vendu chez vos distributeurs**, pas en debug sur desktop.
- 💡 **I6 — Futur « Lynk Plus »** : gros modèle hébergé (crédits gratuits Groq/OpenRouter/Nebius) avec **consentement explicite** et envoi d'un **contexte agrégé et anonymisé uniquement** — jamais de noms de clients ni de numéros de téléphone. À monétiser dans un plan supérieur.

---

## 7. Qualité, tests, release

- **T1 — `flutter analyze` (exécuté ce jour) : 7 issues, 0 erreur.** `unused_field _downloadProgress`, `_downloading` non-`final` (`ai_assistant_screen.dart:38-39`), import inutilisé + 3 `withOpacity` dépréciés (`return_receipt_screen.dart`), import relatif dans `test/unit/billing_and_accounting_test.dart`. Nettoyage : 30 minutes.
- **T2 — `flutter test` (exécuté ce jour) : 102 ✓ / 5 ✗ / 1 ⊘.** Les 5 échecs = U1 (×2), U8, U9, U10. **Aucun ne doit rester rouge au moment de signer la release**, et surtout pas **U10**, qui touche à l'intégrité des données en upgrade.
- **T3 — `integration_test/app_smoke_test.dart` existe mais n'est pas dans la boucle de release.** À lancer sur un appareil physique avec **le APK final signé**, en FR et en EN.
- **T4 — Aucun dépôt Git** (`git status` → « not a git repository ») : pas d'historique, pas de réversion, pas de CI, et un `rm -rf` suffit à perdre le projet. **À initialiser en tout premier** (Jour 1, avant toute ligne de code), avec un `.gitignore` strict : `key.properties`, `*.jks`, `server/.env`, `deploy/secrets.local.env`, `supabase/.temp`, `build/`, `.dart_tool/`, `.gradle/`, `models/`, `assets/models/*.gguf`, `.wrangler/`.
- **T5 — Versioning** : `1.2.0+12` cohérent entre `pubspec.yaml`, `AppConfig.version/buildNumber` et le `versionCode` Flutter. Vérifier qu'aucune version antérieure n'a été distribuée publiquement, sinon ne jamais redescendre le `versionCode`.
- **T6 — Pas d'outillage de release automatisé vérifié** : `tool/build_release_apk.ps1` existe (bon : refuse le build release sans `key.properties`, `-Bundle` pour l'AAB, `--Split-debug-info`). Il faut l'exécuter avec `-Bundle` pour Play Store et **conserver les symboles de debug** pour dépiler les stack traces Sentry.
- **T7 — CI absente** → GitHub Actions gratuit : `analyze` + `test` + `build apk --release` à chaque push sur la branche de release. Sans ça, la checklist §11 ne peut pas être certifiée.


---

## 8. Plan d'exécution sur 5 jours

> Hypothèse : **1 développeur à temps plein** + vous pour les décisions et le KYC. La migration backend complète, l'OTP, la licence payable et le build signé tiennent dans les 5 jours. **La refonte visuelle intégrale et le dashboard « ultra » complet non** — ils sont explicitement planifiés en V1.1 (§8.2), avec un plan B qui ne bloque pas l'encaissement.

### Jour 1 — Fondations et arrêt des hémorragies
- [ ] **`git init` + `.gitignore` strict + premier commit + dépôt privé** (avec `key.properties`, `*.jks`, `.env`, `*.gguf` exclus). Copie chiffrée du keystore hors machine (S11). **Première action de la journée, avant même une ligne de code.**
- [ ] Corriger les docs périmés qui peuvent faire casser ce qui marche : `deploy/NEXT_STEPS.md` (la fonction **est** déployée), `KNOWN_LIMITATIONS.md` (mobile money = référence manuelle, pas « ✅ »).
- [ ] Réparer **U1** (débordement dashboard), **U5** (reprise d'erreur caisse), **U10** (migration) → `flutter test` entièrement vert.
- [ ] Sécurité immédiate, sans dépendre de la migration : **S2** (supprimer `privileged`), **S5** (tuer le bearer = clé), **S7** (repli en clair), **S10** (rotation des secrets), **S4** (CORS restreint).
- [ ] Créer les comptes : Neon (prod + staging, région FRA), Firebase (Spark), Cloudflare (Workers/Pages/R2), Sentry — **2FA + alertes de quota + e-mails de secours sur les 4**.
- [ ] **Déposer le dossier KYC agrégateur aujourd'hui** (CinetPay **et** SenePay en parallèle) → c'est le chemin critique business (§4.5).
- [ ] Trancher **S3** (`requireAgentActivationCode`, `allowDemoMode`) et le modèle d'essai (ex. 14 jours **datés côté serveur**).

### Jour 2 — Passerelle sur Neon
- [ ] Porter le schéma + les 8 migrations/fonctions PL/pgSQL ; importer les données ; vérifier les comptages.
- [ ] Réécrire le Worker API (`sync push/pull`, `register`, `validate`, `subscription`, `analytics`, `admin`, `webhook`) avec un client Postgres ; **contrats de réponse identiques** → le Dart de la sync ne change pas.
- [ ] **S1** : `POST /v1/license/verify` renvoie un statut **signé** (HMAC + nonce + `iat` + `maxOfflineDays`) ; l'app stocke le blob signé ; suppression du `source == 'local' → autorisé` pour un appareil lié ; horloge serveur.
- [ ] **S6** : limitation de débit + verrouillage progressif sur toutes les routes non authentifiées.
- [ ] **S8** : `GET /v1/config` (`minSupportedVersion`, `latestVersion`, `announcement`, `killModules[]`) + son exploitation côté app.
- [ ] Tests d'intrusion croisée : le commerce A tire les données de B → **deux échecs attendus et vérifiés** (`sync/pull`, `backups`, `subscription`).

### Jour 3 — Identité OTP + notifications + observabilité
- [ ] `otp_challenges` (Neon) + routes `request`/`verify` + normalisation E.164 + limitation de débit + code de test backdoor désactivé en prod.
- [ ] Choisir et brancher le canal (WhatsApp / SMS régional **ou** Firebase Phone natif) — cf. §4.4 et la décision à valider.
- [ ] Firebase : `google-services.json`, `firebase_auth`, `signInWithCustomToken`, mappage `auth_uid` ↔ utilisateurs, récupération de commerce sur nouvel appareil par numéro (**U14**).
- [ ] **FCM** : token d'appareil, topics par `business_id`, envoi depuis l'API (expiration de licence, sync en échec, message de l'admin).
- [ ] **S12** : Sentry (crash + `buildNumber` tag) + **S9** : R8/minify activé et re-testé.
- [ ] Écrans **U13** (erreurs OTP localisées FR/EN).

### Jour 4 — Licence payable + administration
- [ ] Tables `plans` (CRUD, prix par pays, `trialDays`, `gracePeriodDays`, `maxOfflineDays`), `transactions`, `payment_intents`, `coupons`.
- [ ] Interface `PaymentProvider` + adaptateur agrégateur (checkout + webhook HMAC + fraîcheur + idempotence + rejeu). **Si le KYC n'est pas validé → mode « crédit manuel »** avec preuve de transaction et identité de l'agent (plan B assumé, pas une dette).
- [ ] Parcours complet dans l'app : bandeau d'expiration → renouvellement (choix du forfait, numéro, paiement, attente, confirmation) → expiration avec **verrouillage progressif et données intactes** → reçu PDF d'abonnement. **C'est le parcours qui fait le revenu : à finir avant d'ajouter un seul autre écran.**
- [ ] Dashboard : module Plans (CRUD), module Commerces (recherche + fiche 360 + **révoquer un appareil**), module Paiements (liste + rejeu webhook + crédit manuel), module Versions/Flags, MFA TOTP `super_admin`, `admin_audit_log` avec motif obligatoire (S14).
- [ ] **S15** : suppression de compte + export des données (obligation Play + conformité).

### Jour 5 — Durcissement, build, soumission
- [ ] Sortir le GGUF de l'APK (**I1** option R2) + téléchargement à la demande avec SHA-256 et reprise ; vérifier la taille de l'AAB.
- [ ] P1 UI restants : **U2** (contraste/actionSurface), **U4** (fausses métriques), **U3** (navigation unique), **U7** (reduced-motion).
- [ ] Exécution complète : `flutter analyze` = 0 issue, `flutter test` = 100 % vert, `integration_test` **sur téléphone physique avec l'APK final signé** (parcours : onboarding OTP → vente → reçu → dette → stock → sync hors ligne → retour en ligne → expiration simulée → renouvellement), en FR **et** en EN.
- [ ] **Purge/agrégation de `sync_events` à 90 jours** + `pg_dump` quotidien vers R2 + **restauration testée chronométrée**.
- [ ] Play Console : internal test track, formulaire Data Safety, note de contenu, **formulaire d'inclusion des méthodes de paiement alternatives**, politique de confidentialité publiée, descriptions et captures à jour FR/EN.
- [ ] Runbook d'incident écrit (rotation de secret, révocation d'appareil, annulation d'un plan, rejeu d'un webhook, restauration Neon, bascule d'agrégateur, kill switch d'un module) + **une deuxième personne formée**.
- [ ] **Gel du code** : après le jour 5, uniquement des correctifs.

### 8.2 Sorti du périmètre 5 jours → V1.1 (semaines 2 à 4)
Refonte visuelle complète (direction de design unique, dark mode intégral, goldens à jour), modules 8-9-10 du dashboard (cohortes, campagnes de push, BI Metabase, alertes), automatisation de l'agrégateur dès le KYC validé, catalogues sectoriels en paquets téléchargeables pour tous les secteurs, `performanceMode` mesuré sur appareil bas de gamme, programme de parrainage, devises/pays supplémentaires, « Lynk Plus » (IA cloud, I6), iOS (toujours hors périmètre délibéré).

---

## 9. Ce à quoi vous n'aviez pas pensé (liste à cocher)

**Business, juridique, distribution**
1. **KYC de l'agrégateur = votre vrai chemin critique** (3 à 10 jours ouvrés) → déposé le jour 1, avec le **plan B de crédit manuel** sans lequel vous ne pouvez rien encaisser au lancement.
2. **Play Billing + « méthodes de paiement alternatives »** : Google peut rejeter une app qui propose un abonnement payé hors Play sans le formulaire dédié. À préparer avec un texte exact.
3. **Reçu/quitance d'abonnement** (PDF, pas seulement celui du client final) : vos acheteurs B2B en ont besoin pour leur comptabilité — `pdf` + `printing` sont déjà dans les dépendances.
4. **CGU + clause de résiliation + politique de remboursement** : inexistantes aujourd'hui (seul `docs/PRIVACY_POLICY.md` existe). On ne fait pas payer sans.
5. **Formalité ARTCI (CI) / ANINF (Cameroun)** pour le traitement de données personnelles + déclaration du site publié.
6. **Canal de support visible dans l'app** (WhatsApp Business ou e-mail partagé) : sans lui, les avis 1 étoile arrivent avant votre premier message.
7. **Document de continuité / propriété des accès** : qui possède Cloudflare, Firebase, Neon, le domaine, le compte marchand, le keystore ? Un seul humain avec tous les accès = entreprise non vendable et bloquée le jour où il part.
8. **Pricing en FCFA et perception du paiement** : 15 000 F par mois pour une boutique de quartier, c'est un arbitrage quotidien. Prévoir le **journalier/hebdomadaire** (ex. 1 500 F par semaine) ou un plan « démarrage » bas — c'est un levier de conversion, pas un détail.
9. **Conversion demo → payant** : `allowDemoMode = true` crée des utilisateurs qui ne deviennent jamais clients s'il n'y a pas de pont explicite « je crée mon commerce pour de vrai ».

**Technique et exploitation**
10. **Télémétrie de plantage** (S12) et **alertes de quota** sur chaque fournisseur : sinon vous apprenez par les avis du store et par une facture.
11. **Mise à jour obligatoire + kill switch** (S8) : sans ça, un bug de la caisse paralyse tout le parc sans aucun recours.
12. **Croissance non bornée de `sync_events`** : tue le Neon gratuit et ralentit la pull ; l'archivage/agrégation n'est pas optionnel.
13. **Restauration réellement testée** (pas seulement création de backup) + vérification chiffrée.
14. **Environnement staging séparé** (B6) : sans lui vous testez sur les données de vos clients.
15. **Horloge de l'appareil** : date fausse = licence expirée crue valide → vérifier contre le serveur (inclus dans S1).
16. **Multi-appareils par commerce** : aujourd'hui non borné ; la limite par plan + la révocation d'appareil sont votre meilleur levier anti-partage de compte.
17. **Poids de l'APK et coût data** : votre cible télécharge sur un réseau payant ; livrer ~250 Mo est un **handicap commercial**, pas qu'un sujet technique (voir I1 + §4.6 module 8).
18. **RAM/batterie** : llama.cpp + modèle de 206 Mo sur un téléphone à 3 Go — à mesurer en **release sur l'appareil le plus faible** distribué chez vous (I5).
19. **Validité du PIN à 4 chiffres** (`pinLength = 4`, `maxPinAttempts = 5`) : le PIN n'est qu'une barrière d'usage local (la clé de base est aléatoire, donc pas de risque crypto) — **mais** c'est ce que vos clients vont percevoir comme « la sécurité de leur caisse » : documenter honnêtement dans `SECURITY.md` et proposer la biométrie par défaut (`local_auth` est déjà là).
20. **Sauvegardes sur stockage partagé** (S18) : `requestLegacyExternalStorage` + permissions de lecture → un backup sur la carte SD se lit avec n'importe quel explorateur.
21. **Reprise de sync après 30 jours hors ligne** : à tester explicitement (curseur, volume, conflits, mémoire).
22. **Plan de secours hors OTP** : ligne perdue, portable volé, portabilité → récupérer son commerce (code agent + pièce), sinon litige et avis négatif.
23. **Coûts récurrents invisibles** : OTP à chaque reconnexion (d'où sessions longues + re-vérification de licence à 7 jours), egress hors R2, dépassement Neon, MAU Firebase → **plafonds d'alerte** sur chaque compte dès le jour 1.
24. **Redondance du keystore** (S11) : le perdre, c'est perdre l'app sur Play Store définitivement.
25. **Identifiant technique verrouillé** (B8) : `com.kumba.kumba_business` est encore le nom de la marque précédente — changer l'`applicationId` après le premier dépôt = repartir de zéro sur le store.
26. **Documentation divergente** (B9) : 25 fichiers `docs/` qui se contredisent, dont une doc de sécurité annonçant des fonctionnalités absentes → un `docs/STATUS.md` unique et honnête, le reste archivé.

---

## 10. Estimation des coûts de la cible

| Parc | Infrastructure / mois | Détail |
|---|---|---|
| 0 – 200 commerces | **0 – 5 $** | Tout sur plans gratuits ; seul poste payant : les OTP (crédit prépayé, ~15–30 $ de capital de départ, consommable) |
| 200 – 1 000 commerces | **35 – 90 $** | Neon Launch (0,106 $/CU-h) + Firebase Blaze (dépassements Firestore/Storage) + OTP négocié au volume + R2 au-delà de 10 Go |
| 1 000 – 5 000 commerces | **150 – 400 $** | + Workers Paid (5 $) + limitation de débit dédiée + base plus grosse + support |

**Repère de marge** : à 300 commerces × 15 000 F CFA (≈ 25 $) = **≈ 7 500 $ de revenu mensuel** pour 35–90 $ d'infrastructure. **L'infrastructure n'est jamais votre problème de marge** : ce sont **la commission de l'agrégateur (2 à 4 %)** et **le coût à l'OTP** qui le sont. D'où trois règles de conception : OTP par WhatsApp quand c'est possible, sessions longues + re-vérification de licence espacée (7 jours) pour ne pas re-consommer d'OTP, et **un seul agrégateur avec un repli** plutôt qu'une accumulation de passerelles.

---

## 11. Checklist Go / No-Go (à signer le jour 5)

- [ ] `flutter analyze` = 0 issue et `flutter test` = 100 % vert (les 5 échecs du 24/09 corrigés, **dont la migration U10**).
- [ ] Sync complète prouvée sur **2 appareils physiques** + 24 h hors ligne puis rejeu.
- [ ] Lecture croisée entre 2 commerces → **échec vérifié** (test d'intrusion consigné).
- [ ] Un APK release décompilé ne contient **aucune** clé partagée (`ADMIN_API_KEY` / `SYNC_API_KEY`), et la licence n'est pas modifiable sans échec de signature.
- [ ] Cycle de paiement réel complet : achat → webhook reçu → licence prolongée → app débloquée (ou crédit manuel avec preuve tracée).
- [ ] Expiration simulée → verrouillage progressif → **aucune donnée perdue** → renouvellement → déblocage.
- [ ] `minSupportedVersion` supérieur à la version installée → l'app refuse la caisse et renvoie vers la mise à jour.
- [ ] Révocation d'un appareil depuis le dashboard → sync de cet appareil coupée en moins de 5 minutes.
- [ ] Restauration d'une sauvegarde Neon sur un environnement vierge, **chronométrée et réussie**.
- [ ] `pg_dump` planifié + purge `sync_events` planifiée + alertes de quota actives sur les 4 fournisseurs.
- [ ] Sentry reçoit un plantage de test ; le `buildNumber` apparaît dans l'entrée.
- [ ] 2FA + e-mails de secours à jour sur Cloudflare, Firebase, Neon, agrégateur, Play Console, **et keystore sauvegardé hors machine**.
- [ ] Play : Data Safety, note de contenu, formulaire de méthodes de paiement alternatives, politique de confidentialité en ligne, version internal test validée par Google.
- [ ] Runbook d'incident écrit et **une deuxième personne** capable de l'exécuter.
- [ ] Code gelé : depuis cette signature, uniquement des correctifs.

---

## 12. Décisions à valider par vous pour demarrer

| # | Décision | Ma recommandation | Pourquoi ça bloque |
|---|---|---|---|
| D1 | Périmètre des 5 jours | **Sécurité + Neon + OTP + licence payable + build** ; UI et dashboard en V1.1 | Aucun autre périmètre n'aboutit réellement en 5 jours |
| D2 | Modèle économique au lancement | **Essai 14 jours daté côté serveur → abonnement, avec crédit manuel des agents en attendant le KYC** | Détermine S1, S3, les écrans U11 et le module 4 du dashboard |
| D3 | Canal OTP | **OTP auto-hébergé + Firebase Custom Token** (WhatsApp ou SMS régional prépayé) | Firebase Phone natif exige une carte + un coût par SMS non maîtrisable ; PNV indisponible dans la zone |
| D4 | Agrégateur | **CinetPay en principal, SenePay en parallèle** ; interface `PaymentProvider` | Dossier KYC à déposer **aujourd'hui**, pas après la migration |
| D5 | Où vit l'API | **Cloudflare Worker** (plutôt qu'une Function Firebase) | Conditionne la facturation et le portage des contrats de réponse |
| D6 | Poids de l'app | **Sortir le GGUF de l'APK → R2 + téléchargement à la demande** | Sans ça l'upload Play peut échouer, et 250 Mo est un frein commercial |
| D7 | Identifiant Android | Statuer maintenant sur `com.kumba.kumba_business` vs `com.lynkstor.*` | Gratuit avant le premier dépôt, coûteux après |

---

*Généré à partir d'une inspection directe du dépôt le 24/09/2026 : `flutter analyze` et `flutter test` exécutés, API interrogée en ligne, code Dart / Deno / SQL / Gradle lu intégralement sur les zones concernées, et chiffres de pricing revérifiés auprès des sources officielles (neon.com/pricing, firebase.google.com/pricing, firebase.google.com/docs/auth/limits, firebase.google.com/docs/phone-number-verification/pricing) et des pages agrégateurs.*
