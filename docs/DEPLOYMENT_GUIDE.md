# Guide de déploiement — API + Admin Lynkstor

## Verdict déploiement (état actuel)

| Cible | Statut | Commentaire |
|-------|--------|-------------|
| **Supabase + Cloudflare Pages** | **GO** | Chemin cloud recommandé — voir `SUPABASE_CLOUDFLARE_DEPLOYMENT.md` |
| **Serveur Node monolithe** (API + site admin) | **GO** | Alternative Docker / Render |
| **Admin Cloudflare + API Node séparée** | **GO avec config** | `CORS_ORIGIN` + URL API |

---

## 1. Chemin recommandé : Node monolithe (Render / Railway / Docker)

Le serveur Express sert **à la fois** :

- l’API (`/api/v1/...`, `/health`)
- le dashboard admin (`server/public/`)

### Variables d’environnement obligatoires (production)

```env
NODE_ENV=production
PORT=8080
ADMIN_API_KEY=<long-random-string>
ADMIN_USER=admin
ADMIN_PASSWORD=<strong-password>
WEBHOOK_SECRET=<hmac-secret>
# Optionnel
SYNC_API_KEY=<clé-mobile-dédiée>
CORS_ORIGIN=          # laisser vide en monolithe
DATA_DIR=/app/data    # Docker
```

Sans `ADMIN_API_KEY`, `ADMIN_PASSWORD` et `WEBHOOK_SECRET`, le process **refuse de démarrer** en production.

### Local

```bash
cd server
cp .env.example .env
# Éditer les secrets
npm install
npm start
# → http://localhost:3001  (ou PORT défini)
```

Login admin : utilisateur / mot de passe du `.env`, ou coller `ADMIN_API_KEY`.

### Docker Compose

```bash
cd server
export ADMIN_API_KEY=...
export ADMIN_PASSWORD=...
export WEBHOOK_SECRET=...
docker compose up -d --build
# → http://localhost:8080
```

### Render.com

1. New **Web Service** → dossier `server/` (ou repo avec root `server`).
2. Runtime : **Docker** (recommandé) ou Node.
3. Si Node nu :
   - Build : `npm install`
   - Start : `npm start`
4. Variables d’env : celles listées ci-dessus (`PORT` fourni par Render).
5. Health check : `GET /health`
6. Disque persistant (optionnel) : monter `DATA_DIR` pour ne pas perdre la SQLite au redémarrage.

### App mobile

Paramètres → Serveur de synchronisation HTTP :

```
https://VOTRE-SERVICE.onrender.com/api/v1/sync/push
```

Header requis (côté client déjà supporté si token configuré) :

```
Authorization: Bearer <SYNC_API_KEY ou ADMIN_API_KEY>
```

Aujourd’hui l’app envoie `Authorization` si un token est fourni au `SyncEngine` ; configurez l’endpoint dans les paramètres.

---

## 2. Admin sur Cloudflare Pages + API ailleurs

1. Déployer le **Node API** (Render) comme ci-dessus.
2. Upload `server/public/` sur Cloudflare Pages.
3. Sur le login admin : renseigner **URL API backend** = `https://votre-api.onrender.com`
4. Sur le serveur Node :  
   `CORS_ORIGIN=https://lynkstor-admin.pages.dev`

Sans ces deux réglages, le site Cloudflare affiche le login mais **ne peut pas appeler l’API**.

---

## 3. Checklist pré-prod

- [ ] Secrets forts (pas les valeurs `dev-*`)
- [ ] `NODE_ENV=production`
- [ ] `GET /health` → `{ "status": "ok" }`
- [ ] Login admin OK
- [ ] `POST /api/v1/sync/push` sans Bearer → **401**
- [ ] Webhook sans signature → **401**
- [ ] Volume / backup de `kumba_central.db` (ou `DATA_DIR`)
- [ ] HTTPS (fourni par Render / reverse proxy)
- [ ] Mobile : URL sync + clé Bearer testées

---

## 4. Ce que le serveur admin **n’est pas**

- Pas un miroir ERP complet (ventes détail, stock, dettes) — journal sync + abonnements + terrain
- Pas multi-instance SQLite partagée (un seul process / un volume)
- Pas un remplacement de Supabase Auth (auth = clés API statiques)

Pour une montée en charge multi-tenant, planifier Postgres + auth JWT (évolution future).
