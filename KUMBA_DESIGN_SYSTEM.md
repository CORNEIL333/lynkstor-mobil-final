# KUMBA Design System — Océan · Ciel · Crème

Identité **bleu océan (primaire) · bleu ciel (secondaire) · blanc crème**.  
Accent chaud **corail** uniquement pour CTA secondaires, célébrations, joue de Lynk.  
Palette **IA** réservée aux surfaces générées (jamais un KPI brut).

---

## Dials

| Dial | Valeur | Note |
|------|--------|------|
| DESIGN_VARIANCE | 6 | Îlots + color-blocks océan/ciel |
| MOTION_INTENSITY | 6 | Stagger, press, halo IA lent |
| VISUAL_DENSITY | 4 | ERP lisible, pas cockpit |

---

## Couleurs (hex)

### Marque

| Token | Hex | Rôle |
|-------|-----|------|
| `ocean` | `#0E5A8C` | Primaire, headers, CTA, nav active |
| `oceanDeep` | `#0A3F66` | Gradients bas, dark containers |
| `sky` | `#4BA3E3` | Secondaire, états actifs, ice |
| `skySoft` | `#D6EEF8` | Fonds teintés, chips |
| `skyMist` | `#B8E0F5` | Color-blocks clairs |
| `cream` | `#FBF7F2` | Scaffold (blanc chaud, jamais clinique) |
| `creamCard` | `#FFFCF8` | Cartes |
| `white` | `#FFFFFF` | Contraste max, nav glass |

### Accent chaud (nouveau, rationné)

| Token | Hex | Rôle |
|-------|-----|------|
| `coral` | `#E07A5F` | CTA secondaire, joue Lynk, mise en avant |
| `coralSoft` | `#FDE8E1` | Fonds d’alerte positive |

### Sémantique (désaturé)

| Token | Hex | Rôle |
|-------|-----|------|
| `success` | `#2F9E7A` | OK, stock suffisant |
| `successSoft` | `#D8F3EA` | Fonds succès |
| `warning` | `#D4A017` | Seuil, pending |
| `warningSoft` | `#F8EBC7` | Fonds warning |
| `danger` | `#D45B6A` | Erreur, rupture, dette |
| `dangerSoft` | `#F8DDE1` | Fonds erreur |

### Neutres chauds

| Token | Hex | Rôle |
|-------|-----|------|
| `ink` | `#1C2A38` | Texte principal |
| `inkMute` | `#5C6B78` | Secondaire, captions |
| `line` | `#E6DFD6` | Séparateurs |
| `disabled` | `#C9C2B8` | Contrôles off |

### Palette IA (uniquement « généré / assistant »)

| Token | Hex | Rôle |
|-------|-----|------|
| `aiViolet` | `#6B5CE7` | Milieu du dégradé IA |
| `aiCyan` | `#3EC8E0` | Highlight glow |
| `aiGlow` | `#7B8CFF` | Halo 16–24 % |

**Dégradés signature**

1. **Marque** : `#0E5A8C` → `#4BA3E3`  
2. **Premium** : `#0E5A8C` → `#E07A5F`  
3. **IA** : `#0E5A8C` → `#6B5CE7` → `#4BA3E3`

Mode sombre : scaffold `#0B1824`, cards `#122433`, glow IA plus visible (`aiGlow` 28 %). Pas d’inversion crème→noir brut.

Alias rétrocompat code actuel : `primary` → ocean, `secondary` → sky, `background` → cream, `turquoise` → success (plus d’accent turquoise concurrent).

---

## Typographie

- **Titres** : système géométrique (SF / Roboto) **w800**, tracking −1.2 à −0.4.  
- **Corps** : même famille **w400–w600**, line-height 1.45–1.5.  
- **Données** : `FontFeature.tabularFigures()`, w700.  
- **Texte IA** : w500, couleur `ink`, filet dégradé IA à gauche — jamais la même graisse qu’un montant Drift.

