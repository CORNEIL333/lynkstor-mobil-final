# Design stack - Lynkstor v2 (source de verite : `docs/reference/template.jpeg`)

Statut : **propose, en attente de validation**. Aucun ecran n'est recode tant que ce document + `DESIGN_SYSTEM_V2.md` ne sont pas valides.

## Deja dans le projet (on garde)

| Package | Role v2 | Pourquoi on le garde |
|---|---|---|
| `flutter_riverpod` + `riverpod_annotation` | Theme tokens, `performanceMode`, prefs Lynk, session | Deja le SM de l'app. Le design system reste des constantes Dart + ThemeData, pas un store. Riverpod expose `performanceMode` pour le fallback GPU. |
| `google_fonts` | Plus Jakarta Sans (variable-like weights) | Present dans `pubspec` mais **jamais branche**. On l'active. Offline : bundler les TTF dans `assets/fonts/` au build release pour les boutiques sans reseau. |
| `flutter_animate` | Springs, stagger KPI, press scale, header breathe | Deja la. Couvre 90 % du motion Expressive sans nouvelle dependance lourde. |
| `shimmer` | Skeleton des KPI / listes | Deja la. |
| `flutter_svg` | Icones custom + pictos 2D | Deja la. |
| `fl_chart` | Mini sparkline KPI Ventes | Deja la. On le bride (1 serie, pas d'animation continue en mode perf). |
| `go_router` | Navigation, Predictive Back | Deja la. |

## A installer apres validation (pas avant)

| Package | Role | Pourquoi |
|---|---|---|
| `phosphor_flutter` | Iconographie rounded/fill | Les icones Material par defaut sont trop anguleuses vs la reference (caisse, home fill, cloche, scan). Phosphor Fill/Regular colle au style "blob doux". Une seule famille. |
| `rive` | Avatar Lynk idle / talking / sorry | La reference montre un personnage 3D clay, pas un CustomPainter 2D. Rive = vectoriel anime, fichier leger, pause auto si `disableAnimations` / `performanceMode`. |

## A ne PAS installer

| Package | Pourquoi non |
|---|---|
| `lottie` en plus de Rive | Double runtime animation. Rive suffit pour Lynk. Les illustrations de cards (sacs, pieces, checklist) sont des **PNG/WebP statiques** generes, pas des JSON Lottie 3D. |
| `liquid_glass_widgets` / shaders glass | `BackdropFilter` = 6-9 ms raster sur mid-range Android. Segment terrain = bas/moyen de gamme. Le dock de la reference est **opaque marine**, pas du verre. |
| `ui_animations_pro` / `haptic_kit` | Overkill. `HapticFeedback` SDK + `flutter_animate` suffisent. |
| `cupertino_icons` comme famille UI | Interdit visuellement. On le laisse en dependance transitive mais on ne l'utilise plus dans le DS. |

## Assets visuels a produire (pas des packages)

Apres validation, generation d'illustrations 3D clay alignees sur la reference :

- `assets/images/hero_shop.jpg` - boutique etageres, cadrage droite
- `assets/illu/bags_vendre.webp` - 3 sacs shopping qui debordent
- `assets/illu/wallet_encaisser.webp` - portefeuille + pieces
- `assets/illu/clipboard_lynk.webp` - presse-papiers checklist
- `assets/illu/spark_ventes.webp` - courbe / sparkline verte
- `assets/illu/coins_encaisse.webp` - pile de pieces
- `assets/illu/people_dettes.webp` - silhouettes peche
- `assets/illu/calendar_acomptes.webp` - calendrier + coche
- `assets/rive/lynk.riv` - mascotte (idle / wave / talking)

## Theme / tokens

Les couleurs ne vivent **pas** dans Riverpod. Elles vivent dans `lib/core/theme/app_colors.dart` (tokens extraits de la capture). Riverpod ne fait que :

- `performanceMode` -> desactive springs, blur, header breathe
- `lynkPrefs` -> nom d'affichage, pas la palette

`ThemeData(useMaterial3: true)` reste le moteur. On **n'utilise pas** `CupertinoApp`. Predictive Back Android reste.

## Fallback perf (mode terrain)

Detecte via le flag existant `session.performanceMode` (+ `MediaQuery.disableAnimations`) :

| Effet | Qualite | Fallback |
|---|---|---|
| Header photo + degrade 2 stops | toujours | photo plus sombre, 1 stop |
| Cards action degrade 2 stops | toujours | aplat = stop 1 |
| Ombres teintees 2 couches | qualite | 1 couche, blur 12 |
| Stagger KPI | qualite | instant |
| Rive Lynk idle | qualite | frame statique |
| `BackdropFilter` | **jamais** | dock opaque `#072048` |
| Header "breathe" | qualite | statique |

## Installation (commande, a lancer seulement apres OK)

```
flutter pub add phosphor_flutter rive
```

`google_fonts`, `flutter_animate`, `shimmer` : deja presents, zero install.
