# Design system v2 - Lynkstor

**Source de verite unique** : `docs/reference/template.jpeg`  
**Statut** : livrable a valider. **Aucun ecran n'est recode tant que ce document n'est pas approuve.**

Lecture : refonte *overhaul*. La palette ocean/sky/cream en aplats plats est **retiree** des surfaces principales. Elle ne survit que comme sous-tons dans le bleu vif du header / Vendre.

---

## 0. Lecture design

Application POS/ERP mobile pour commercants africains, usage quotidien caisse + IA Lynk. Langage : consumer-app 2026, cards 3D clay, palette multi-teintes vive, dock marine. Pas un dashboard B2B gris.

Dials (apres la capture, pas le baseline taste-skill) :

- `DESIGN_VARIANCE: 6` - grille 2 colonnes reguliere, hero asymetrique (texte gauche / photo droite)
- `MOTION_INTENSITY: 6` - springs a l'entree, idle Lynk, pas de scroll-hijack
- `VISUAL_DENSITY: 5` - dashboard dense mais cards respirent

---

## 1. Audit couche par couche de la reference

Image analysee : 420 x 935. Couleurs = mediane de zone + pixels satures (clusters), pas une estimation a l'oeil.

### 1.1 Status bar (systeme)

- Fond : le degrade header, bleu `#1162F0` / `#003FE9`
- Heure blanche, pictos reseau blancs
- Island / pill sombre "Caisse 1" au centre (hors scope app, chrome telephone)

### 1.2 Header / hero

| Couche | Description | Hex extraits |
|---|---|---|
| Fond gauche | Degrade bleu vif, haut plus profond, bas plus ciel | Haut `#1162F0` / `#0A5CF6` → milieu `#1F78EF` → bas `#2A8BEA` |
| Fond droite | Photo boutique (etageres, tissus roses/beiges), **nette a droite**, fondue dans le bleu a gauche | Chauds `#E2C4C6`, `#EDBB9A`, `#D7A99E` |
| Scrim | Pas un voile blanc opaque. Le bleu **teinte** la photo a gauche, la photo reste lisible a droite | Melange `#99A8DF`, `#6495E4` |
| Plante | Feuillage flou vert, bas-gauche, sort du cadre | accent vegetal, pas un token UI |

**Ce n'est pas un aplat.** C'est photo + degrade diagonal bleu, coins bas arrondis ~32-36 qui versent dans le creme.

### 1.3 Typo header

| Element | Poids / taille percus | Couleur |
|---|---|---|
| "Bonjour," | 16-17, regular/medium | Blanc `#FFFFFF` ~85 % |
| "Oscar" | 28-32, extra-bold, tracking serre | Blanc `#FFFFFF` 100 % |
| Emoji main | inline apres le prenom | - |
| "Que vendez-vous aujourd'hui ?" | 15-17, medium, 2 lignes, **menthe** | `#5CDFFF` / `#7AEFFF` (cyan clair, pas du blanc) |
| Chip "CHEZ OSCAR" | 11-12 caps, pin a gauche, pill translucide | Texte blanc 80 %, fond blanc 18 % |

### 1.4 Avatar Lynk (header)

- Sphere 3D bleu clay `#1A6FE8` → `#0B4CC8`, specular blanc
- Yeux blancs, pupilles noires, sourire
- Pastille online **verte** `#22C55E` bas-droite, ring blanc 2 px
- Taille ~48-52

### 1.5 Actions header droite

| Element | Forme | Couleurs |
|---|---|---|
| Cloche | Cercle blanc 44, icone bleue, badge rouge 8-10 | Fond `#FFFFFF`, icone `#157EF5`, badge `#FF3B5C` |
| Compteur | Cercle bleu vif 44, chiffre blanc "0" | Fond `#0A5CF6` / `#157EF5` |

### 1.6 Search

- Pill blanc plein, hauteur ~48, radius 999
- Loupe gauche gris-bleu `#8AA0C0`
- Placeholder "Rechercher un produit..." `#9AABC4`
- QR droite, meme gris-bleu
- Ombre douce bleutee, pas noire
- Chevauche le bas du hero (moitie sur le bleu, moitie sur le creme)

