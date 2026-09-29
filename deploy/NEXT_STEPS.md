# Déploiement — état réel (Neon) & étapes restantes

> ⚠️ Ce fichier décrivait l'ancien backend **Supabase** (`wtbmwquovcizrtggkkzn`).
> Il est obsolète : la production tourne désormais sur **Neon** (gateway
> `functions/api/index.ts` déployée en Neon Function) + dashboard statique
> hébergé sur Cloudflare.

## En place (vérifié E2E 59/59 en prod)

| Composant | URL / commande |
|---|---|
| Gateway API Neon | `https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech` (`/health`, `/api/v1/*` : register, sync, licences Ed25519, webhooks, dashboard admin complet, analytics période test) |
| Redéploiement gateway | `npm run deploy` (= `neon deploy --env .env.local`) |
| Dashboard admin (public) | `https://sweet-bush-a7e8.wosee-connect.workers.dev` — bundle généré par `node deploy/cloudflare/prepare.mjs`, poussé par `npx wrangler deploy` depuis `deploy/cloudflare/` |
| IA hybride « Lynk » | `POST /ai/ask` + `GET /ai/health` sur le MÊME Worker (`deploy/cloudflare/worker.mjs`, binding Workers AI, clé anon `x-lynkstor-anon`) — déployé et prouvé en live 2026-09-25 ; voir [docs/LOCAL_AI.md](../docs/LOCAL_AI.md) |
| Vérification E2E | seed `powershell -File tool/seed_e2e_demo.ps1` (credentials via `E2E_ADMIN_USERNAME`/`E2E_ADMIN_PASSWORD`) puis `node tool/verify_neon_backend.mjs` |
| Nettoyage prod | `Get-Content tool/purge_neon_demo.sql -Raw \| neon psql production --role-name neondb_owner` |
| Paiement abonnement **PawaPay** | Routes gateway `POST /api/v1/payments/initiate`, `GET /api/v1/payments/{intentId}`, `POST /api/v1/payments/pawapay/webhook`. **Nécessite** `PAWAPAY_API_TOKEN` dans `.env.local` puis `npm run deploy`. Voir section « Paiement Mobile Money » ci-dessous. |

## Paiement Mobile Money des abonnements (PawaPay)

**Modèle push PawaPay** : la demande de paiement arrive sur le téléphone du
payeur (MTN MoMo / Orange Money), qui la confirme avec SON code secret
opérateur. Le PIN/OTP mobile ne transite **jamais** par Lynkstor, et l'app ne
reçoit **aucun** secret agrégateur : elle ne parle qu'au gateway Neon, qui
résout seul le montant (table `plans`/`subscriptions`) et détient le token
PawaPay.

**Le callback est OPTIONNEL.** L'API PawaPay est asynchrone et offre deux voies
vers le statut final : callback **ou** polling « Check Status ». Lynkstor
utilise le polling :

1. l'app `initiate` → le gateway crée une `payment_intent` (idempotence par
   `depositId` = UUID) et pousse la demande ;
