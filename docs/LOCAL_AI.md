# Assistant IA hybride « Lynk »

## Architecture (depuis septembre 2026)

L'ancien design (GGUF Qwen embarqué + llama.cpp sur l'appareil) a été
**retiré** : le modèle embarqué était détruit par la requantification
(couches 6-23 élaguées → réponses incohérentes) et coûtait 196 Mo dans
l'APK. Lynk fonctionne désormais en **deux cerveaux** :

1. **Cerveau local déterministe** (toujours disponible, hors ligne)
   - `LynkGroundedAnswers.tryAnswer()` répond instantanément et
     **exactement**, sans réseau, à ~20 familles de questions métier
     (moteur d'intents élargi, septembre 2026) :
     - ventes / chiffre d'affaires, bénéfice, encaissé, avec fenêtres
       **aujourd'hui / hier / 7 jours / ce mois** ;
     - tendance et comparaison entre fenêtres (« hier vs d'habitude ») ;
     - dépenses **et par catégorie** (Loyer, Transport…) ;
     - dettes globales, **et par client nommé** (« Paul vous doit… »,
       avec rang parmi les débiteurs) ;
     - stock, ruptures, seuils, **fiche produit nommée**
       (« il reste du ciment ? » → quantité, unité, prix, alerte) ;
     - top-3 meilleures ventes, **invendus de 30 jours** ;
     - panier moyen, retours/avoirs, acomptes partiels ;
     - comptes du catalogue (produits / clients / endettés) ;
     - petit talk (bonjour, merci, « qui es-tu / que sais-tu faire »).
   - Comprehension renforcée : normalisation des accents et de la
     ponctuation, mots-entiers regex vs sous-chaînes, garde anti-
     collision (« recharger » ≠ « charge », « meilleures ventes » ≠
     ventes…), questions de conseil (« comment améliorer… ») et de
     causalité (« pourquoi… ») **volontairement déléguées au cloud**.
   - Les chiffres viennent de la base SQLite locale chiffrée ; aucune
     donnée ne quitte l'appareil pour ces réponses. Hors connexion,
     une question hors périmètre reçoit un message honnête au lieu
     d'un chiffre inventé (`hasTrendData=false` → windowing désactivé).
2. **Cerveau cloud** (questions libres, conseils)
   - `LynkBrainService` (`lib/features/ai_assistant/data/`) appelle
     `POST /ai/ask` sur le Worker Cloudflare
     (`deploy/cloudflare/worker.mjs`, même déploiement que le tableau
     de bord admin).
   - Modèle : `@cf/meta/llama-3.2-3b-instruct` (repli automatique
     1B puis 8B selon la disponibilité Workers AI).
   - Contexte envoyé : question + résumé d'affaires **numérique**
     (prompt système construit par `BusinessAiContextBuilder`) +
     6 derniers tours de conversation. Aucun nom de client, aucune
     donnée personnelle.
   - Garde-fous serveur : clé d'accès anon (`x-lynkstor-anon`),
     60 requêtes/min/IP, corps ≤ 16 Ko, question ≤ 600 caractères,
     prompt système ≤ 4 000, garde anti-injection dans le système
     prompt, réponse ≤ 420 tokens.

## Honnêteté de source

Chaque bulle de réponse porte un badge :
`Calcul local · hors ligne` (vert) ou `Llama 3.2-3B · cloud · en ligne`
(violet). Hors connexion, les questions libres reçoivent un message
honnête qui renvoie vers les suggestions locales — jamais de réponse
inventée.

## Clé d'accès et rotation

- La clé anon vit dans `AppConfig.aiAccessAnonKey` et les `vars` de
  `deploy/cloudflare/wrangler.jsonc` (`AI_ACCESS_KEY`).
- Ce n'est pas un secret fort (embarquée dans l'app) : elle filtre le
  bruit, pas un attaquant déterminé. Pour la tourner : modifier les
  deux fichiers puis `npx wrangler deploy` depuis `deploy/cloudflare/`
  + rebuild de l'app.
- Coût : ~7 % du quota gratuit Workers AI par question ; le trafic
  attendu d'un trial reste dans le gratuit.

## Sécrétariat / brouillons fournisseur

`draftSupplierMessage()` utilise le cerveau cloud ; en cas
d'indisponibilité il renvoie le brouillon local de l'utilisateur
(jamais bloquant).

## Build

- Plus aucun asset modèle : `android/app/src/main/assets/models/` a
  disparu, le plugin `llama_flutter_android` et le canal MethodChannel
  `local_ai` aussi.
- L'APK est construit **arm64 uniquement**
  (`flutter build apk --release --target-platform android-arm64`) :
  les appareils ciblés sont 64 bits ; ~60 Mo de .so morts supprimés.

## Limites

- Questions libres = réseau requis (repli local honnête sinon).
- Le modèle cloud ne voit que le résumé numérique : répond moins bien
  sur des détails hors résumé (demander une précision aide).
- Lecture seule de bout en bout : l'IA ne modifie jamais vente, stock
  ou dette. Vérifier toute recommandation importante.
