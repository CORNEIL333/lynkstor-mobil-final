# Déploiement Cloudflare Worker — Admin Lynkstor

Le contenu de ce dossier est généré par le script :

```bash
# depuis la racine du repo
node deploy/cloudflare/prepare.mjs
```

Le Worker cible est `sweet-bush-a7e8` et sert directement les fichiers de
`deploy/cloudflare/dist/` grâce à `wrangler.jsonc`.

Validation sans publication :

```bash
npx wrangler deploy --config deploy/cloudflare/wrangler.jsonc --dry-run
```

Publication :

```bash
npx wrangler login
npx wrangler deploy --config deploy/cloudflare/wrangler.jsonc
```

Si le callback OAuth local échoue, créer un jeton avec le modèle
`Edit Cloudflare Workers`, limité au compte cible, puis ajouter ces valeurs à
`deploy/secrets.local.env` (fichier exclu du dépôt) :

```dotenv
CLOUDFLARE_ACCOUNT_ID=...
CLOUDFLARE_API_TOKEN=...
```

Dans PowerShell, charger les deux variables uniquement pour le processus de
déploiement avant d'exécuter Wrangler.

URL de production :

`https://sweet-bush-a7e8.wosee-connect.workers.dev/`

Sonde IA publique (sans coût) : `.../ai/health`
