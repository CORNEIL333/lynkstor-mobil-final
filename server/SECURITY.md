# Sécurité serveur KUMBA / Lynkstor (v1.1)

## Authentification

| Surface | Protection |
|---------|------------|
| `/api/v1/admin/*` | `Authorization: Bearer <ADMIN_API_KEY>` |
| `/api/v1/sync/push` & `/pull` | `Bearer <SYNC_API_KEY>` ou `ADMIN_API_KEY` |
| `/api/v1/payments/webhook` | HMAC-SHA256 : header `X-Webhook-Signature: sha256=<hex>` |
| `/api/v1/auth/login` | Public — échange `ADMIN_USER`/`ADMIN_PASSWORD` → token |
| `/health`, fichiers statiques | Public |

## Configuration

```bash
cp .env.example .env
# Éditer les secrets, puis :
npm install
npm start
```

**Production obligatoire :** `NODE_ENV=production`, `ADMIN_API_KEY`, `ADMIN_PASSWORD`, `WEBHOOK_SECRET`.

## Signature webhook (exemple Node)

```js
const crypto = require('crypto');
const body = JSON.stringify(payload);
const sig = crypto.createHmac('sha256', process.env.WEBHOOK_SECRET).update(body).digest('hex');
// Header: X-Webhook-Signature: sha256=<sig>
```

## Sync mobile

- **Push** : `POST /api/v1/sync/push` avec corps JSON (`businessId`, `entityType`, `entityId`, `operation`, `payload`).
- **Idempotence** : `id` ou header `X-Idempotency-Key` ; doublons → `200` + `duplicate: true`.
- **Pull** : `GET /api/v1/sync/pull?businessId=...&since=ISO&limit=100`.
- Pas de fallback `biz-01` : `businessId` obligatoire.
- Erreur SQL → **500**, jamais un faux succès.

## Dashboard

Connexion via utilisateur/mot de passe ou collage de la clé API. Token stocké en `localStorage` uniquement.

## Déploiement

Voir `docs/DEPLOYMENT_GUIDE.md` (Node monolithe recommandé).  
Supabase « seul » n’est **pas** un chemin supporté aujourd’hui (`docs/SUPABASE_CLOUDFLARE_DEPLOYMENT.md`).

## À faire ensuite (hors scope v1.1)

- Rate limiting (login / webhook)
- JWT à expiration + rotation de clés
- HTTPS terminé (reverse proxy)
- Audit log des actions admin
- Ne pas versionner `*.db` ni `.env`
- Persistance Postgres (Supabase) branchée au Node
