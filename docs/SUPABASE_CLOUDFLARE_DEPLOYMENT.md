# Déploiement Supabase + Cloudflare Pages — Lynkstor

Architecture cible **supportée** :

```
[ App mobile ]  --Bearer SYNC/ADMIN-->  Supabase Edge Function lynkstor-api
                                              |
                                              v
                                        Postgres (RLS fermé)
                                              ^
[ Admin Cloudflare Pages ] --Bearer ADMIN-->  même Edge Function
```

---

## Prérequis

- Compte [Supabase](https://supabase.com)
- Compte [Cloudflare](https://cloudflare.com)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (recommandé)
- Node.js 18+ (pour le script de bundle Cloudflare)

---

## ÉTAPE 1 — Projet Supabase

1. Créer un projet : **lynkstor-backend**
2. Noter :
   - **Project URL** : `https://<PROJECT_REF>.supabase.co`
   - **Project ref** (Settings → General)
   - **service_role key** (ne jamais la mettre dans le front)

### Option A — SQL Editor (sans CLI)

1. Ouvrir **SQL Editor**
2. Coller le contenu de `supabase/migrations/20260727000000_init.sql`
3. **Run**

### Option B — CLI

```bash
# À la racine du repo
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
npx supabase db push
```

---

## ÉTAPE 2 — Secrets Edge Functions

Créer un fichier local (ne pas committer) :

```bash
cp supabase/secrets.example.env supabase/.secrets.env
# Éditer ADMIN_API_KEY, ADMIN_PASSWORD, WEBHOOK_SECRET
```

Puis :

```bash
npx supabase secrets set --env-file supabase/.secrets.env
```

Ou Dashboard → **Edge Functions → Secrets** :

| Secret | Description |
|--------|-------------|
| `ADMIN_API_KEY` | Token Bearer admin + login |
| `ADMIN_USER` | Login dashboard (défaut `admin`) |
| `ADMIN_PASSWORD` | Mot de passe dashboard |
| `WEBHOOK_SECRET` | HMAC webhooks paiement |
| `SYNC_API_KEY` | (optionnel) clé mobile |

`SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont injectés automatiquement.

---

## ÉTAPE 3 — Déployer l’Edge Function

```bash
npx supabase functions deploy lynkstor-api --no-verify-jwt
```

Vérifier :

```bash
curl https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api/health
```

Réponse attendue : `{ "status": "ok", ... }`

Tester le login :

```bash
curl -X POST https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"VOTRE_MOT_DE_PASSE\"}"
```

---

## ÉTAPE 4 — Bundle admin Cloudflare

```bash
# Windows PowerShell
$env:SUPABASE_PROJECT_REF="votre_project_ref"
node deploy/cloudflare/prepare.mjs

# ou
$env:SUPABASE_URL="https://votre_project_ref.supabase.co"
node deploy/cloudflare/prepare.mjs
```

Cela crée `deploy/cloudflare/dist/` avec :

- `index.html`, `admin.js`, `styles.css`, logos
- `config.js` (apiBase déjà renseigné)
- `_headers`

### Cloudflare Pages

1. Workers & Pages → **Create** → **Pages** → **Upload assets**
2. Nom : `lynkstor-admin`
3. Glisser-déposer **tout le contenu** de `deploy/cloudflare/dist/`
4. Deploy

URL type : `https://lynkstor-admin.pages.dev`

### Connexion admin

1. Ouvrir le site
2. Utilisateur / mot de passe définis dans les secrets  
   **ou** coller `ADMIN_API_KEY`
3. Si besoin : champ **URL API backend** =  
   `https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api`

---

## ÉTAPE 5 — Application mobile

Paramètres → Serveur de synchronisation HTTP :

```
https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api/api/v1/sync/push
```

Header (si l’app envoie un token) :

```
Authorization: Bearer <SYNC_API_KEY ou ADMIN_API_KEY>
```

Pull (si utilisé) :

```
https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api/api/v1/sync/pull?businessId=...
```

---

## ÉTAPE 6 — Webhooks paiement (CinetPay / Wave / …)

- **IPN / Webhook URL** :  
  `https://<PROJECT_REF>.supabase.co/functions/v1/lynkstor-api/api/v1/payments/webhook`
- Header : `X-Webhook-Signature: sha256=<hmac-sha256-hex du body>`
- Secret = `WEBHOOK_SECRET`

---

## Routes exposées (gateway)

| Méthode | Chemin (après `/functions/v1/lynkstor-api`) |
|---------|-----------------------------------------------|
| GET | `/health` |
| POST | `/api/v1/auth/login` |
| * | `/api/v1/admin/*` (Bearer admin) |
| POST | `/api/v1/sync/push` (Bearer sync) |
| GET | `/api/v1/sync/pull` (Bearer sync) |
| POST | `/api/v1/payments/webhook` (HMAC) |

Même contrat que le serveur Node Express.

---

## Checklist GO

- [ ] Migration SQL exécutée
- [ ] Secrets Edge Functions définis
- [ ] `lynkstor-api` déployée (`--no-verify-jwt`)
- [ ] `GET .../health` OK
- [ ] Login admin renvoie un `token`
- [ ] Cloudflare dist généré avec `apiBase` correct
- [ ] Dashboard charge les KPI après login
- [ ] Sync push testée avec Bearer

---

## Sécurité

- RLS Postgres : **aucun accès anon** direct aux tables
- Seule l’Edge Function (service_role) lit/écrit la base
- Ne jamais mettre `service_role` dans `config.js` ou Cloudflare
- Changer tous les secrets avant production réelle

---

## Dépannage

| Problème | Cause probable |
|----------|----------------|
| Login « Impossible de joindre l’API » | `config.js` apiBase vide / CORS / function non déployée |
| 401 permanent | Mauvais `ADMIN_API_KEY` ou secrets non pushés |
| Stats vides | Seed SQL non exécuté |
| Sync 500 FK | `business_id` inconnu — la function crée un commerce minimal si absent |
| JWT error Supabase | Redéployer avec `--no-verify-jwt` |

---

## Fichiers du repo

```
supabase/
  config.toml
  migrations/20260727000000_init.sql
  functions/lynkstor-api/index.ts
  functions/_shared/*
  secrets.example.env
deploy/cloudflare/
  prepare.mjs
  _headers
  dist/          # généré, non versionné idéalement
server/public/
  config.js      # runtime admin
  config.example.js
```