2. l'app affiche « en attente de confirmation » et **sonde**
   `GET /api/v1/payments/{id}` (le gateway ré-interroge PawaPay, ne croit
   jamais le corps d'un callback) ;
3. dès `COMPLETED` (montant vérifié), le gateway **active l'abonnement et émet
   la licence Ed25519** de façon atomique/idempotente.

Filet de sécurité offline-first : si l'app est fermée avant la confirmation,
un paiement abouti en arrière-plan est rattrapé **à la prochaine ouverture**
(`refreshSubscription` → le gateway re-réconcilie l'intention en attente la
plus récente). Aucun hébergement de callback n'est donc requis.

**Activer en production :**
1. Coller le token PRODUCTION PawaPay dans `.env.local` (`PAWAPAY_API_TOKEN=`)
   — jamais dans le dépôt ni dans l'APK ;
2. `npm run deploy` ;
3. (recommandé, améliore la latence) dans le **dashboard PawaPay**, renseigner
   l'URL de callback :
   `https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech/api/v1/payments/pawapay/webhook`
   — le gateway ré-interroge PawaPay de toute façon, donc activer « Sign all
   callbacks » est sans risque ;
4. vérifier le pays/ devise si hors Cameroun : `PAWAPAY_COUNTRY`,
   `PAWAPAY_CURRENCY` (XAF), `PAWAPAY_DIAL_CODE` (237), correspondants
   `PAWAPAY_CORR_ORANGE` / `PAWAPAY_CORR_MTN`.


## Étapes restantes — à la main du client (actions sensibles)

1. **Comptes admin permanents** : ✅ créés le 2026-09-25 via l'outil
   `node tool/seed_admin_permanent.mjs` (hash pbkdf2 local, mdp jamais stocké
   dans le repo ni la doc). Deux `super_admin` actifs : `MIGUEL` et `OSCAR`.
   Login dashboard → `Se connecter` (utilisateur + mot de passe), insensible à
   la casse. ⚠️ **Ces deux mots de passe ont transité dans un chat : les
   changer à la première connexion** — modifier le champ `password_hash` en SQL
   (ou la route admin staff/update) incrémente `token_version` et révoque donc
   les sessions déjà émises avec l'ancien mdp. L'outil est re-jouable pour cela.
   Login + `/admin/stats` validés en live (200) pour les deux comptes ; mauvais
   mdp → 401.
2. **Rotater la clé `napi_…` qui a fuité** dans le chat (tableau de bord Neon →
   API keys), puis mettre à jour `.env.local` / secrets Neon si utilisée.
3. **`git init` + premier commit** : `git init` FAIT le 2026-09-25 avec audit
   de sécurité préalable — 429 fichiers stagés, AUCUN secret stage (vérifié :
   `key.properties`, `*.jks`, `secrets.local.env`, `.env`, `.env.local`,
   `server/.env` tous ignorés ; grep staging sur les motifs de secrets réels
   = 0). Deux fuites corrigées au passage : mot de passe admin par défaut
   retiré de `deploy/push_all.ps1` (désormais : échec si `ADMIN_PASSWORD`
   absent) et de `secrets.local.env.example` (placeholders).
   ➕ Contrôle complémentaire du 2026-09-26 : un JWT Supabase legacy était
   encore codé en dur dans `lib/core/config/app_config.dart` et 3 scripts
   `server/*_supabase*.js` → retiré (routes Neon publiques, vérifié en live :
   `/api/v1/register/validate` et `/v1/config` répondent sans header apikey) ;
   preuve binaire : le JWT ne figure plus dans libapp.so de l'APK 121029.
   ⚠️ Reste à faire par le client : corriger l'identité git (actuellement
   `user.name = "Votre Nom Complet"`, placeholder) puis valider le premier
   commit. Si l'ancien backend Supabase Edge Functions est encore vivant, son
   mot de passe admin d'origine (⛔ ne jamais réécrire en clair dans le dépôt)
   est considéré compromis (il a vécu dans un script) → le changer avant toute
   réutilisation du projet Supabase `wtbmwquovcizrtggkkzn`.
4. **Analytics mobiles → Neon** : ✅ câblé puis rendu effectif le 2026-09-25 —
   `AppConfig.analyticsIngestUrl` = `'$cloudApiBase/api/v1/analytics/ingest'` ;
   requête au format exact de l'app validée contre la prod (`node
   tool/probe_analytics_ingest.mjs` → `accepted=2`, events purgeés depuis).
   APK rebuildé le 2026-09-25 (`lynkstor-20260925-133515-release.apk`, 41,1 Mo,
   arm64, IA hybride) : l'ingest est actif dans ce build.
5. **Recette terrain du build IA hybride** : installer le dernier APK
   (`lynkstor-20260926-121029-release.apk`, 41,21 Mo, SHA-256 `B17D0831…` —
   cerveau hors ligne
   élargi à ~20 familles de questions, voir [docs/LOCAL_AI.md](../docs/LOCAL_AI.md))
   sur un téléphone client ; vérifier badges « Calcul local » / « Llama 3.2-3B ·
   cloud », repli honnête en mode avion, et brouillon fournisseur. En mode AVION,
   tester les questions élargies : « bénéfice ce mois », « hier ça a donné quoi »,
   « combien de clients », « que me doit Paul », « il reste quoi en stock »,
   « meilleurs produits », « invendus ».