### 1.7 Card Vendre

- Ratio ~1:1.15, radius 28
- Degrade **cyan → cobalt**, haut-gauche clair, bas-droit plus profond
  - Depart `#00C9FF` / `#04B2FC`
  - Arrivee `#4D7FF1` / `#1A6BFF`
- Titre blanc bold "Vendre", caption blanc 80 % "Ouvrir la caisse"
- Pictos : caisse dans pastille translucide haut-droite
- Illustration 3D : **3 sacs** (jaune, rose, bleu) qui debordent du bas
- CTA : cercle blanc 36, fleche bleue, bas-droite
- Ombre portee **teintee cyan** `#00A7FF` 35 %, blur 24, y=12

### 1.8 Card Encaisser

- Meme geometrie
- Degrade **violet** haut `#8349F5` → bas `#6430DF` / `#5B25F7`
- Highlights magenta `#EF15F2` sur les pieces
- Titre blanc "Encaisser", caption "Dettes et acomptes"
- Fleche dans cercle blanc 25 % haut-droite
- Illustration : portefeuille violet + pieces or qui **sortent** de la card
- Ombre teintee violet `#6E2DFF` 40 %

### 1.9 Card Lynk · priorite du jour

- Fond blanc `#FBFBFC`, radius 24, ombre gris-bleu `#C5CDE0` 18 %
- Etoile or `#FAAD13` + "Lynk · priorite du jour" (Lynk gris, priorite **violet** `#5B16ED`)
- Mascotte grande ~72, pose "coucou" (bras leve)
- Corps du message `#2B3345` regular
- CTA "Demander a Lynk →" violet `#5B16ED` / `#6921FF`, w700
- Illustration droite : clipboard 3D pastel + checks

### 1.10 Grille KPI 2x2

Chaque card : radius 22, padding 14, illustration bas-droite, **identite unique**.

| KPI | Fond pastel | Icone / montant | Illustration |
|---|---|---|---|
| Ventes | `#F2FDF7` | `#30D368` / `#3AE77E` | courbe montante verte |
| Encaisse | `#F3F6FF` | `#1A7CFF` / `#3284FF` | pile de pieces bleues |
| Dettes | `#FEF8F5` | `#F55207` / `#F86923` | silhouettes peche |
| Acomptes | `#FFF4FA` | `#F1186F` / `#EC1C74` | calendrier + coche |

Label colore en haut (icone + mot). Montant extra-bold ~20. Caption gris `#8B95A7` ("0 vente").

### 1.11 Chevron flottant

Cercle ~44, bleu `#157EF5`, double chevron blanc, pose sur le bord droit entre Lynk et KPI. Lecture : collapse / scroll. **A valider** : on le garde comme "replier le brief Lynk" ou on le drop (risque de confusion avec le dock).

### 1.12 Dock

- Capsule marine **opaque** `#072048` (cluster `#08214A`)
- Marge ~14 laterale, ~10 + safe-area bas
- Hauteur ~64, radius 32
- 5 slots : Accueil, Ventes, FAB caisse, Assistant (mini Lynk), Plus
- **Actif Accueil** : disque bleu vif `#157EF5` / `#1B7CFF` derriere l'icone blanche, label blanc
- Inactifs : icone `#8FA3C4`, label `#8FA3C4`
- FAB central : cercle ~56, meme bleu vif, **surélevé** de 8-10 px au-dessus du dock, icone caisse blanche, ring optionnel blanc 2 px
- Ce n'est **pas** du glass. Pas de blur.

### 1.13 Page / contenu

Fond hors header : `#F7F8FC` / `#F4F3F9` (blanc-mauve tres leger, pas creme chaud `#FBF7F2`).

### 1.14 Ce que la version actuelle rate vs cette capture

