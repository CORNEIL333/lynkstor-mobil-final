# Spécification — Avatar IA « Lynk » + module Assistant

Nom interne : **Lynk** (lien + Lynkstor). Personnage unique, pas un robot, pas Duo copié : **boule océan expressive** avec un accent ciel et une tache corail (joue / reflet).

---

## 1. Direction artistique

- Forme : sphère molle, légèrement écrasée (squash 4 %), ratio ~1:1.
- Corps : dégradé océan `#0E5A8C` → ciel `#4BA3E3`.
- Yeux : deux ovales crème, pupilles océan profond. Un œil un peu plus grand = personnalité.
- Accent : petite virgule corail `#E07A5F` (joue droite) — reconnaissable à 32 px.
- Bouche : trait crème, 3 états (neutre, sourire, « o » surprise).
- **Pas d’emoji Unicode.** Dessin vectoriel Flutter (`CustomPainter` / `CustomPaint`) pour 60 fps, 0 asset lourd au départ.
- Lottie : optionnel plus tard si un motion designer livre des `.json`. L’API du widget reste la même (`LynkAvatar(state:, size:)`).

### Tailles

| Contexte | Taille |
|----------|--------|
| Chip / onglet nav | 36–40 px |
| Header chat / dashboard | 64–80 px |
| Accueil module IA / onboarding | 140–180 px |
| Célébration overlay | 96 px |

Personnalisation (réglages) : prénom affiché à côté (« Lynk » par défaut), **couleur d’accent** (corail, ciel, océan) — pas un second personnage.

---

## 2. Bibliothèque d’états

| État | Motion | Durée | Quand |
|------|--------|-------|--------|
| `idle` | Respiration scale 1.00↔1.04, clignement 3–6 s | Loop 2.4 s | Repos |
| `thinking` | Yeux qui glissent, halo IA pulse | Loop 800 ms | Génération |
| `listening` | Ondes autour, bouche « o » | Sync micro | STT |
| `replying` | Léger rebond, sourire | 400 ms | Fin de stream |
| `alert` | Inclinaison 8°, accent corail plus saturé | 350 ms | Anomalie métier |
| `sorry` | Yeux baissés, pas de rouge agressif | 400 ms | Erreur / vide |
| `celebrate` | Saut 12 px + 6 étincelles ciel | 600 ms | Objectif / sync OK |
| `offline` | Désaturé 40 %, idle ralenti | Loop | Pas de modèle / hors ligne |

Reduce motion / mode perf : image clé de l’état, **aucun loop**. L’info reste (badge texte).

---

## 3. Technique recommandée

1. **V1 (cette refonte)** : `LynkAvatar` en `StatefulWidget` + `AnimationController` + `CustomPainter`. Un fichier, pas de Lottie, cache GPU via `RepaintBoundary`.
2. **V2** : remplacer le painter par `Lottie.asset` si les JSON arrivent, derrière la même API.
3. Interdit : GIF, emoji, `AiOrb` actuel (blob de points) — on le retire des surfaces utilisateur, on peut le garder en fallback debug.

Fichier cible : `lib/design_system/motion/lynk_avatar.dart`.

---

## 4. Module IA — écrans

### 4.1 Plein écran `/ai` (Google AI Studio, identité Lynkstor)

```
[ avatar 72 + « Lynk » + historique ]
[ conversation ]
    user → bulle droite, fond océan, texte crème
    lynk → gauche, avatar 32, fond crème, bordure 1.5 px dégradé IA
    données → mini-card (KPI / sparkline) sous le texte, badge « Généré par IA »
[ chips de relance ]
[ input pill : micro | champ | send→loader ]
```

- Streaming : mots par groupes (pas caractère par caractère) via le stream llama déjà en place.
- Curseur pulse océan en fin de token.
- Actions contextuelles sous la réponse : `Créer une vente`, `Ouvrir le stock`, `Encaisser [client]` — **jamais exécutées sans tap**.
- Suggestions vides, selon rôle :
  - seller : « Résume mes ventes du jour », « Qui doit de l’argent ? »
  - stockManager : « Quels articles sont sous seuil ? »
  - accountant : « Dépenses vs encaissements aujourd’hui »
- Historique : drawer gauche, conversations persistées en Drift (nouvelle table `ai_threads` / `ai_messages`). V1 peut rester session-only si on livre l’UI d’abord, persistence au module 5b.
- Ouverture : shared-element depuis l’onglet / chip (avatar scale 40→72, fond dégradé IA fade 420 ms).

### 4.2 Bottom sheet rapide

- 55–70 % de hauteur, grab handle, swipe down.
- Même fil de conversation (provider partagé `aiChatControllerProvider`).
- Bouton « Plein écran » en header.
- Pop : scale 0.96→1 + fade, 280 ms, overshoot 1.02.

### 4.3 Bulles contextuelles métier

- Ancrées à une ligne (stock bas, dette élevée).
- Avatar 32 + une phrase + 1 CTA.
- Max 1 bulle visible, dismiss 8 s ou tap.
- Jamais sur la grille caisse pendant un scan.

### 4.4 Contrat de confiance

Toute sortie modèle :
- Badge `Généré par IA`
- Bordure dégradé IA
- Séparation **fait local** (chiffres Drift) vs **suggestion** (texte)
- Le prompt système actuel reste : lecture seule, pas d’invention de chiffres.

---

## 5. Backend IA déjà en place

- `LocalAiModelService` : download + load GGUF.
- `BusinessAiContextBuilder` : ventes / stock / dettes du jour injectés dans le prompt.
- `AiAssistantScreen` : chat + download UI.

On **réutilise** ce pipeline. On remplace uniquement la couche visuelle et on extrait le state dans un controller Riverpod pour sheet + plein écran + recherche.

Voix : `speech_to_text` à ajouter au module 5 si le plugin Android est acceptable ; sinon micro en V1 = placeholder visuel + toast « saisie vocale à brancher ».

---

## 6. Intégration hors module

| Surface | Lynk |
|---------|------|
| Dashboard | 64 px + phrase du jour |
| Empty / error | `sorry` |
| Objectif ventes atteint | `celebrate` 1.2 s |
| Pull-to-refresh | `thinking` puis `idle` |
| Paramètres | Choix accent + nom |
