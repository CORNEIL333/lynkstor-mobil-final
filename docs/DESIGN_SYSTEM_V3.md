# Design system V3 — Lynkstor « Midnight Ledger »

**Statut** : direction gelée après validation utilisateur. Source de vérité visuelle : maquettes `docs/reference/premium_v3/`. Remplace DESIGN_SYSTEM_V2.md (template clay 3D abandonnée) et clos l'audit UI_UX_AUDIT_2026-09-22.md.

**Principe cardinal** : la hiérarchie s'exprime par le poids typographique et l'espace, jamais par la couleur. Un écran = une seule couleur d'accent. Le violet n'appartient qu'à Lynk (IA). Aucune illustration 3D, aucun glassmorphism, aucun dégradé sur les surfaces métier, aucun emoji dans le chrome.

---

## 1. Tokens couleur

### 1.1 Clair (référence)

| Rôle | Hex | Usage |
|---|---|---|
| `bg` | `#F6F8FB` | fond de page |
| `surface` | `#FFFFFF` | cartes, feuilles |
| `surfaceMuted` | `#F0F3F8` | champs, zones retirées |
| `ink` | `#0B1524` | texte primaire, chiffres |
| `inkMuted` | `#56657C` | texte secondaire (≥ 4,5:1 sur bg/surface) |
| `inkFaint` | `#8B98AB` | légendes ONLY non essentielles |
| `line` | `#DDE4EE` | séparateurs, bordures |
| `accent` | `#2563EB` | action primaire, FAB, onglet actif, liens |
| `accentDeep` | `#1D4ED8` | press/hover |
| `accentSoft` | `#E8EFFD` | fonds de badges actifs, sélection |
| `onAccent` | `#FFFFFF` | texte sur accent (ratio 5,2:1 — conforme AA) |
| `ai` | `#6D28D9` | Lynk uniquement : bulles, CTA IA, badges IA |
| `aiSoft` | `#F1EAFE` | fond bulles/panneaux IA |
| `success` | `#15803D` | payé, sync OK, stock OK |
| `successSoft` | `#E6F4EC` | fond badge succès |
| `warning` | `#B45309` | en attente, stock bas, essai |
| `warningSoft` | `#FBF0DF` | fond badge avertissement |
| `danger` | `#B91C1C` | impayé, erreur, destructif |
| `dangerSoft` | `#FBE9E9` | fond badge erreur |
| `info` | = `accent` | information neutre |

### 1.2 Sombre (dérivé des mêmes rôles)

