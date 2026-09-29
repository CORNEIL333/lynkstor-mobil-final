# Audit de conformité — Maquette DAVEX ↔ App LYNKSTOR (v2, règle stricte)

Règle appliquée : **maquette > iOS HIG > code existant**. Le code existant n'est
jamais une référence de design. En cas de doute : **RECRÉER**.
- **CRÉER** : composant absent de l'app → nouveau fichier.
- **RECRÉER** : un composant « proche » existe mais diffère → nouveau fichier
  séparé qui remplace l'usage de l'ancien (interdiction de patcher l'ancien en place).
- **RÉUTILISER TEL QUEL** : identique au pixel ET conforme HIG — justifié explicitement.

Références maquette :
- `docs/reference/figma_export/PrototypeApplicationDesign-main/src/App.tsx` (10 200 lignes)
- `src/design-system/components.css` (1 197 lignes)
- `src/imports/design-system.md`, `src/ui/tokens.css`

---

## 1. Composants système (shell)

| Composant maquette | Réf. maquette | Existant dans l'app | Décision | Justification |
|---|---|---|---|---|
| `lk-header` (LynkstorHeader.tsx) | gradient navy 116deg, blob orange 204px, avatar 58px cercle bord 3px blanc/70, actions 44px rondes #16253A, badge compte orange | `design_system/components/lynkstor_header.dart` | **RECRÉER** | Structure fidèle MAIS actions divergentes : maquette = [Panier][Bell][Menu], app = [Search][Bell][Menu] ; typo/espacements non vérifiés au pixel. Nouveau fichier `davex_app_header.dart`, ancien déréférencé. |
| `lk-bottom-navigation` | fond navy #091829 fixes (2 thèmes), bord #142B45, min-height 80px, actif = pastille #FF9800 + label #FFAD24 + halo radial | `design_system/components/lynkstor_bottom_navigation.dart` | **RECRÉER — fait (cette session)** | Contenu du fichier entièrement réécrit à 100 % depuis components.css (aucune ligne conservée de l'ancien blanc/bleu). Vérifié sur Infinix : conforme. |
| `SyncIndicator` (pill transport) | pill bord 1px, point d'état, 3 états cloud/local/pending | `shared/widgets/sync_indicator.dart` (approx.) | **RECRÉER** | Version maquette avec couleurs exactes des tokens et textes FR/EN propres → nouveau fichier `davex_sync_indicator.dart`. |
| Shell (MainAppShell) | App.tsx L5411–6060 : header + contenu + nav + tiroirs | `shared/widgets/shell_scaffold.dart` | **RECRÉER** | Assemblera les composants recréés ; l'ancien fichier reste en place jusqu'à bascule du router, puis suppression. |
| Alertes de confirmation | modales maquette + standards iOS | — (Material dialogs / showLkToast) | **CRÉER** | Aucun composant conforme : nouveau `davex_alert.dart` sur `CupertinoAlertDialog` (HIG Alerts : titre gras, message corps, bouton destructif rouge à gauche/au-dessus, bouton par défaut gras). |
| Notifications in-app (banner) | panneau bell + toasts maquette | toasts Material custom | **CRÉER** | `davex_toast.dart` style banner natif iOS (icône, titre, sous-titre, durée, swipe up pour dismiss) ; écran notifications → RECRÉER depuis la maquette. |
| Tab bar safe area | haut 80px + safe area bottom | nav recréée | **CONFORME** | Voir checklist §8 (écart volontaire 80px vs 49pt imposé par la maquette). |

## 2. Primitives (components.css)

| Composant maquette | Décision | Justification / cible |
|---|---|---|
| `LynkstorMetricCard` (`lk-metric-card`, tons info/warning/danger/success) | **CRÉER** | Absent. → `design_system/components/davex_metric_card.dart` : padding 16 (12 dans lk-home), radius 16, bord borderDecorative, ombre shadowCard, icône 36px tile teinté, value 24px (20px lk-home), label/caption 12px textSecondary. |
| `LkButton` (`lk-button` + variantes) | **RECRÉER** | `lk_primitives.dart:LkButton` diffère (rayons/états/hover maquette). → `davex_button.dart`. |
| `lk-icon-button` (44px, fond #16253A dans header) | **RECRÉER** | Zone tactile 44×44pt (HIG) ✓ maquette. → `davex_icon_button.dart`. |
| `LkField`/`LkInput`/`lk-search-field` | **RECRÉER** | Style maquette : hauteur 44px, radius 12, bord borderControl. → `davex_text_field.dart`. |
| `LkBadge` / `lk-status-badge` (5 tons, min-height 26px, bord currentColor) | **RECRÉER** | → `davex_status_badge.dart`. |
| `lk-filter-chip` (pill filtre actif/inactif) | **CRÉER** | Absent. → `davex_filter_chip.dart`. |
| `lk-quantity-selector` (− n +) | **CRÉER** | Absent en style maquette. → `davex_quantity_selector.dart`. |
| `lk-qr-banner` | **CRÉER** | → `davex_qr_banner.dart`. |
| `lk-section-title` | **CRÉER** | → `davex_section_title.dart`. |
| `lk-state` (loading/error/empty) | **RECRÉER** | `kumba_states.dart` ≠ maquette. → `davex_states.dart`. |
| Sheet / modale (presentation modale iOS) | **CRÉER** | → `davex_sheet.dart` : `showCupertinoModalBottomSheet`-style, poignée 36×5, radius top 20, detents HIG (medium/large), drag-to-dismiss. |

## 3. Écran Accueil (`AccueilScreen` App.tsx L2869–3419)

| Bloc maquette | Décision | Adaptation logique projet (données réelles) |
|---|---|---|
| Greeting bar (date fr-FR + SyncIndicator + « boutique · ville ») | **RECRÉER** (écran neuf) | Date réelle `DateFormat` ; nom boutique = `session.business` ; ville s'il existe, sinon « Ville non renseignée » comme la maquette. |
| Grille 6 actions rapides (rose/bleu/émeraude/ambre/violet/indigo) | **RECRÉER** | Cartes identiques au pixel, câblées sur les vraies routes : Dépenses→`/expenses`, Rapports→`/reports`, Clôture Z→`/reports` (section caisse), Carnet de Dette→`/debts`. **Conflit signalé** : « Client PWA/USSD » et « Fidélité & Coupons » n'existent pas dans le projet → remplacées par « Clients »→`/customers` et « Historique ventes »→`/sales` (mêmes couleurs/position). Jamais de faux succès. |
| 3 KPI (Total articles / Stock faible / Rupture critique) | idem | `ReportService.stockValue()` : product_count / low_count / out_count. |
| Courbe CA (Heures/Semaine/Mois, tooltip, aire lissée dégradé #4F46E5→#7C3AED→#06B6D4) | **CRÉER** (`davex_area_chart.dart` + painter) | Ventes réelles `db.getSales` agrégées : heures du jour / 7 jours / 4 semaines. Pic = max réel. Tooltip au tap. |
| Donut modes de paiement du jour (48/32/15/5, couleurs #0050FF/#12B76A/#F79009/#7A5AF8) | **CRÉER** (`davex_donut_chart.dart`) | Parse `sales.paymentMethodsJson` du jour : cash→Espèces, momo→Mobile Money, credit→Carnet de Dette, mixte→Paiement Mixte. Pourcentages réels. |
| Ventes par catégorie (barres dégradées + chip %) | **CRÉER** | `saleItems` → `product.categoryId` (libellé humanisé), CA réel du jour. |
| Carte IA sombre « Rentabilité & Heures de Pointe » | **RECRÉER** | Marge = (ventes − coût) / ventes réel (`saleItems.costPrice`) ; bénéfice = collected − expenses (`DailyReport`) ; pic d'affluence = heure réelle max. Déterministe local, pas de IA fantôme. |
| Alertes de stock (pliable, badge count) | **CRÉER** | `db.getProducts(lowStock:true)` + ruptures (`stockQty<=0`) : nom + quantité réels. |
| Ventes récentes (4–5 lignes) | **CRÉER** | 5 dernières ventes `db.getSales` : référence, mode, articles, « il y a N min » réel, total. « Voir tout »→`/sales`. |

## 4. Écran Vente (`VenteScreen` L963–2868) — **LIVRÉ (a8/a8b)** — checklist §11b

| Bloc | Décision | Notes |
|---|---|---|
| Grille produits + recherche/scan + filtres catégories | **RECRÉER** | Données Drift réelles ; `lk-sale-*` CSS. |
| Panier latéral/drawer + `lk-quantity-selector` | **RECRÉER** | Panier réel (provider existant). |
| Modale paiement (méthodes, momo désactivé = « prochaine version ») | **RECRÉER** | Conserver le garde-fou existant (pas de faux Mobile Money). |
| Reçu / ticket | **RECRÉER** | Receipt existante à re-styler via nouveau fichier. |
| Détail produit (`product-detail` CSS) | **RECRÉER** | |

## 5. Écran Stock (`StockScreen` L3444–4631) — **LIVRÉ (a9)** — checklist §11c

| Bloc | Décision | Notes |
|---|---|---|
| En-tête modes (express/assisté) + recherche + chips | **RECRÉER** | |
| Liste/catégorie produits (grille/liste, images on/off) | **RECRÉER** | Produits Drift réels. |
| Mouvements de stock (modale raison) | **RECRÉER** | Services existants. |
| Catalogue secteur (qr banner, activation) | **RECRÉER** | `assets/catalogue/*.json` réels. |

## 6. Écran Assistant (`AssistantScreen` L4632–5072) — LIVRÉ (a10) — checklist §11e

| Bloc | Décision | Notes |
|---|---|---|
| Bulles de chat + chips suggestions + bandeau modèle IA | **RECRÉER** | IA locale réelle (déterministe + optional cloud), jamais de réponse inventée. |
| Bandeau « Carnet de Dette » (dégradé navy + action orange) | **RECRÉER** | Données RÉELLES (`CustomerService.debtors` → somme balance > 0) ; « Ouvrir » route `/debts`. |
| Modales de la maquette (liste dettes, détail, remboursement, WhatsApp) | **NON DUPLIQUÉES** | `/debts` (DebtsScreen) est la source unique ; rappel WhatsApp existe (`notifications_screen`, deep link `wa.me`). |

## 7. Onboarding & modales shell (`OnboardingFlow` L466–962 ; modales L5073–5410+) — LIVRÉ (a11) — checklist §11d

| Bloc | Décision | Notes |
|---|---|---|
| Onboarding (secteur, catégories, activation) | **RECRÉER** | Codes d'activation + catalogue secteurs réels. |
| ExpenseManagementModal | **RECRÉER** | Expenses Drift réelles + permissions. |
| ReportingModal / CashClosureModal / CreditLedgerModal | **RECRÉER** | `recordCashClose`, dettes réelles. |
| ClientPwaModal / LoyaltyModal | **CRÉER puis marquer démo** | Fonctionnalités non implémentées côté projet → accès depuis Accueil **retiré** (voir §3 conflit) ; si la maquette les garde ailleurs, badge « Démo » obligatoire, jamais de succès simulé. |
| Menu sheet / Search modal | **RECRÉER** | Routes réelles. |

---

## 8. Checklist de conformité HIG (composants système)

**Header (`davex_app_header.dart`)**
- Décision : RECRÉER (justification §1).
- Règle HIG appliquée : *Status bar & safe area* — contenu sous la status bar, jamais dessous ; zone tactile actions ≥ 44×44pt (les boutons ronds maquette font 44px ✓) ; *Navigation* — titre d'écran hiérarchisé (Large Title ici car imposé par la maquette).
- Écart volontaire : hauteur > 44pt (structure 2 lignes avec avatar 58px) → **imposé au pixel par la maquette** ; maquette > HIG.

**Tab bar (`lynkstor_bottom_navigation.dart`, recréée)**
- Décision : RECRÉER — fait.
- Règle HIG : *Tab bars* — icône + label toujours visibles, cible ≥ 44pt (item ≈ 90×68 ✓), état actif clairement distingué ✓, safe area bottom respectée ✓.
- Écart volontaire : hauteur 80px vs 49pt standard → imposé par la maquette ; couleur navy fixe en thème clair → imposée par la maquette (documenté dans components.css).

**Alertes (`davex_alert.dart`)**
- Décision : CRÉER.
- Règle HIG : *Alerts* — titre court gras, message factible, 2 boutons max côte à côte, destructif en rouge, bouton recommandé en gras ; pas d'alerte custom qui imite mal le système → widget `CupertinoAlertDialog` natif.
- Écart volontaire : aucun.

**Notifications in-app (`davex_alert.dart` → `davexNotify`)**
- Décision : CRÉER.
- Règle HIG : *Notifications* — banner sous la status bar, icône app + titre + corps, dismissal par geste, ne bloque pas l'interaction.
- Écart volontaire : positionnement au-dessus de la barre d'onglets (contexte marchand, un bouton de caisse ne doit pas être masqué) → signalé, validable.

**Sheets modales (`davex_sheet.dart`)**
- Décision : CRÉER.
- Règle HIG : *Panels/Sheets* — poignée visible, drag-to-dismiss, detents, contenu scrollable, pas de fausse modale rectangulaire.
- Écart volontaire : radius top 20px et fond surface maquette (au lieu du systemMaterialView natif) → maquette.

## 9. Conflits signalés (ne sont pas tranchés en silence)

1. **App Flutter multi-plateforme vs « iOS HIG »** : la cible de test est un Android (Infinix). Choix appliqué : widgets Cupertino (style iOS) partout où le HIG gouverne, conformes à la maquette qui est elle-même iOS-stylée. Les performances/overlays Android restent corrects.
2. **« Client PWA/USSD » et « Fidélité & Coupons »** : n'existent pas dans le projet. Conformément à « adapte aux logiques déjà implémentées » + « jamais de faux succès », les 2 cartes sont remplacées par Clients et Historique ventes (couleurs/positions conservées). À valider par le commanditaire.
3. **Tab bar 80px navy fixe** vs standards iOS 49pt translucide : écart imposé par la maquette, documenté.
4. **Clôture Caisse (Z)** : la maquette ouvre une modale complète ; le projet n'a que `recordCashClose` en base. RECRÉER la modale au pixel et la câbler sur `cash_closes` (fonctionnel réel, pas décoratif). → **FAIT** : sheet native (poignée + detents) avec champ comptage, écart enregistré réellement en base, bannière de confirmation native.

## 10. Ordre d'implémentation (processus unitaire)

1. Primitives : metric card → status badge → button → icon button → text field → filter chip → quantity selector → section title → states → sheet → alert → toast → donut → area chart.
2. Shell : header (recréé) + sync indicator + assemblage dans un nouveau scaffold ; bascule router ; suppression des usages de l'ancien.
3. Accueil (recréé, bloc par bloc, données réelles). → **fait** (checklist §11).
4. Vente → Stock → Assistant → Onboarding → modales.
5. Auto-revue : checklist HIG §8 resserrée par composant + captures sur Infinix.

## 11. Checklist composant d'écran — Accueil (a7, livré)

**Écran Accueil (`lib/features/dashboard/davex_accueil_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `dashboard_screen.dart` conservé tel quel, déréférencé du router (plus aucune fusion).
- Règle HIG appliquée : cibles tactiles ≥ 44×44pt sur toutes les cartes/boutons (`DavexPressable.minTouchTarget`), safe areas (barre de salutation sous la status bar via le shell), textes ellipsés jamais coupés, pull-to-refresh natif (`RefreshIndicator`), hiérarchie typographique maquette respectée (11/12/14/16 px).
- Écarts volontaires (signalés, non improvisés) :
  1. Cartes d'actions rapides aux teintes fixes (rose/bleu/émeraude/amber/violet/indigo) : imposées par la maquette, identiques en thème sombre (comme les charts et le header).
  2. Cartes « Client PWA/USSD » et « Fidélité & Coupons » remplacées par « Clients » et « Historique ventes » (conflit §9.2 — fonctionnalités inexistantes du projet ; jamais de faux succès).
  3. Diagramme 4 « Analyse IA » : décor = maquette au pixel, **chiffres 100 % réels** (marge brute = Σ(lineTotal − coût×qty)/ΣlineTotal du jour, pic d'affluence = heure la plus vendue, bénéfice = encaissé − dépenses).
  4. Donut/caisses : les 4 modes de la maquette sont mappés sur les modes réels (`cash`, `mtn_momo`/`orange_money`, `credit`, ventes multi-modes ou partielles → « Paiement Mixte »).
- Données : un seul agrégat `_AccueilData` calculé depuis Drift (DailyReport, stockValue, getSales 28 j, getProducts, getDebtors) — zéro donnée fictive ; chaque empty state affiche « aucune vente » au lieu d'un graphique en trompe-l'œil.
- **Correctif post-capture Infinix (crash « Accueil vide »)** : deux `Row(crossAxisAlignment: stretch)` — grille d'actions rapides et carte IA — étaient posés dans un sliver à hauteur non bornée → `BoxConstraints forces an infinite height` → subtree entier non peint = écran blanc (silencieux en release). Fix : chacun enveloppé dans `IntrinsicHeight` (cartes jumelles de hauteur égale, rendu borné). Régression verrouillée par `test/widget/davex_accueil_diag_test.dart` (611 exceptions avant → 0 après). Bug préexistant corrigé au passage dans `main.dart` : `ref.listen` dans `initState` → `ref.listenManual` (assertion Riverpod qui bloquait tout diagnostic debug). Revérifié sur le release APK (SHA256 `AC418822…D6865`) : les 9 blocs rendent.

## 11b. Checklist composant d'écran — Vente (a8 + a8b, livré)

**Écran Vente (`lib/features/sales/davex_vente_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `sale_screen.dart` (SaleScreen) conservé tel quel sur disque (fixtures de tests), **déréférencé du router** (`/vente` → `DavexVenteScreen(embedded: true)` ; `/sale/new` redirige toujours vers `/vente`). Aucune fusion.
- Logique RÉUTILISÉE TELLE QUEL (justification : c'est la logique métier réelle, intacte) : `SaleService.completeSale` (paiements cash/mtn_momo/orange_money/transfer/crédit/mixte, remise globale `CompleteSaleInput.discount`, garde-fou crédit→client obligatoire + `creditLimit`, équilibrage BillingEngine), `ProductService.byBarcode/update`, `CustomerService.create`, ticket `/sale/receipt/:id`, relance fiche adHoc `/products/new?saleId=`, garde-fou abonnement (`canSell`) message conservé mot pour mot.
- Panier : **a8b FAIT** — `lib/features/sales/davex_cart.dart` = panier en `StateNotifierProvider` persistant (non autoDispose : changer d'onglet ne vide pas la caisse, règle HIG « ne jamais détruire une saisie »), réutilisant `CartLine` tel quel (zéro modèle parallèle). `davexCartBadgeProvider` alimente le **badge Panier live du header DAVEX** (`davex_shell.dart`, avant : codé à 0) ; le bouton Panier ouvre `/vente`.
- Mapping maquette→réel unité par unité : recherche + tuile scan #0050FF ; tuiles produits 2 colonnes (pastille quantité, badge En stock/Stock faible/Service, prix bleu, sku/code-barre, « Stock : n · catégorie » réel via `productService.categories`) ; carte pointillée « Produit hors catalogue » (ligne adHoc RÉELLE → vente réelle → relance fiche) ; barre dégradée « VOIR LE PANIER · n articles · label · total » ; panier plein écran (bandeau client navy dégradé, nom direct OR champ libre réel `customerName`, rattachement client via sheet, lignes − qty +, « Vider », barre basse Remise/Total Net/Encaisser) ; Encaissement (carte dégradée total + 4 tuiles modes : Espèces, Mobile Money, Crédit→vue dédiée, Mixte ; CTA vert « Encaisser X FCFA ») ; Vente à crédit (segment existant/nouveau, lignes clients avec « X F dû » rouge / « Soldé » vert réel `Customer.balance`, création client réelle) ; succès plein écran 1,8 s ; modales : première vente prix (écrit `salePrice` RÉEL sur la fiche), pick quantité avec plafond stock, remise 5/10/15/20 % + libre FCFA (→ `CompleteSaleInput.discount`, alerte >15 % comme la maquette), hors catalogue, rattachement client.
- Écarts maquette↔logique RÉELLE **signalés, jamais tranchés en silence** :
  1. **Multi-paniers** (« Panier 1 / 2e client ») : la logique réelle est une vente à la fois (`completeSale`) → non simulé, écart listé.
  2. **Fidélité/points, coupons, devis/proforma, négociation prix unitaire par ligne** : aucun modèle persisté côté Drift → NON fabriqués. La remise % maquette est mappée sur le seul point d'extension réel (remise globale).
  3. **Mobile Money** : la maquette suggère un push USSD ; le projet n'a que la saisie manuelle de référence → garde-fou existant conservé + note affichée dans la tuile momo (« jamais de faux succès »).
  4. **Scan** : caméra RÉELLE (`BarcodeScannerScreen`) au lieu du simulateur de code de la maquette ; code inconnu → vente hors catalogue (comportement maquette).
  5. **Bleu caisse #0050FF** : pixel imposé par la maquette, hors charte LkPalette (info #1D6BFF) → couleur locale `_posBlue` documentée en tête de fichier, même rôle sémantique (écart ≤ 1 nuance accepté, hiérarchie maquette > existant).
- Bugs trouvés et corrigés PAR LE TEST DE RÉGRESSION (non cosmétiques) :
  1. `TextEditingController` des modales disposé dès `Navigator.pop` alors que l'animation de sortie reconstruit les `TextField` → crash « controller used after dispose ». Fix : contrôleurs portés par le State et disposés dans `State.dispose()`.
  2. Corps de sheets en `Column` nu → `RenderFlex overflowed` dès que le clavier remonte (sheet 0,5–0,6). Fix : chaque corps enveloppé `SingleChildScrollView` (+ `viewInsets` pour la modale hors catalogue).
  3. Lignes hors catalogue (`productId == null`) : variation de quantité par id ambiguë entre plusieurs lignes libres → méthodes par INDEX (`changeQuantityAt`/`setQuantityAt`) dans le notifier.
- Données : 100 % Drift réels (produits actifs, catégories, clients, stock) ; `autoDispose` sur le catalogue = stocks rafraîchis à chaque retour d'onglet (pas de faux stock affiché après vente) ; empty states authentiques (« Aucun produit », « Ce panier est vide »).
- HIG : cibles ≥ 44 pt (DavexPressable/DavexIconButton), feedback haptique sur ajout/achat (sélection + medium), pas de destruction silencieieuse du panier (« Vider » explicite), confirmation de fiche après vente adHoc via dialogue natif,AnimatedSwitcher 220 ms entre vues (cohérence spatiale retour/avant).
- Régression : `test/widget/davex_vente_test.dart` (catalogue vide → modale ligne libre → panier → Total Net + badge provider) **2/2 ✓** ; suite complète **+203, 1 ~, 5 échecs = exactement les 5 échecs préexistants** (google_fonts ×2, finder « Beignet fourré » too many, migration count, premium visual) — aucune régression.

## 11c. Checklist composant d'écran — Stock (a9, livré)

**Écran Stock (`lib/features/stock/davex_stock_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `stock_screen.dart` (StockScreen) conservé tel quel sur disque (fixtures de tests), **déréférencé du router** (`/stock` → `_gate(stockView, DavexStockScreen())`). Aucune fusion.
- Logique RÉUTILISÉE TELLE QUELLE (justification : logique métier réelle intacte) : `ProductService.list/categories/create/update` (le prix de la fiche produit passe par `update` avec `ProductInput` complet — `stockQty` volontairement non modifiable par update), **`ProductService.adjustStock`** (newQty absolu + motif obligatoire + garde-fous `PermissionGuard`/business/`trackStock`, `ValidationException` remontée à l'utilisateur), table RÉELLE `StockMovements` (types schéma `init|sale|purchase|return|loss|damage|inventory|transfer|adjustment`), routes existantes `/products/new`, `/products/:id`, `/products/catalog`, `/purchases`, Lynk réel (`pendingAiPromptProvider` + quick sheet, réponses ancrées).
- Mapping maquette→réel unité par unité : barre recherche + 3 tuiles bleues #0050FF ; chips catégories actives orange (`DavexFilterChip`, données Drift réelles) ; compteur + bascule express (grille) / assisté (show_chart) ; bandeau ambre « n produit(s) à finaliser » ; trio métriques Critique/Bas/Valeur (calculs réels `stockQty×salePrice`, seuils réels) ; assisté = carte navy dégradée « Valeur totale du stock » + « + Mouvement typé » + carte IA + barre d'alerte ambre ; cartes produits à bordure d'alerte (rouge/ambre/neutral) avec badges Rupture/Bas/Disponible/Service ; express = `DavexQuantitySelector` ±1 **staged** (rien n'est écrit avant confirmation) + carte « ±n unité(s) modifiée(s) » + barre violette collante « Appliquer N modification(s) — Motif requis » → sheet motif (presets + champ obligatoire) → `adjustStock(type:'adjustment')` en lot ; assisté = jauge colorée ; **fiche produit** en sheet 0,85 (photo réelle `photoPath`, prix éditable carte bleue → `update`, stock visé ±1/±10 + motif → `adjustStock`, convertisseur carton→unités, derniers mouvements RÉELs via requête Drift inline sur `stockMovements` limit 8, accès fiche complète `/products/:id`) ; **mouvement typé** : sélecteur produit (stock actuel affiché), 7 motifs maquette → types réels (Entrée→`purchase`+, Sortie→`transfer`−, Retour client→`return`+, Retour fournisseur→`return`−, Casse→`damage`−, Consommation→`loss`−, Ajustement→`adjustment` avec bascule Ajouter/Retirer), quantité + commentaire, aperçu « avant → après » **bloqué si cible négative** (jamais de faux succès), CTA violet « Valider le mouvement de stock ».
- Écarts maquette↔logique RÉELLE **signalés, jamais tranchés en silence** :
  1. **Caméra « réception par photo de facture (OCR) »** : la maquette simule un scan (1,5 s) puis pré-remplit 3 lignes FAUSSES codées en dur ; aucun moteur OCR dans le projet → tuile mappée sur la route RÉELLE `/purchases` (chemin authentique d'une réception facture). Non fabriqué.
  2. **Politique Commerciale** (prix fixe/négociable/free/on_order) : aucun champ `Product` → NON FABRIQUÉE, absente de la fiche.
  3. **Conditionnement** (`unite/carton/paquet`, `unitsPerPack`) : aucun champ persisté → le convertisseur de la fiche est un **calculateur temporaire** (alimente le stock visé, rien n'est enregistré) ; note affichée dans l'UI.
  4. **Brouillons catalogue** (`catalogueStatus==='draft'`) : pas de tel statut → mappé sur produits actifs suivis **sans prix de vente** (`salePrice ≤ 0`), réellement invendables tels quels ; la saisie du prix dans la fiche « publie » réellement la fiche.
  5. **IA « Stock Vivant Prédictif »** : texte prédictif fictif dans la maquette → carte nourrie aux SEULS comptes réels (ruptures/bas) + question ancrée posée à Lynk (service déjà en production).
  6. **Jauge assisté** : la maquette n'a pas de cible de stock dans son modèle → échelle visuelle 0→3×seuil de réappro (convention documentée en code, pas une donnée).
  7. Émojis des motifs maquette (📥📤↩️🚚💔☕⚖️) → icônes Material équivalentes (règle projet : pas d'émojis dans l'UI).
- Données : 100 % Drift réels ; `autoDispose` + `ref.invalidate` après chaque écriture (jamais de stock périmé à l'écran) ; échec partiel d'apply en lot = quantités laissées staged + toast « n sur m » (pas de demi-succès silencieux).
- HIG : permissions réelles vérifiées AVANT action (`stockAdjust` masque la barre d'apply et bloque l'ajustement fiche avec toast explicite ; `productsManage` conditionne la tuile catalogue) ; cibles ≥ 44 pt ; feedback haptique ; confirmation avant toute écriture (motif obligatoire partout) ; rien n'est persisté sans action explicite.
- Régression : `test/widget/davex_stock_test.dart` (seed Drift réel → staged appliqué avec motif → `stockQty` 3→6 + mouvement `adjustment` en base ; assisté → mouvement typé Entrée → 10→20 + `type='purchase'`) **2/2 ✓**. Bugs trouvés par le test : viewport de test 800×600 → CTA sous la flottaison = `ensureVisible` nécessaire ; `MockUser.id` non stubbé → erreur MissingStubError bien remontée dans le toast de catch (comportement production correct : l'erreur est visible, jamais silencieuse).

## 11d. Checklist composant d'écran — Onboarding + modales (a11, livré)

**Splash (`lib/features/onboarding/davex_splash_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `splash_screen.dart` (SplashScreen) resté sur disque, **déréférencé du router** (`/splash` → `DavexSplashScreen`). Aucune fusion.
- Logique RÉUTILISÉE TELLE QUELLE : séquence `_boot()` identique (probe SQLCipher `SELECT 1`, `sync.start` jamais bloquant, `session.bootstrap()` → redirect GoRouter, analytics `app.opened` + snapshot, sauvegarde auto si commerce non-démo), erreur + retry via `userFacingErrorMessage`. Aucune animation `flutter_animate` sur le splash (démontage pendant le redirect = arbre cassé — règle déjà documentée).
- Mapping maquette : dégradé slate-900→indigo-950, halos radiaux (substitut des `blur-3xl`, pas de BackdropFilter), carte logo blanche 112 px + glow indigo, pill « Compagnon de Commerce™ », badge vert « 100 % fonctionnel hors ligne & Cloud Sync » (affirmation VRAIE), « Touchez l'écran pour démarrer ».
- Écarts documentés : le timer cosmétique 1,6 s de la maquette NON repris (le touch n'agit qu'UNE FOIS le boot terminé — jamais un saut avant lecture de session) ; status bar iOS dessinée (9:41/wifi/batterie) = chrome du frame web, non reproduite. Sélecteur de langue FR/EN conservé (réel).

**Onboarding (`lib/features/onboarding/davex_onboarding_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `onboarding_shell.dart` (OnboardingShell) resté sur disque (encore testé par `premium_entry_visual_test`), **déréférencé du router** (`/onboarding` → `DavexOnboardingScreen`).
- Logique RÉUTILISÉE TELLE QUELLE (contrat de création réel) : `ActivationPolicy.requireAgentActivationCode` + `listenManual(runtimeConfigProvider)` (la config serveur arrive après le 1er frame → rebuild), validation code via `CloudRegistrationService.validateCode` (normalisation KMB-XXXXXXXX, plan + expiration), `BusinessCreationInput` complet via `businessServiceProvider` (mot de passe ≥ 8 + PIN 4 chiffres : **indispensables à la dérivation de clé SQLCipher et au lock screen**), mode démo (+ `demoSeeder`), restaurations sync post-création, `session.refresh()` → redirect, entrées `/join` et `/restore`, validations et erreurs à l'identique.
- Mapping maquette : fond slate-50, en-tête = bouton retour carré blanc bordé + pill « Étape X sur Y » indigo, champs en cartes blanches rounded-2xl (icône leading indigo, label 12 px bold + astérisque rose, focus bordure indigo), CTA dégradé #4F46E5→#9333EA glow + flèche (opacité réduite si désactivé), bannières indigo/émeraude/rose, grille secteurs 3 colonnes cartes bordées 2 px avec `AnimatedScale 1.02`.
- Écarts documentés (jamais tranchés en silence) :
  1. écran « connexion téléphone seul, aucun mot de passe » de la maquette **NON FABRIQUÉ** — la première étape réelle reste le code d'activation (selon politique serveur) puis l'identité ;
  2. « Étape 1 sur 3 » figé → compteur dynamique 3 ou 4 selon politique runtime ;
  3. checklist « Catégories initiales » : **aucun modèle de persistance** d'un choix de catégories dans `BusinessCreationInput` → RECRÉÉE en résumé informatif réel (modules `SectorModules.forSector` en pastilles lecture seule + compteur) — cocher serait un faux succès ;
  4. `CatalogueSelector` (écran 6 maquette) existe déjà en réel (`/products/catalog`) → reste APRÈS l'onboarding, non fusionné dans la wizard ;
  5. 9 secteurs/émojis maquette → 8 secteurs réels + icônes Material ;
  6. labels de champs jusqu'ici codés en dur FR dans l'ancien shell → passés `S.tr` (FR/EN réel).
- **Modales shell** (ExpenseManagementModal / ReportingModal / CashClosureModal / CreditLedgerModal) : décision **non dupliquées en modales** — l'Accueil recréé (a7) route déjà vers les VRAIS écrans complets `/expenses`, `/reports`, `/debts` et embarque une VRAIE clôture caisse (Z) en `showDavexSheet`. Recréer les modales maquette = double source de vérité métier (violation de la directive). Menu sheet + recherche : livrés avec le shell (a6, header [Cart][Bell][Menu] → routes réelles dont `/search`). ClientPwaModal/LoyaltyModal : déjà retirés (§7, pas de données réelles).
- HIG : cibles ≥ 44 pt (`DavexPressable`), Semantics sur pill d'étape + boutons, feedback d'erreur jamais silencieux (messages `userFacingErrorMessage`, validation avant toute écriture), aucun état simulé (le CTA « Vérifier le code » n'est désactivé que par `_loading`, jamais par cosmétique).
- Régression : `test/widget/davex_onboarding_test.dart` (parcours complet sans code agent : accueil → identité avec garde champs requis → grille 8 secteurs + modules réels → sécurité avec validation mot de passe ≥ 8 ; **2/2 ✓**) ; `onboarding_no_activation_key_test.dart` basculé sur le nouvel écran (**2/2 ✓**) ; `session_nav_smoke_test` (router avec `/onboarding` recréé) ✓. Suite widget complète : seuls les échecs **préexistants** (google_fonts ×2, « Beignet fourré », premium visual) — aucune régression.

## 11e. Checklist composant d'écran — Assistant (a10, livré)

**Écran Assistant (`lib/features/ai_assistant/davex_assistant_screen.dart`)**
- Décision : RECRÉER — nouveau fichier entier ; `ai_assistant_screen.dart` (AiAssistantScreen) conservé sur disque, **déréférencé du router** (`/ai` → `_gate(aiUse, DavexAssistantScreen())`). Aucune fusion.
- Logique RÉUTILISÉE TELLE QUELLE (cœur hybride réellement en production) : `LynkGroundedAnswers.tryAnswer` (CA, dettes, stock, bénéfice calculés localement, hors ligne, déterministe, quelques millisecondes), `LynkBrainService.ask` (LLM hébergé, historique borné 6 tours), nettoyage des balises de raisonnement (`<think>`) et réponses « menu de capacités » sans chiffres (`_trimCapabilityMenu`), repli local si cloud échoue, honnêteté source ('local' / nom modèle), welcome message (prénom réel via `BusinessAiContextBuilder.firstNameOf`), `pendingAiPromptProvider` (conso fiche rapide/Accueil/Stock), analytics `ai.used`, `_showAbout` (confidentialité).
- Mapping maquette→réel unité par unité (tokens CSS `.lk-assistant-*` PRIMANT sur les classes Tailwind bleues du JSX) : bandeau dette dégradé navy 108° + bordure orange 32 % + label #FFD58C + action #FF9800 (données réelles `CustomerService.debtors` → somme balance > 0) ; bulles utilisateur #1D6BFF angle haut-droit coupé ; bulles IA surface+bordure+shadowCard angle haut-gauche coupé ; avatar bot dégradé #1D6BFF→#5446C7 28px rounded-xl ; frappe 3 points rebondissants 900ms (reduce-motion aware) ; barre saisie surface+ bordure sup, champ rounded-16 min-h 48, envoi orange #FF9800 glow rounded-16 48×48 ; étiquettes source (local = success/cloud = action) ; gras markdown `**…**` ; horodatage réel (locale, pas figée).
- Écarts maquette↔réel documentés (jamais tranchés en silence) :
  1. `aiReply` de la maquette = FAUX BOT codé en dur (47 300 FCFA, stock Sucre, top produits inventés) → NON REPRIS ; l'écran affiche UNIQUEMENT les vraies réponses ancrées + LLM ;
  2. 4 modales « Carnet de Dette » (liste, détail, remboursement, WhatsApp) → NON DUPLIQUÉES ; `/debts` (DebtsScreen Drift réel) = source de vérité unique ; le bandeau route `/debts` ; rappel WhatsApp existe déjà ;
  3. bouton micro (dictée) : `speech_to_text` absent du projet → NON FABRIQUÉ, retiré ;
  4. `AiAurora` (décor violet de l'ancien écran) → RETIRÉ (absent des tokens CSS `.lk-assistant-*` de la maquette).
- HIG : cibles ≥ 48 pt (champ saisie + envoi), `_TypingDots` statique si reduce-motion, `_scrollToEnd` = `Curves.easeOut` 180 ms (jamais brutal), message d'erreur jamais silencieux (`_friendlyError` remonte LynkBrainReject/Offline + SocketException/TimeoutExplicite), analytics opt-out respecté.
- Régression : `test/widget/davex_assistant_test.dart` (seed Drift réel → rendu accueil + bannière dette 47 300 + chips + TextField → tap chip CA → réponse ancrée locale source 'local' visible ; **2/2 ✓**).

## 12. Écarts connus restants
- `lynkstor_header.dart` actuel : actions [Search/Bell/Menu] vs maquette [Cart/Bell/Menu] → corrigé par RECRÉER (étape 2).
- Suite de tests rejouée après Accueil : **+200 ✓, 1 ~, 5 échecs** — ce sont exactement les 5 échecs **préexistants** (§ google_fonts `allowRuntimeFetching=false`, finder « too many », migration drift) ; **aucune régression** imputable à la bascule Accueil/shell.

## 13. Revue finale de bout en bout (a12, livré)

Les 4 écrans d'onglets + onboarding sont désormais recréés et branchés sur le
router ; l'ancien code reste sur disque (fixtures de tests) mais n'est plus
référencé. Chaîne de validation appliquée à chaque livraison puis au global :

- `flutter analyze` : **No issues found** (projet entier).
- `flutter test` : **+209 ✓, 1 ~, 5 échecs** — les 5 échecs sont exactement les
  échecs **préexistants** (google_fonts ×2 + cascade snapshot dark, finder
  « Beignet fourré » too many, golden premium) ; **+2 = les 2 tests assistant**
  newly added ; **aucune régression**.
- `flutter clean` + `flutter build apk --release` : **41,6 Mo**,
  SHA-256 `1ADECF898CFC8163CD0A1E02C7CE24D25B83FBDDE5D5EE1244D3178A23D44562`
  (distinct du build Accueil `AC418822…D6865` → rebuild réellement différent).
- `adb install -r` sur l'Infinix (série 149185558D018471) : **Success**.
- Capture on-device de l'Assistant recréé : en-tête navy [Cart/Bell/Menu],
  bannière « Mode hors ligne · 2 en attente » (compteur sync RÉEL), bandeau
  « Carnet de Dette Client · 53 000 FCFA en cours · 3 comptes » (données Drift
  RÉELLES) + « Ouvrir », statut hybride honnête (« calcul local hors ligne ·
  Llama 3.2-3B · cloud »), chips suggestions, bulle d'accueil avec prénom réel
  (« Bonjour Marie… ») + avatar bot dégradé + horodatage réel.
- Vérification fonctionnelle du cœur IA sur l'appareil : saisie « vente
  aujourd'hui » → envoi → **réponse ancrée locale** « Aujourd'hui : 0 vente(s),
  CA 0 FCFA, encaissé 0 FCFA, crédit 0 FCFA… » étiquetée « Calcul local · hors
  ligne » (vert). Chiffres RÉELS (journée sans vente), jamais inventés.
- Arborescence d'accessibilité (uiautomator) : labels sémantiques présents sur
  toutes les actions (« Ouvrir le carnet de dette », « Fonctionnement et
  confidentialité », « Envoyer », chips, 4 onglets) → conformes HIG VoiceOver.

Note technique relevée pendant la capture : le `TextField` de saisie est
multi-lignes (`maxLines: 4`) → la touche Entrée du clavier insère un retour
chariot au lieu de soumettre ; la soumission se fait par le bouton « Envoyer »
(comportement voulu, identique à un chat). Les cibles tactiles device vérifiées
≥ 48 px (bouton envoi 84×84 px ≈ 48 pt @280 dpi).

## 14. Vague « niveau senior » — chrome global, contrastes, iOS (2026-09-29)

Demande explicite : rendu équipe de design senior, suppression de la section
d'état de connexion au profit d'une icône header, élévation UI/UX vers les
normes iOS. Priorité appliquée : **HIG + WCAG > maquette** sur les points de
contraste (la maquette imposait du blanc-sur-orange que le design system avait
déjà proscrit via `onAction`).

### 14.1 État de connexion : bannière → icône (RECRÉER, RÉUTILISER logique)
- **Retiré** : `KumbaOfflineBanner` pleine largeur sous le header
  (`davex_shell.dart`, import `kumba_states` nettoyé). La bannière reste
  disponible pour `shell_scaffold.dart` (legacy hors DAVEX, non touché).
- **Ajouté** : `_ConnectionStatusAction` dans `DavexAppHeader` — glyphe *cloud*
  sans fond (ne rivalise pas avec Panier/Cloche/Menu), teinte = état
  (`cloud_done` calme / `cloud_upload` ambre + pastille = file d'attente /
  `cloud_off` hors ligne), pastille chiffrée `onAction` sur orange. Cible
  44×44 pt via `DavexPressable`, `semanticLabel` complet (jamais couleur seule).
- Tap → `showDavexSheet` « Synchronisation » : deux lignes RÉELLES (connectivité
  + volume en attente), aucune action inventée (offline-first).
- Params header ajoutés avec défauts (`online`/`pendingSync`/`onStatusTap`) →
  autres call-sites non impactés.

### 14.2 Contraste / typo / motion
- Assistant : « Ouvrir » et icône d'envoi **blanc-sur-orange (2,16:1) → encre
  #3A2500 (6,7:1)** ; halos orange atténués (alpha/blur). Glow du blob header
  réduit `0x38/50/18 → 0x1F/34/12` (restraint iOS).
- Plancher typo assistant : eyebrow 9,5→10,5 px, horodatage 10→11 px.
- **Arbitrage documenté (non résolu en silence)** : les badges uppercase
  9,5/10 px du Stock RESTENT — ils vivent dans des pills `maxLines:1` à largeur
  contrainte ; les gonfler troncagerait le libellé (pis que le gain).
- `reduce-motion` : garde ajoutée au spinner `DavexLoading` (`.repeat()` coupé
  si animations réduites, arc statique).

### 14.3 Validation + capture on-device (Infinix 149185558D018471)
- `flutter analyze` : **No issues found**.
- Tests widgets DAVEX (assistant/stock/vente/accueil/design-system) : **16/16 ✓**.
  Les 4 échecs du run complet = **préexistants** (google_fonts/Inter non bundlé
  en test ×2 + 2 goldens), vérifiés à la racine, sans lien.
- `flutter build apk --release` : 41,6 Mo,
  SHA-256 `CA78C889162CF1A0DF1118EC54CBCC8C1067B81D81A5A2D6979C767C6B05B9A4`
  (distinct du build assistant `1ADECF89…4562`). `adb install -r` : **Success**.
- Captures on-device : Accueil + Vente + Assistant → **bannière hors-ligne
  absente**, **icône cloud barré visible dans le header**, « Ouvrir » et
  « Ajouter » en **encre foncée sur orange lisibles**, glow atténué.
- Constat mineur restant (non bloquant) : emoji 💡 utilisé comme icône dans le
  cartouche d'aide du graphique Accueil → à remplacer par une icône Material
  dans la prochaine vague.

### 14.4 Prochaine vague recommandée
- Onboarding rendu *theme-aware* (encore figé clair → aveuglant en mode sombre).
- Haptique harmonisée sur Accueil/Onboarding (vente/stock/assistant déjà couverts).
- Passe de rythme 4·8 pt + optical sizing sur Accueil/Vente ; retrait des
  derniers emojis-icônes.
