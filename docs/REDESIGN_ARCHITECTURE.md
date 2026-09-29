# Architecture & navigation — refonte Lynkstor

Stack : **Flutter 3.9 + Riverpod + go_router + Drift (offline-first)**.  
L’IA locale existe déjà (`llama_flutter_android`, Qwen, `/ai`). La logique métier (ventes, stock, sync) **ne change pas**. On refait UI, UX, navigation, et on hisse l’IA au rang de module de première classe.

---

## 0. Morphologie vs plateforme (décision figée)

**Look = iOS-like / consumer premium** (références Adidas after, furniture, file-transfer, calorie).  
**Moteur = Material 3 Flutter**, fortement dépouillé. **Pas** `CupertinoApp`. **Pas** le M3 stock (NavigationBar, FilledButton 20 px, ripple violet).

| Couche | Choix | Pourquoi |
|--------|--------|----------|
| Visuel | Coins 20–32, pills, glass `BackdropFilter`, ombres océan 2 couches | Les refs ; déjà amorcé dans `KumbaFloatingNavBar` |
| Widgets | `ThemeData(useMaterial3: true)` + composants Kumba | Accessibilité TalkBack, ink sémantique, overlays |
| Gestes | **Contrats Android** | Téléphones cibles = Android |

### Morphologie des 3 familles

**Bottom nav** — dock flottant (pas `NavigationBar` M3)  
- Hauteur 64, radius 32, marge 18 + safe area  
- Verre crème 82 % + blur 28 (0 en mode perf)  
- Indicateur actif : pill ciel derrière l’icône, pas une ligne M3  
- FAB Vendre : disque 64, dégradé océan→ciel, au-dessus du dock  
- Slot 4 = `LynkAvatar` 36 px  

**Boutons** — capsule, pas le M3 20×20  
- Primaire : height 52, radius 999, fill océan, texte crème, **press scale 0.97** (pas de ripple)  
- Secondaire : même forme, fill transparent, stroke ciel 1.2  
- Tertiaire : texte océan, tap 48  
- Loading : le label se morph en spinner 16 px dans le même pill  

**Cards** — îlot, pas `Card` elevation 1  
- Radius 24 (liste) / 28 (KPI) / 32 (hero)  
- Fill `creamCard`, bord 1 px `line` ou highlight crème  
- Ombre : blur 24 offset (0,10) océan 8 % + inset highlight  
- Color-block : fill ciel/ice, texte océan, même radius  

Sheets : radius haut 28, grabber, **suivi du doigt** (Android back ferme aussi).  
Champs : radius 20, fill crème, pas d’underline M3.

### Cohérence Android (si look iOS)

On **n’imite pas** iOS sur les gestes système.

| Comportement | Règle Lynkstor |
|--------------|----------------|
| Bouton / geste Retour | Toujours `Navigator.pop` / `go_router` pop. Aucun hijack « swipe from left = iOS back ». |
| Predictive Back (API 34+) | `PredictiveBackPageTransitionsBuilder` (ou equivalent go_router). L’écran suit le geste Android, pas un slide Cupertino figé. |
| Nav 3 boutons vs geste | `extendBody` + `MediaQuery.padding.bottom`. Dock au-dessus de la barre de geste, jamais dessous. |
| Edge-to-edge | Status bar transparente, icônes sombres sur crème / claires sur océan. |
| Back sur sheet / modal | Retour système = dismiss (comme swipe down). `PopScope` si confirmation destructive. |
| Back sur caisse avec panier | Dialog « Vider / Rester », puis pop. Pas un piège. |
| Haptique | `HapticFeedback` Android (selection / light / medium), pas UIKit. |
| Ripple | Désactivé sur pills/cards (`KumbaPressable`). Conservé **léger** sur lignes de liste pour TalkBack. |
| Zones de tap | **48 dp** (norme Android), pas 44 iOS. |
| TalkBack | Rôles Material (`Semantics button`, labels FR/EN). |
| Reduce motion | Setting Android + flag perf app → fade 180 ms, Lynk statique. |

Transitions de **pages Android** : predictive back (ou shared-axis horizontal 300 ms qui reste interruptible par le geste système).  
`CupertinoPageTransitionsBuilder` **interdit** sur `TargetPlatform.android`.

En une phrase : **ça ressemble à iOS, ça se conduit comme Android.**

---

## 1. Audit de l’existant

### 1.1 Inventaire des écrans (routes)