| Actuel | Reference |
|---|---|
| Header voile blanc sur photo boutique | Photo nette a droite, bleu sature a gauche, texte blanc + menthe |
| Vendre / Encaisser ice + ocean plats | Cyan 3D + violet 3D + illustrations debordantes |
| KPI tous en variations de bleu | Vert / lavande / peche / rose |
| Dock blanc glass puis marine plat | Marine opaque + disque actif + FAB surélevé |
| Lynk CustomPainter 2D petit | Mascotte 3D clay, pose, checklist |
| Rapports : aplats sombres (darkCard / navy) | Interdit. Aucun pavé noir hors dock |

---

## 2. Recherche standards 2026 - impact sur les choix

Sources : Material 3 Expressive (May 2025, rollout Android 16 / 2025-2026), motion physics M3, WCAG 2.2, Flutter Impeller 3.41, patterns chat IA 2026.

### 2.1 Material 3 Expressive

- Motion **physics / springs** remplace easing+duree. Schema **Expressive** (overshoot) pour moments heros, **Standard** (peu de bounce) pour l'utilitaire. Spatial springs (position/taille) peuvent overshooter. Effect springs (couleur/opacite) **jamais** de bounce. [web:0][web:2]
- Shapes : Extra large 32, Extra extra large 48, pills `full`. Shape morph pour etats, pas pour les tap targets. [web:1]
- Couleur plus chroma, hierarchie plus lisible. [web:32]
- **Flutter** : motion physics M3 **pas encore natif** dans le SDK. On l'emule avec `SpringSimulation` / `flutter_animate` (stiffness/damping), pas avec `Curves.easeIn`.

Impact : cards d'action et KPI = schema Expressive a l'entree (scale 0.94→1, overshoot leger). Navigation onglets et saisie = schema Standard (rapide, pas de bounce). Predictive Back Android **conserve** (`PredictiveBackPageTransitionsBuilder`). Pas de Cupertino.

### 2.2 Motion mobile 2026

- Shared element : Android Predictive Back spec scale min 0.90. Flutter `Hero` pour Lynk header → ecran IA. [web:15]
- Springs interruptibles pour press (`scale 0.97`, 100-160 ms).
- Haptics : selection sur tab, medium sur Vendre / Encaisser, light sur chips.

Impact : `Hero(tag: 'lynk')` du dashboard vers `/ai`. Pas d'animation sur actions clavier (N/A mobile). Reduced motion = crossfade 180 ms.

### 2.3 Accessibilite 2026

- WCAG 2.2 AA : contrast 4.5:1 body, 3:1 large text, tap **24 CSS px floor**. Android Material = **48 dp** (on reste a 48, jamais 24). [web:16][web:23]
- TalkBack : labels FR/EN, roles button, compteur cloche annonce.
- Texte blanc sur header bleu `#1162F0` : OK large. Menthe `#5CDFFF` sur bleu : a verifier (large text 3:1). Si fail → `#B8F4FF`.
- Vert KPI `#30D368` sur `#F2FDF7` : montant large OK, caption gris doit rester `#5A6578` pas `#B0B8C4`.
- Violet CTA `#5B16ED` sur blanc : 4.5:1 OK.

### 2.4 Patterns assistant IA 2026

- Streaming token + caret (barre 2 px / dot pulse). Stop visible. [web:28][web:29]
- Apps "outil" (Claude, ChatGPT) : messages full-width, pas SMS. **Mais** Lynk est un compagnon POS : on garde **bulles**, coins 20, avatar a gauche, utilisateur a droite. Cadre "copain de caisse", pas IDE.
- Avatar anime = etat (idle / thinking / talking), pas deco infinie.
- Skeleton + "Lynk reflechit…" plutot que spinner.

Impact : ecran IA = bulles, streaming, Lynk Rive. Sheet dashboard = chips + handoff, pas un 2e moteur de chat.

### 2.5 Perf Flutter (bas/moyen de gamme)

- `BackdropFilter` : 6-9 ms raster mid-tier. 3 filtres = plus de 60 Hz. [web:12]
- `Opacity` / `ShaderMask` = saveLayer. Preferer couleur de fond opaque.
- Impeller 3.41 : bounded blur moins de color bleeding, **ca n'efface pas le cout**. [web:9]
- Reponse 2026 : prerender le blur, ou **ne pas en mettre**.