| Rôle | Hex |
|---|---|
| `bg` | `#0B1524` |
| `surface` | `#111D2E` |
| `surfaceMuted` / carte haute | `#18273C` |
| `line` | `#26374F` |
| `ink` (texte) | `#E9EFF7` |
| `inkMuted` | `#A3B1C6` |
| `accent` | `#4F83F1` (éclairci pour contraste ≥ 4,5:1 sur surfaces nuit) |
| `ai` | `#A78BFA` |
| `success` | `#4ADE80` · `warning` `#FBBF24` · `danger` `#F87171` (fonds soft = même teinte à 14 % d'alpha) |

En sombre : bordures hairline au lieu d'ombres. **Interdit** : noir pur `#000`, blanc pur sur noir sans alpha intermédiaire.

### 1.3 Paires sémantiques (règle absolue)

Chaque rôle de fond a son texte associé défini dans le thème. Aucun composant n'a le droit d'imposer `Colors.white` ou un hex en dur ; uniquement les tokens. C'est la correction du constat P1 de l'audit (blanc sur orange 2,16:1).

## 2. Typographie

Famille : **Plus Jakarta Sans** (google_fonts, fallback TTF embarqué). Chiffres : `fontFeatures: ['tnum']` (tabulaire) partout où un montant est affiché, format `NumberFormat.decimalPattern('fr_FR')` + ` FCFA`.

| Rôle | Taille | Poids | Tracking | Usage |
|---|---|---|---|---|
| display | 28 | 800 | -0.5 | prénom hero, gros total |
| h1 | 22 | 700 | -0.3 | titre d'écran, total caisse |
| title | 18 | 700 | -0.2 | en-têtes de section, AppBar |
| body | 15 | 500 | 0 | texte courant |
| bodyStrong | 15 | 600 | 0 | libellés actifs |
| caption | 12 | 500 | +0.1 | métadonnées, aides |
| overline | 11 | 700 | +0.6 (majuscules) | étiquettes de section |
| money | 20 | 800 | -0.4 | montants KPI |
| moneySm | 15 | 700 | -0.2 | montants en liste |

Interligne : 1,35 pour display/h1 ; 1,45 pour body. Aucune taille < 11.

## 3. Forma (rayons, espacements, ombres)

- Rayons : `field 14` · `card 18` · `sheet 26` (haut des feuilles modales) · `pill 999` (badges, chips, dock).
- Espacement : base 4 ; rythme `8 / 12 / 16 / 24 / 32 / 40`. Marge de page 16. Padding carte 16. Gap entre sections 24.
- Ombres (clair uniquement, très discrètes) :
  - `card` : `0 1 2 rgba(11,21,36,.05)` + `0 8 24 -12 rgba(11,21,36,.10)`
  - `fab` : `0 10 24 -8 rgba(37,99,235,.45)` (teintée accent, jamais noire)
  - `sheet` : `0 -8 40 -12 rgba(11,21,36,.22)`
- Cibles tactiles : **48 × 48 dp minimum partout** (l'icône peut faire 20-24).

## 4. Motion

| Token | Spéc | Usage |
|---|---|---|
| `press` | scale 0,98, 120 ms ease-out | tout élément tappable |
| `entry` | fade + translateY 8 px, 180 ms ease-out | apparition de liste/cartes |
| `stagger` | 40 ms entre items (max 6 items animés) | grilles KPI |
| `hero` | spring stiffness 380 damping 24, overshoot léger | transitions Lynk, FAB→caisse |
| `sheet` | spring standard, 220 ms | feuilles modales |

`MediaQuery.disableAnimations` OU mode performance ⇒ état final rendu immédiatement, AUCUNE animation (correction du bug `fadeIn(target:0)` relevé par l'audit). Aucune animation ne doit retarder une action de caisse.

## 5. Composants (règles)

- **Boutons** : primaire (aplat accent, onAccent, radius 14, hauteur 52) · secondaire (surface + bordure line, texte ink) · tertiaire (texte accent seul) · destructif (danger). États : loading (spinner inline, tap bloqué), disabled (38 % d'alpha, jamais grisé inventé).
- **Cartes** : surface, radius 18, ombre `card`, padding 16. Une action principale maximum par carte.
- **Champs** : label au-dessus (caption 600), champ 52 dp, radius 14, fond surfaceMuted, bordure focus accent 1,5 px, erreur inline sous le champ (danger + icône, jamais le champ qui rougit seul).
- **Badges de statut** (pills overline, fond soft + texte saturé) : `Payé` success · `En attente` warning · `Impayé` danger · `Brouillon` inkMuted/surfaceMuted · `Stock bas` warning · `Hors ligne` inkMuted · `Synchronisé` success · `IA/Lynk` ai.
- **KPI** : label overline + montant money + variation réelle (delta calculé) OU rien. **Sparkline interdite sans données réelles et période affichée** (constat P1 de l'audit).
- **Listes métier** : ligne 64 dp min, titre bodyStrong, sous-titre caption, montant à droite aligné tabulaire, chevron ou action. Séparateur line indenté sous le contenu.
- **États** : `LsEmptyState` (illustration sobre + titre + action), `LsErrorState` (message + « Réessayer » obligatoire, données préservées), `LsSkeleton` (shimmer aux rayons finaux, jamais de spinner nu sur un écran plein).
- **Navigation** : dock blanc (clair) / surface (sombre) en pill flottante, 5 destinations filtrées par permissions — Accueil, Ventes, **FAB caisse central surélevé (accent)**, Assistant, Plus. Rail ≥ 840 dp conservé. Un seul composant de navigation actif (le `KumbaFloatingNavBar` mort est fusionné/supprimé).
- **Lynk** : avatar = monogramme « L » ou visage CustomPainter épuré, pastille en ligne verte ; bulles assistant `aiSoft` à gauche, utilisateur `accent` à droite ; streaming par caret, « Lynk réfléchit… » en skeleton.

## 6. Notifications et feedback — API unique `LsFeedback`

Un seul point d'entrée dans toute l'app ; plus aucun `SnackBar`/`showDialog` brut dans les écrans.

- **Toast** (confirmation légère) : ancré en haut sous la status bar, pilule surface + bordure line + icône de rôle (success/warning/danger/info) + message 2 lignes max, durée 2,5 s (4 s si action « Annuler » inclusive), fermeture par swipe, aucun emoji, pile max 2.
- **Bannière persistante** (état système : hors ligne, sync en attente, abonnement) : bandeau pleine largeur sous l'AppBar, fond soft du rôle, texte ink, action à droite, non automatique, rétractable.
- **Confirmation destructive** : `LsDialog` titre + impact chiffré + bouton danger explicite (« Supprimer 3 ventes »), annulation à gauche, jamais le destructif en couleur par défaut.
- **Snackbars Material et dialogs brut** : interdits (lint par revue de diff).

## 7. Dosage par écran

- Une couleur d'accent par écran au plus (l'accent métier : accent bleu, ou ai violet sur l'écran Lynk).
- Les sémantiques (success/warning/danger) n'apparaissent que dans badges, deltas et retours de feedback — jamais en décor.
- Illustrations IA sobre (6-8 max, style abstrait premium lumière douce, jamais 3D clay) : onboarding, abonnement, états vides. Budget total < 1,5 Mo en webp.

## 8. Accessibilité (contraintes permanentes)

- WCAG 2.2 AA : 4,5:1 texte courant, 3:1 grand texte, vérifié **dans les deux thèmes** par un test dédié parcourant les paires de tokens.
- Semantics : nom + rôle sur toute action iconique ; annonce du compteur de notifications ; pas de double annonce des icônes décoratives.
- Texte jusqu'à 200 % sans cassure (hauteurs pilotées par le contenu, jamais fixes pour du texte) ; rendus validés à 320 / 390 / 600 dp.

## 9. Périmètre intouchable

Routes/go_router, providers Riverpod, services, permissions, montants et logique comptable, textes FR/EN (`S.tr`), offline-first, licence/abonnement : seuls les couches `build` et styles changent. Les tests existants doivent rester verts (hors 5 échecs baseline connus).