| Zone | Routes | Accès actuel |
|------|--------|----------------|
| Entrée | `/splash`, `/onboarding`, `/join`, `/restore`, `/lock` | Hors shell |
| Shell (bottom nav) | `/home`, `/sales`, `/stock`, `/more` | 4 onglets + FAB Vendre |
| Caisse | `/sale/new`, `/sale/receipt/:id`, `/sale/return/:id` | Hors shell (plein écran) |
| Catalogue | `/products`, `/products/new`, `/products/:id` | Plus / raccourcis |
| Clients | `/customers`, `/customers/:id` | Plus |
| Ops | `/debts`, `/expenses`, `/suppliers`, `/purchases`, `/inventory` | Plus |
| Docs | `/quotes`, `/invoices`, `/deliveries` | Plus |
| RH | `/employees`, `/attendance` | Plus |
| Système | `/reports`, `/backup`, `/notifications`, `/subscription`, `/settings` | Plus |
| IA | `/ai` | **Plus, en bas de grille** |

Dossiers vides : `features/orders/`, `features/payments/` (la facturation vit dans `/invoices`).

### 1.2 Frictions (taps)

| Action fréquente | Parcours actuel | Taps | Verdict |
|------------------|-----------------|------|---------|
| Nouvelle vente | FAB central | 1 | OK |
| Vérifier un stock | Accueil → Stock, ou Plus → Produits | 1–3 | Moyen : produit vs stock séparés |
| Valider / voir une facture | Plus → Factures → ligne | 3+ | Trop long |
| Consulter un rapport | Accueil raccourci ou Plus | 2–3 | Moyen |
| Poser une question à l’IA | Plus → scroller → IA | **3–5** | Cassé |
| Recherche globale | **N’existe pas** | — | Manque |

Autres constats :
- L’IA n’est **pas** dans la bottom nav. L’orb actuel (`AiOrb`) est un blob, pas un personnage.
- Pas de FAB IA, pas d’overlay contextuel, pas d’historique de conversations, pas de voix.
- Pas de recherche unifiée.
- Dashboard identique pour tous les rôles (seul le menu Plus est filtré).
- `AppRole.seller` **n’a pas** `aiUse`. Commercial / magasinier / livreur / comptable non plus.
- Modules `ia` absents de certains secteurs (`salon`, `ambulant`, `imprimerie`, `grossiste`).
- Hors-ligne : bandeau existant, mais messages Android encore présents sur plusieurs écrans.
- Caisse et listes : search locale, pas de suggestions IA.

### 1.3 Bottom nav actuelle

Accueil · Ventes · **FAB Vendre** · Stock · Plus

Problème : 4 destinations métier, 0 IA. Deux FAB (Vendre + avatar) se marcheraient dessus si on les empile sans règle.

---

## 2. Nouvelle arborescence

```
Entrée
  Splash → Onboarding | Join | Restore | PIN
App (shell)
  Accueil          /home          (KPIs rôle + avatar du jour)
  Ventes           /sales         (liste)
  Caisse           /sale/new      (FAB central, hors tab)
  Assistant        /ai            (plein écran, tab dédié)
  Plus             /more          (modules restants + réglages)
Hors shell (push)
  Recu, retour vente
  Produits, fiche, formulaire
  Clients, fiche
  Dettes, dépenses, fournisseurs, achats, inventaire
  Devis, factures, livraisons
  Employés, pointage
  Rapports, sauvegardes, notifs, abonnement, settings
  Recherche globale   /search     (NOUVEAU)
Overlays
  Bottom sheet chat IA rapide
  Bulle contextuelle (anomalie stock / dette)
```

### Bottom nav (5 touches max)

| Slot | Destination | Pourquoi |
|------|-------------|----------|
| 1 | Accueil | Priorité du jour, rôle |
| 2 | Ventes *ou* Stock *ou* Factures | **Adapté au rôle** (voir 2.1) |
| 3 | FAB **Vendre** | Action n°1 POS — inchangé |
| 4 | **Assistant (avatar)** | Citoyen de 1re classe |
| 5 | Plus | Le reste |

**Pas deux FAB.** L’avatar n’est pas un second bouton rond en bas à droite en permanence (il cacherait la caisse). Il vit :

1. Dans l’onglet 4 (40 px, idle).
2. Dans le header Accueil (64 px, message du jour).
3. En **chip flottant** bas-droite **uniquement hors caisse / scanner / PIN**, déplaçable, masqué sur `/sale/new`.
4. Tap court chip ou onglet → bottom sheet IA. Tap long / swipe up → `/ai` plein écran avec morphing.