| Niveau | Size | Weight | Height | Tracking |
|--------|------|--------|--------|----------|
| H1 display | 34 | 800 | 1.05 | −1.2 |
| H2 | 24 | 700 | 1.18 | −0.55 |
| H3 | 18 | 700 | 1.25 | −0.22 |
| body-large | 17 | 400 | 1.5 | 0 |
| body | 15 | 400 | 1.48 | 0 |
| caption | 12 | 500 | 1.35 | 0.1 |
| label | 12 | 700 | 1.3 | 0.15 |
| tabular | 16–28 | 700 | 1.12 | −0.4 |

---

## Espacement & forme

Échelle : `4, 8, 12, 16, 20, 24, 32, 40`.  
Page : gutter 20. Cards padding 18. Tap ≥ 44.  
Rayons : 12 / 16 / 20 / 24 / 28 / 32 / capsule.  
Ombres : 2 couches teintées océan (blur 24 + highlight crème), jamais noir 40 %.

---

## Motion

| Token | Valeur |
|-------|--------|
| press | 90–120 ms, scale 0.96–0.97 |
| chip / badge morph | 180 ms |
| nav / sheet | 280–350 ms, `cubic-bezier(0.32, 0.72, 0, 1)` |
| stagger list | 50–80 ms |
| page | 300 ms ease-in-out (slide H) |
| graph draw | 400–600 ms |
| halo IA | loop 4–8 s, opacity 0.12–0.22 |
| stream caret | pulse 700 ms |

Courbes : UI `cubic-bezier(0.23, 1, 0.32, 1)` ; déplacement `cubic-bezier(0.77, 0, 0.175, 1)` ; pop `easeOutBack` léger.  
Jamais `scale(0)`. Reduce-motion : fade 180 ms.

---

## Morphologie (look iOS, moteur M3)

Pas de M3 stock. Pas de `CupertinoApp`. Formes calées sur les refs (dock flottant, pills, cards 24–32).

| Famille | Forme | Interaction |
|---------|--------|-------------|
| Bottom nav | Dock pill radius 32, H 64, glass crème + blur 28 | Indicateur pill ciel ; FAB 64 océan au-dessus |
| Bouton primaire | Capsule 999 × H 52 | Scale 0.97 / 90 ms, **sans ripple** |
| Bouton secondaire | Même capsule, stroke ciel 1.2 | Idem |
| Card métier | Radius 24, crème, ombre océan 2 couches | Press scale 0.97 |
| Card KPI | Radius 28, fill ice/ciel | Idem |
| Hero / îlot | Radius 32 | — |
| Champ | Radius 20, fill crème, pas d’underline | Focus anneau ciel 2 px |
| Sheet | Radius haut 28 + grabber | Swipe down **et** retour Android |

Plateforme : retour physique / geste = pop ; Predictive Back sur Android 14+ ; tap 48 dp ; TalkBack Material. Détail : `docs/REDESIGN_ARCHITECTURE.md` §0.

## Composants (contrat)

- Boutons : primaire océan (ou dégradé marque), secondaire outline océan, tertiaire texte, **coral** pour CTA doux, FAB Vendre océan, **chip Lynk** (pas un 2e FAB caisse).
- Champs : label au-dessus, erreur en dessous, focus anneau ciel 2 px.
- Cards : KPI color-block ciel/océan, métier crème, **IA** bordure dégradé + badge.
- Badge `Généré par IA` : fond `skySoft`, point `aiViolet`, 11 px w700.
- Bottom nav : verre crème, pill ciel sous l’icône active, slot 4 = Lynk.
- Sheet IA, toasts slide, skeletons pulse crème→skySoft.
- Graphiques : océan / ciel / coral ; tooltip scale 0.97→1.
- `LynkAvatar` : voir `docs/AI_AVATAR_SPEC.md`.

---

## Surfaces

| Surface | Signature |
|---------|-----------|
| Accueil | Crème, greeting, KPI océan/ciel, Lynk 64 |
| Caisse | Grille, FAB océan, **pas de chip Lynk** |
| IA | Halo dégradé IA, bulles asymétriques, stream |
| Plus | Grille modules, ice tiles |
| Nav | Crème glass, Lynk idle onglet 4 |
