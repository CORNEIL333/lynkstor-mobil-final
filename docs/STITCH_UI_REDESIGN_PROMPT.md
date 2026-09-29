# PROMPT MAÎTRE — REFONTE UI/UX PREMIUM LYNKSTOR BUSINESS (GOOGLE STITCH & GEMINI)

> **Instructions d’utilisation** : Copiez-collez l'intégralité du prompt ci-dessous directement dans **Google Stitch**, Gemini ou votre assistant de design & code UI pour générer une refonte visuelle d'exception des interfaces de l'application **Lynkstor Business**.

---

```markdown
# ROLE & MISSION
Tu agis comme un Designer UI/UX Mobile Senior & Ingénieur Lead Flutter/Material 3 expert en applications financières et ERP mobiles africains.

Ton objectif est de réaliser une **refonte visuelle complète, moderne, fluide et spectaculaire ("WOW Effect")** des interfaces de l'application mobile **Lynkstor Business** (ERP mobile offline-first & Caisse POS).

---

# 1. IDENTITÉ VISUELLE & SYSTEME DE DESIGN LYNKSTOR

## Palette de Couleurs Officielles (Tailored Palette)
- **Bleu Roi Principal (Royal Blue)** : `#1A4FA0` (Bannières, cartes majeures, boutons primaires)
- **Bleu Électrique (Vibrant Blue)** : `#2563EB` (Éléments d'action, accents, jauges)
- **Orange Ambre Chaud (Amber Accent)** : `#F59E0B` (Point d'accentuation logo, alertes, forfaits PRO, notifications)
- **Vert Émeraude Succès (Forest Emerald)** : `#10B981` (Encaissements, bénéfices, stock suffisant)
- **Rouge Rose Dette/Alerte (Rose Debt)** : `#F43F5E` (Reste dû, créances clients, rupture de stock)
- **Arrière-plan Mode Sombre (Dark Surface)** : `#0F172A` & `#1E293B`
- **Arrière-plan Mode Clair (Light Surface)** : `#F8FAFC` & `#FFFFFF`

## Typographie & Numériques
- **Police Principale** : Google Font **Inter** ou **Outfit** (Lisibilité maximale)
- **Formataion Monétaire** : `fontFeatures: [FontFeature.tabularFigures()]` pour un alignement parfait des montants en **FCFA**.

## Esthétique & Composants (Modern Aesthetics)
- **Glassmorphism & Profondeur** : Cartes avec bordures subtiles (`rgba(255,255,255,0.08)`), ombres légères et flou de fond.
- **Rondes & Ergonomie Tactile** : Border radius `16px` à `24px`, zones de clics généreuses adaptées au travail sur le terrain et à l'usage à une main.
- **Micro-animations & Fluidité** : Retours haptiques, transitions de vues par glissement, compteurs animés et indicateurs d'état en temps réel (offline/online pulse dot).

---

# 2. REFONTE DES 6 ÉCRANS CLÉS DE L'APPLICATION

## ÉCRAN 1 : ACCUEIL & TABLEAU DE BORD COMMERCIAL (`/home`)
- **En-tête de Marque** : Logo Lynkstor (L géométrique bleu + barres de graphiques + point orange), nom du commerce, badge de rôle (Propriétaire/Gérant) et indicateur vert de mode hors-ligne.
- **Cartes KPI Financières** :
  - Ventes du Jour (Total FCFA + % d'évolution).
  - Encaissements liquides vs Crédits/Dettes du jour.
  - Alerte Stock bas & Nombre d'articles en rupture.
- **Barre d'Action Rapide Caisse** : Gros bouton flottant d'accès direct « Vendre / Encaisser » avec effet dégradé lumineux.
- **Flux des Dernières Ventes** : Cartes compactes interactives avec icône du mode de paiement (Espèces, Orange Money, MTN MoMo, Wave).

## ÉCRAN 2 : CAISSE POS & VENTE FLASH (`/sale/new`)
- **Zone Scanner & Recherche** : Bouton d'activation caméra scanner rapide (`mobile_scanner`) et barre de recherche intelligente multi-critères.
- **Grille Produit Dynamique** : VIGNETTES d'articles avec photo/icône, nom, prix FCFA et indicateur visuel de quantité en stock.
- **Tiroir de Panier Interactif (Cart Drawer)** :
  - Ajustement des quantités instantané (+/-).
  - Calcul automatique du sous-total, remises et monnaie à rendre.
  - Choix du mode de paiement par boutons d'icônes de couleur (Espèces, Mobile Money, Dette Client).

## ÉCRAN 3 : REÇU & TICKET DE CAISSE THERMIQUE (`/sale/receipt/:id`)
- **Aperçu Ticket de Caisse** : Carte style reçu papier réaliste avec découpe ondulée en bas.
- **Détails de Vente** : Numéro de référence, liste des articles, total net et monnaie rendue.
- **Boutons d'Action Rapides** :
  - 🖨️ « Imprimer Ticket (Thermique 58mm/80mm) » (Appel `EscPosPrinterService`).
  - 📱 « Partager WhatsApp / Reçu PDF ».
  - ➕ « Nouvelle Vente ».

## ÉCRAN 4 : CATALOGUE STOCK & FICHE PRODUIT (`/products`)
- **Vue Liste / Grille** : Filtre rapide par catégorie (Épicerie, Pharmacie, Quincaillerie, Boissons).
- **Badges d'État de Stock** : Vert (Disponible), Orange (Stock Faible), Rouge (Rupture).
- **Fiche Produit Moderne** : Prix d'achat vs Prix de vente, marge calculée en %, code-barres et historique de réapprovisionnement.

## ÉCRAN 5 : CARNET DE DETTES & CLIENTS (`/debts`)
- **Résumé du Portefeuille Créances** : Total des dettes à recouvrer en FCFA.
- **Fiche Client / Dette** : Nom du client, photo/initiales, limite de crédit autorisée, historique des remboursements et bouton « Encaisser un Acompte ».

## ÉCRAN 6 : MENU PLUS & PARAMÈTRES (`/more` & `/settings`)
- **Profil & Licence Commerce** : Statut de l'abonnement Lynkstor (PRO / STARTER / ENTERPRISE).
- **Grille des Modules Sectoriels** : Icônes d'accès filtrées selon le rôle RBAC (Ventes, Dépenses, Achats, Devis, Factures, Livraisons, Pointage, Sauvegardes).
- **Contrôles Système** :
  - Sélecteur de Langue (Français 🇫🇷 / English 🇬🇧).
  - Configuration de l'URL du Serveur HTTP de Synchronisation.
  - Interrupteur Mode Performance (Téléphones modestes).
  - Déverrouillage Biométrique & Verrouillage PIN.

---

# 3. DIRECTIVES DE CODE & IMPLÉMENTATION FLUTTER

- Utilise les widgets natifs **Flutter / Material 3** avec `ThemeData` personnalisé intégrant les couleurs Lynkstor.
- Utilise **Riverpod** (`ConsumerWidget` / `ref.watch`) pour la réactivité des états de vente, du panier et du stock.
- Assure une parfaite réactivité sur tous les formats d'écrans Android (téléphones 5", 6.5", et tablettes).
- Garantis 0 avertissement d'analyse (`flutter analyze`) et une gestion propre du mode sombre/clair.
```