Impact : dock **opaque**. Gradients 2 stops max. Mode perf existant desactive Rive idle + stagger. Pas de glass.

---

## 3. Tokens (extraits reels, pas indicatifs)

### 3.1 Couleur

```
// Header
headerStart        #0A5CF6
headerMid          #1F78EF
headerEnd          #4AA3F5
headerOn           #FFFFFF
headerOnMuted      #FFFFFF D9
headerMint         #5CDFFF   // sous-titre

// Actions
sellStart          #00C4FF
sellEnd            #2F6BFF
sellShadow         #00A7FF 59
collectStart       #8B4AFF
collectEnd         #5A22E0
collectShadow      #6E2DFF 66

// Lynk / IA
lynkViolet         #5B16ED
lynkVioletSoft     #EFE8FF
lynkStar           #FAAD13
lynkBody           #1A6FE8
lynkOnline         #22C55E

// KPI
kpiSalesBg         #F2FDF7
kpiSales           #1DBF6A
kpiCollectBg       #F3F6FF
kpiCollect         #1A7CFF
kpiDebtBg          #FEF8F5
kpiDebt            #F55207
kpiDepositBg       #FFF4FA
kpiDeposit         #EC1C74

// Chrome
pageBg             #F5F6FB
cardBg             #FFFFFF
searchBg           #FFFFFF
ink                #1C2433
inkMuted           #5A6578
inkFaint           #8B95A7
dock               #072048
dockInactive       #8FA3C4
dockActive         #157EF5
fab                #157EF5
danger             #FF3B5C
```

Regle : **une famille = une teinte**. Ventes ne sera jamais bleue. Lynk / Assistant / liens IA = toujours `lynkViolet`. Dock et FAB = `dock` / `fab`, jamais creme.

### 3.2 Typographie

Famille : **Plus Jakarta Sans** (google_fonts, puis TTF embarques).

| Role | Size | Weight | Tracking | Usage |
|---|---|---|---|---|
| display | 30 | 800 | -1.0 | prenom hero |
| title | 17 | 700 | -0.3 | titres cards action |
| kpi | 20 | 800 | -0.4 | montants |
| body | 15 | 500 | 0 | messages Lynk |
| caption | 12 | 500 | 0 | "0 vente" |
| mint | 16 | 600 | -0.2 | sous-titre hero |
| label | 11 | 700 | 0.2 | chip CHEZ … |

### 3.3 Forme

| Token | dp | Usage |
|---|---|---|
| radius.card | 28 | Vendre / Encaisser |
| radius.kpi | 22 | grille 2x2 |
| radius.sheet | 28 | haut des sheets |
| radius.pill | 999 | search, dock, chips |
| radius.fab | 999 | caisse centrale |
| dock.height | 64 | |
| fab.size | 56 | |
| tap | 48 | **partout** |

### 3.4 Ombres (toujours teintees)

```
shadow.sell     0 12 24 -4  sellShadow
shadow.collect  0 12 24 -4  collectShadow
shadow.card     0 10 20 -6  #072048 12%
shadow.dock     0 14 28 -8  #072048 40%
```

Interdit : `Colors.black26` sur fond clair.

### 3.5 Motion

| Token | Spec | Usage |
|---|---|---|
| spatial.expressive | spring stiffness 380, damping 22, mass 1 | entree cards |
| spatial.standard | spring 500 / 28 | tabs, search |
| effect | 180 ms ease-out, **zero bounce** | couleur, fade |
| stagger | 45 ms | KPI 1→4 |
| press | scale 0.97, 120 ms | toutes cards tappable |
| lynk.idle | Rive loop, pause si reduced motion | |

---

## 4. Composants a reconstruire (spec, pas de code)