### 2.1 Onglet 2 selon le rôle

| Rôle | Onglet 2 | FAB Vendre |
|------|----------|------------|
| owner, manager, seller | Ventes | Oui |
| stockManager | Stock | Non (icône scan catalogue) |
| accountant | Factures | Non |
| commercial | Clients | Oui si `salesCreate` |
| delivery | Livraisons | Non |

### 2.2 Permissions IA

Étendre `aiUse` à : owner, manager, seller, stockManager, commercial, accountant.  
Delivery : non (parcours terrain court).  
Activer le module `ia` pour **tous les secteurs** (aujourd’hui manquant sur salon, ambulant, imprimerie, grossiste).

---

## 3. Parcours critiques cibles

### Créer une commande / vente
FAB → caisse (scan / grille) → encaisser → reçu. **1 tap** pour ouvrir. Inchangé.  
IA : chips « Ajouter le top vendeur » dans le sheet, jamais auto-ajout stock.

### Vérifier un stock
Accueil (KPI stock bas) **ou** onglet Stock (magasinier) **ou** recherche globale. **1 tap**.  
IA : bulle sur ligne « seuil bientôt atteint → Créer un achat ».

### Valider une facture
Comptable : onglet Factures. Autres : Plus → Factures **ou** recherche. Cible **2 taps**.  
IA : résumé « 3 factures en attente » sur le dashboard.

### Consulter un rapport
Accueil KPI → `/reports`. Cible **1–2 taps**.  
IA : carte « résumé du jour » générée, badge Généré par IA.

### Poser une question à l’IA
Onglet Assistant **ou** chip avatar **ou** recherche. Cible **1 tap**.  
Sheet si on reste dans le métier ; plein écran pour une session longue.

---

## 4. Recherche globale `/search`

- Entry : loupe header Accueil / Plus, raccourci clavier tablette.
- Résultats mixtes : produits, clients, ventes, factures, **réponse IA courte** en tête si la requête est une question (« combien de ventes aujourd’hui ? »).
- La réponse IA porte toujours le badge + halo dégradé IA.
- Hors-ligne : recherche locale seulement, chip « IA indisponible hors ligne » si le modèle n’est pas chargé.

---

## 5. Dashboard par rôle

Phrase type : **« Bonjour [Prénom], voici votre priorité du jour. »**

| Rôle | Bloc principal | Secondaire | Avatar |
|------|----------------|------------|--------|
| owner / manager | Ventes + encaissé + bénéfice | Stock bas, dettes | « 3 factures / X dettes » |
| seller | Objectif caisse + dernières ventes | Clients à relancer | « Prêt à encaisser » |
| stockManager | Alertes rupture + valeur stock | Achats à recevoir | « N articles sous seuil » |
| accountant | Encours factures + dépenses | Trésorerie du jour | « Pièces à valider » |
| commercial | Pipeline devis + clients | Livraisons | « Devis en attente » |

---

## 6. États système (hors Android brut)

| État | UI | Motion |
|------|----|--------|
| Hors ligne | Bandeau crème + point océan, « Données locales actives » | Pulse 1.6 s sur le point |
| Sync en cours | Pastille header, compteur pending | Spinner 12 px, pas full-screen |
| Erreur réseau | Toast slide-in, retry | 280 ms ease-out |
| IA réfléchit | Avatar thinking + halo | 400–800 ms loop, figé si reduce-motion |
| IA erreur / modèle absent | Avatar sorry + CTA télécharger | Pas de crash silent |
| Reduce motion | Crossfade only, avatar statique expression-still | — |

---

## 7. Ordre d’implémentation (modules)

1. Tokens + composants de base (couleurs, type, boutons, cards, badge IA)  
2. Avatar `Lynk` (états, tailles)  
3. Shell : nav + chip IA + recherche  
4. Splash / PIN / Onboarding (présentation avatar)  
5. Écran IA plein écran + sheet  
6. Dashboard rôle + message avatar  
7. Caisse / ventes  
8. Stock / produits / inventaire (+ bulles IA)  
9. Clients / dettes  
10. Achats / fournisseurs  
11. Factures / devis / livraisons  
12. Rapports  
13. Notifications (système vs IA)  
14. Paramètres (nom / accent avatar)  
15. Checklist cohérence  

Un module livré = résumé « ce qui a changé / pourquoi », puis pause avant le suivant.
