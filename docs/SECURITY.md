# Sécurité — Lynkstor Business

État consolidé le 2026-09-26 (avant déploiement). Chaque point a été vérifié
dans le code, pas seulement conçu.

## Interdictions produit

- Ne jamais demander le code secret Mobile Money / PIN opérateur / mot de passe
  bancaire. Mobile Money = enregistrement de la référence transaction communiquée
  par le client, jamais les identifiants.

## Appareil (offline-first)

- **Base de données chiffrée SQLCipher** (AES, clé aléatoire 256 bits générée
  par `crypto` et stockée dans EncryptedSharedPreferences). Le moteur est
  contrôlé à l'ouverture (`PRAGMA cipher_version`) : si SQLCipher est
  absent, l'app **refuse de démarrer** plutôt que de créer une base en clair.
- **PIN et mot de passe** : PBKDF2-SHA256 **120 000 itérations** + sel
  aléatoire 192 bits, comparaison en temps constant ; les anciens hashes
  SHA-256 sont migrés automatiquement vers PBKDF2 à la première connexion réussie.
- **Anti-énumération PIN** : 5 échecs → verrouillage 5 min (compteurs dans
  le stockage chiffré, inaccessibles sans déverrouiller l'appareil).
- **Aucun secret dans SharedPreferences** : uniquement `performance_mode`
  (booléen non sensible). Tokens, clés, licence → `flutter_secure_storage`
  (EncryptedSharedPreferences Android).
- **Sauvegardes locales** : AES-256 + IV aléatoire + checksum SHA-256 ;
  sauvegarde cloud chiffrée côté client avant envoi.
- **Logs** : aucun PIN/mot de passe/token dans les logs ; actions critiques
  tracées dans `audit_logs` (ventes, dettes, backups, produits…).
- **Backup Android désactivé** (`allowBackup=false`, `fullBackupContent=false`)
  → extraction adb non consentie du data dir inutilisable (base chiffrée de
  toute façon).

## Canal cloud (gateway Neon)

- **Transport** : HTTPS uniquement (aucun `usesCleartextTraffic`), toutes les
  routes production appelées par l'app sont sur le gateway Neon.
- **Auth appairage appareil** : jeton sync `lynk_…` 264 bits par appareil,
  révocable côté admin (`device_sync_tokens.revoked_at`).
- **Licences** : jetons **Ed25519** signés serveur, vérifiés hors ligne côté
  app (grâce offline adossée à la signature, pas à un flag). La clé privée ne
  vit que dans `server/.env` (ignoré git ; audit staging : 0 « PRIVATE KEY »).
- **Codes d'activation** : `LYNK-XXXX-XXXX` sur alphabet 29 caractères
  (`crypto.randomBytes`) ≈ 5×10¹¹ combinaisons → énumération réseau infaisable.
- **Anti-lockout admin** : impossible de se désactiver/rétrograder soi-même ;
  mot de passe staff ≥ 12 caractères ; rôles sur liste blanche.
- **Revocation des sessions admin** : `token_version` incrémenté à chaque
  changement sensible (rôle, statut, mdp, suppression) → toutes les sessions
  HMAC déjà émises meurent à la requête suivante (revalidation en base).
- **SQL** : 100 % paramétré (`$1…$n`) ; les 2 interpolations existantes sont
  des noms de colonnes codés en dur et un entier borné (1-36) — pas d'injection.
- **RBAC** : `requireAdmin` + contrôle `super_admin` sur les routes sensibles ;
  `password_hash` jamais renvoyé par les listings.
- **Inscription mobile** : la vraie porte d'entrée est le code agent ; aucune
  clé API n'est nécessaire (l'ancien JWT Supabase legacy a été **retiré du
  dépôt et du binaire** le 2026-09-26 — vérifié absent de `libapp.so`).

## IA (Cloudflare Worker)

- `POST /ai/ask` : clé anon `x-lynkstor-anon` (filtre le bruit, pas un
  attaquant déterminé — assumé), **rate-limit 60 req/min/IP**, corps ≤ 16 Ko,
  question ≤ 600 car., prompt système ≤ 4 000, garde anti-injection, réponse
  ≤ 420 tokens.
- Aucune donnée personnelle n'est envoyée : uniquement un **résumé numérique**
  construit localement ; le texte saisi par l'utilisateur dans l'assistant est
  la seule donnée libre.
- IA 100 % lecture seule : ne modifie jamais vente, stock ou dette.

## Build & supply chain

- APK **arm64-v8a uniquement**, sans assets modèle (0 GGUF), signé release
  (keystore `kumba_release.jks` + `key.properties` hors git ; échec de build
  garanti si keystore absent — pas de signature debug possible).
- Politique pre-commit : tout ce qui ressemble à un secret est soit ignoré
  (`.gitignore`), soit lu depuis l'environnement avec **fail-fast** ; audit
  systématique du staging (`git grep --cached`) avec motifs incluant le
  préfixe JWT générique `eyJ…`.

## Risques résiduels assumés (à connaître avant déploiement)

1. **Pas de rate-limit applicatif sur le gateway Neon** — compensé par les
   espaces de clés (codes ≈ 5×10¹¹, jetons 264 bits, mdp staff ≥ 12 car.) ;
   si la base clients grandit, ajouter un throttle par IP au gateway.
2. **Pas de certificate pinning** — fait confiance aux CA système ; acceptable
   pour ce modèle de menace (POS hors ligne), à réévaluer en cas d'APT ciblé.
3. **Pas de FLAG_SECURE** (captures d'écran récentes possibles) — choix
   délibéré : l'app doit pouvoir partager des tickets en image ; la base est
   chiffrée et l'écran se verrouille par PIN/biométrie.
4. **Clé anon IA embarquée** — rotation documentée (docs/LOCAL_AI.md) ; coût
   maximal d'un abus = quota gratuit Workers AI, aucune donnée exposée.
5. **Mot de passe admin du projet Supabase legacy** considéré compromis →
   ne plus réutiliser ce projet sans rotation complète (deploy/NEXT_STEPS.md).