1. **LynkAvatarRive** - 3 tailles (32 dock, 48 header, 72 card), mood idle/wave/talk, pastille online
2. **HeroWelcome** - photo droite + degrade gauche, typo 3 niveaux, chip lieu, cloche, badge
3. **SearchPill** - blanc, 48, loupe + QR
4. **ActionSceneCard** - degrade 2 stops, illustration overflow, CTA cercle
5. **LynkBriefCard** - blanc, mascotte, CTA violet
6. **KpiTintCard** - 4 teintes, illu, caption
7. **DockNavy** - opaque, disque actif, FAB surélevé **dans** le bottom bar, pas un 2e FAB caisse
8. **AiBubble** - assistant gauche violet-soft, user droite bleu, streaming caret
9. **SkeletonKpi** - shimmer aux rayons 22

Vendre reste **1 tap** (FAB dock + card Vendre). Pas de 2e FAB sur le checkout.

---

## 5. Maquette dashboard (a valider avant tout autre ecran)

```
┌─────────────────────────────────────┐
│ [photo boutique →]  [bleu sature]   │
│  (Lynk)  Bonjour,          (bell)(0)│
│          Oscar 👋                   │
│          Que vendez-vous            │
│          aujourd'hui ?   (menthe)   │
│          📍 CHEZ OSCAR              │
│    ┌───────────────────────────┐    │
│    │ 🔍 Rechercher un produit  │ QR │
│    └───────────────────────────┘    │
├─────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐     │
│  │ Vendre     │  │ Encaisser  │     │
│  │ cyan 3D    │  │ violet 3D  │     │
│  │ sacs  →    │  │ pieces     │     │
│  └────────────┘  └────────────┘     │
│  ┌─────────────────────────────┐    │
│  │ ⭐ Lynk · priorité du jour  │    │
│  │ (mascotte)  message…        │📋  │
│  │ Demander à Lynk →           │    │
│  └─────────────────────────────┘    │
│  ┌───────┐ ┌───────┐          (◀◀)  │
│  │vert   │ │lavande│                │
│  └───────┘ └───────┘                │
│  ┌───────┐ ┌───────┐                │
│  │peche  │ │rose   │                │
│  └───────┘ └───────┘                │
│                                     │
│    ┌──────────────────────────┐     │
│    │ ⬤Accueil  Ventes ⬤caisse │     │
│    │              Assistant Plus│    │
│    └──────────────────────────┘     │
└─────────────────────────────────────┘
```

Comportement :

- Pull-to-refresh : Lynk brief se met a jour, haptique light
- Tap Vendre / FAB = `/sale/new` (1 tap)
- Tap Encaisser = `/debts`
- Tap Demander a Lynk = Hero Lynk + `/ai` (shared element)
- Tap Assistant = sheet rapide, long-press = `/ai`
- Padding bas = dock 64 + FAB overflow 10 + safe area + 16. **Rien de coupe.**
- Chevron bleu : proposition = replie/etend le brief Lynk. Si refuse, on le vire.

Calibration qualite : si un ecran (Rapports, Stock, IA…) est plus terne que ce dashboard, il est refuse.

### Declinaison des autres modules (apres validation dashboard)

| Ecran | Header | Cards |
|---|---|---|
| Ventes | bleu header court | liste tickets blancs, statut vert/orange/rose |
| Stock | photo rayons + bleu | alertes peche, OK vert |
| Rapports | **interdit le noir** | 4 KPI memes teintes que l'accueil + graphe |
| Clients | creme | avatars, dettes peche |
| IA | degrade bleu→violet, Lynk Hero | bulles, chips violet |
| Plus | blanc | icones Phosphor fill, pas Material outlined |

---

## 6. Plan d'execution (apres ton OK seulement)

1. Brancher tokens + Plus Jakarta + Phosphor + Rive (pubspec)
2. Generer les 8 illustrations + `lynk.riv`
3. Reconstruire **uniquement le dashboard + dock**
4. Screenshot vs `template.jpeg`, gap list
5. Rapports (tuer le bloc noir) → Stock → Ventes → IA → reste

Contraintes techniques inchangees : Flutter Material 3, pas CupertinoApp, Predictive Back, tap 48, TalkBack, dock au-dessus de la barre de geste.
