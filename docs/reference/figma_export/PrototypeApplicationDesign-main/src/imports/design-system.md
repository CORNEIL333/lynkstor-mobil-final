# DAVEX Business Suite™ — Dossier UX/UI MVP v2.0

## 0. Positionnement produit

DAVEX n'est pas un logiciel de gestion. C'est un **compagnon de commerce** : le commerçant l'ouvre pour travailler, pas pour gérer. La gestion se produit en arrière-plan, comme effet secondaire de l'usage, jamais comme activité en soi.

Conséquence directe sur chaque décision de design ci-dessous : si un écran demande au commerçant de *penser à la gestion* plutôt que de simplement *continuer à vendre*, l'écran est mal conçu.

---

## 1. Architecture de l'information

### 1.1 Navigation principale (4 onglets)

```
🏠 Accueil   💰 Vente   📦 Stock   🤖 Assistant
```

- **Vente est l'écran de lancement de l'app**, pas Accueil. Accueil existe comme onglet séparé pour le rapide coup d'œil "comment va mon commerce", mais n'est jamais la première chose vue au démarrage.
- Aucun cinquième onglet, jamais. Toute nouvelle fonctionnalité s'intègre dans l'un des quatre espaces ou devient une capacité de l'Assistant.

### 1.2 Arborescence complète

```
Vente (écran de lancement)
 ├─ Recherche / scan / grille produits fréquents
 ├─ Panier en cours
 ├─ Encaissement (espèces / mobile money / mixte)
 └─ Ticket (partage, impression, aucun)

Accueil
 ├─ Résumé du jour (CA, ventes, alertes) — lecture ≤ 15s
 ├─ Alertes prioritaires (rupture, marge, anomalie)
 └─ Raccourci vers Rapports (accès secondaire, pas un onglet)

Stock
 ├─ Liste produits (recherche, filtre catégorie)
 ├─ Fiche Produit (détail, historique, ajustement)
 ├─ Achats / réception (photo facture → stock mis à jour)
 └─ Alertes de rupture

Assistant
 ├─ Fil de conversation (texte, vocal, photo, scan)
 ├─ Suggestions proactives (pas seulement réactif)
 └─ Point d'entrée unique vers toute fonctionnalité non triviale

Accessible depuis les 4 espaces, jamais en onglet direct :
 ├─ Notifications
 ├─ Paramètres
 ├─ Rapports détaillés
 └─ Création boutique / sélection secteur (onboarding, une seule fois)
```

### 1.3 Règle de placement d'une nouvelle fonctionnalité
Avant d'ajouter un écran ou une option, se demander : *"Cette action sert-elle à vendre, gérer le stock, comprendre la journée, ou est-elle trop rare/complexe pour mériter un chemin dédié ?"* Le quatrième cas va systématiquement dans l'Assistant plutôt que dans un nouveau menu.

---

## 2. User flows critiques

### 2.1 Premier lancement (onboarding)
```
Splash → Connexion (numéro de téléphone, pas d'email obligatoire)
  → Création boutique (nom, ville)
  → Sélection secteur (grille visuelle d'icônes, un tap)
  → Sélection catégories (pré-cochées selon secteur, ajustables)
  → Vente (écran final — boutique déjà fonctionnelle)
```
Cible : moins de 5 minutes, moins de 8 écrans, aucun champ de saisie libre obligatoire hors nom de boutique et numéro de téléphone.

### 2.2 Vente rapide (flow le plus fréquent, doit être le plus court)
```
Vente → tap produit fréquent (ou scan code-barre / recherche)
  → quantité ajustée par + / - (pas de clavier par défaut)
  → Encaisser → choix mode de paiement → confirmation visuelle
  → retour automatique à un panier vide, prêt pour la vente suivante
```
Cible : 3 taps pour une vente d'un article courant, du panier vide à la confirmation.

### 2.3 Réception de marchandise sans saisie
```
Stock → Achats → Photo de la facture fournisseur
  → IA extrait produits, quantités, prix
  → Écran de confirmation (produits pré-remplis, éditables, pas vides)
  → Validation → stock mis à jour, aucune ligne saisie manuellement
```

### 2.4 Interaction Assistant (n'importe quel moment)
```
Tap Assistant (ou action vocale/photo depuis n'importe quel écran)
  → Assistant identifie l'intention (vente, stock, question, rapport)
  → exécute ou pose une seule question de clarification si nécessaire
  → confirme le résultat en langage naturel, jamais en jargon technique
```
L'utilisateur ne voit jamais "module Ventes" ou "module Stock" — seulement le résultat de ce qu'il a demandé.

### 2.5 Parcours client — catalogue par QR Code (nouveau, hors des 4 onglets commerçant)
Ce parcours ne s'ajoute pas à la navigation du commerçant : c'est une expérience séparée, ouverte par le client sur son propre téléphone, jamais visible comme un cinquième onglet (conforme à la contrainte de navigation, §1.1).

```
Panneau en boutique ("Scannez pour acheter plus vite")
  → Détection automatique : catalogue en ligne (Internet) ou local (Wi-Fi boutique)
  → Catalogue : ajout par tap ou par scan direct du produit en rayon ("+1")
  → Panier → choix du mode :
       ⚡ Scan & Achat — le client a déjà les articles, passe à la caisse
       📋 Précommande — le magasin prépare, le client vient payer
  → Nom (seul champ obligatoire) + numéro (optionnel, avec bascule de consentement explicite)
  → "Commander" → confirmation avec numéro de commande
```

Cible : aucune saisie au-delà du nom ; le "+1" au scan doit être aussi immédiat que le geste physique de prendre le produit en main.

**Côté commerçant**, la commande apparaît comme une **bannière sur l'écran Vente** (pas un nouvel onglet ni une interruption modale) — cohérente avec la deuxième loi DAVEX : l'écran Vente sert à vendre, la commande client s'y intègre comme un panier déjà préparé, pas comme une fonctionnalité à part. Le commerçant touche la bannière, vérifie, et encaisse — le panier client se transforme en panier de caisse normal.

### 2.6 Le consentement au numéro, traité comme un choix réel
Le principe DAVEX ("deviner plutôt que demander") s'arrête volontairement à la frontière du consentement : partager son numéro n'est jamais pré-coché ni présenté comme la voie par défaut. Le bénéfice pour le client (être informé des promotions sur ses produits habituels) est énoncé au moment du choix, pas après — pour que l'acceptation soit informée, pas arrachée par un design orienté.

### 2.7 Vendre un produit qui n'est pas encore en stock
Un commerçant ne doit jamais être bloqué par l'absence d'une fiche produit — la vente prime toujours sur la gestion (§0).
```
Vente → "Produit hors catalogue" → nom + prix → ajouté au panier (marqué "nouveau")
  → Encaisser (comme une vente normale)
  → DAVEX propose : "Ce produit n'existe pas encore en stock, l'ajouter ?"
       → catégorie + quantité initiale → stock créé
       → ou "Plus tard" → la vente reste valide, rien n'est perdu
```
Ce flow transforme une exception (produit manquant) en opportunité d'enrichir le catalogue — cohérent avec le principe "plateforme qui apprend" (vision produit). La proposition arrive **après** la vente, jamais avant : rien ne doit ralentir la transaction elle-même.

### 2.8 Ajuster le panier avant l'encaissement
Chaque ligne du panier caisse dispose de contrôles − / + directement visibles, sans écran séparé — cohérent avec "l'utilisateur clique, il ne remplit pas de formulaire" (règles absolues, brief initial).
- Réduire la quantité à zéro ne supprime pas la ligne immédiatement : elle est repoussée en fin de panier et grisée, pour permettre un changement d'avis en un tap sans tout ressaisir.
- À la validation de la vente, les lignes restées à zéro sont retirées silencieusement — le commerçant n'a rien à nettoyer manuellement.

### 2.9 Ajouter un produit au stock manuellement, avec conditionnement
Depuis Stock, un commerçant peut créer une fiche produit sans passer par un achat scanné (cas d'un premier remplissage de stock, ou d'un produit reçu autrement qu'en facture photographiée).
```
Stock → "Ajouter un produit manuellement"
  → nom, catégorie, prix, quantité initiale
  → conditionnement : à l'unité / carton / paquet (+ nombre d'unités si carton ou paquet)
  → produit visible immédiatement dans la liste de stock, avec son conditionnement affiché
```
Le conditionnement est un sélecteur à trois options visuelles, jamais un champ texte libre — cohérent avec "l'utilisateur clique, il ne lit pas".

---

## 3. Design system

### 3.1 Principes visuels
- **Flat, chaleureux, jamais froid** : DAVEX doit paraître humain, pas institutionnel. Éviter l'esthétique "logiciel bancaire".
- **Contraste fort, texte large** : usage en boutique, souvent en plein soleil, parfois d'une seule main.
- **Une action évidente par écran** : toujours un bouton principal visuellement dominant, jamais deux boutons de même poids visuel en concurrence.

### 3.2 Couleurs (à valider avec identité de marque DAVEX)
| Rôle | Usage |
|---|---|
| Couleur primaire (accent chaud) | Boutons d'action principale (Encaisser, Valider, Envoyer) |
| Neutre foncé | Texte principal |
| Neutre clair / blanc cassé | Fonds de carte |
| Vert sémantique | Confirmation, stock sain |
| Ambre sémantique | Alerte (marge en baisse, stock bas) |
| Rouge sémantique | Rupture, erreur, anomalie — usage rare, jamais décoratif |

Règle : la couleur d'alerte n'apparaît que lorsqu'une action est réellement recommandée — pas de rouge "au cas où".

### 3.3 Typographie
- Une seule famille, sans-serif, haute lisibilité à petite taille (marché de téléphones d'entrée de gamme, écrans parfois de faible densité).
- Deux graisses seulement (régulière, medium) — jamais plus, pour rester rapide à rendre et lisible.
- Taille minimale de texte : jamais en dessous du seuil de lisibilité debout, à bout de bras.

### 3.4 Composants clés
- **Bouton d'action principale** : pleine largeur, hauteur généreuse (cible tactile large, usage à une main), toujours en bas d'écran pour les flows de vente.
- **Carte produit** : image ou icône, nom, prix — jamais plus de 3 informations visibles sans interaction.
- **Champ de saisie** : évité par défaut ; quand indispensable, toujours pré-rempli par suggestion si une donnée peut être devinée (première loi DAVEX).
- **Chip de suggestion** (Assistant) : réponses rapides pré-formulées, pour répondre sans clavier.
- **Icône de synchronisation** : discrète en permanence dans l'en-tête, jamais un écran ou une alerte intrusive tant que le fonctionnement n'est pas bloqué.
- **Contrôle de quantité (− / +)** : toujours inline dans la ligne concernée, jamais un écran ou une boîte de dialogue séparée pour un simple ajustement.
- **Sélecteur à options visuelles** (mode de commande, conditionnement) : 2 à 3 choix maximum affichés côte à côte, jamais un menu déroulant pour un choix aussi fréquent.

### 3.5 Iconographie
Style trait (outline), reconnaissable sans lecture — le commerçant scanne, il ne lit pas. Chaque action critique (vendre, scanner, parler, photographier) a une icône dédiée et cohérente sur tous les écrans.

---

## 4. Écrans détaillés

| Écran | Rôle unique | Ne doit jamais contenir |
|---|---|---|
| Splash | Chargement, identité de marque | Toute action |
| Connexion | Authentification minimale (téléphone) | Formulaire long |
| Création boutique | Nom + ville | Paramètres avancés |
| Sélection secteur | Un tap = profil métier chargé | Explications longues |
| Sélection catégories | Ajuster les pré-cochés | Liste exhaustive à parcourir manuellement |
| Accueil | Répondre à "comment va mon commerce" en 15s | Actions de vente ou de stock détaillées |
| Vente | Vendre, uniquement vendre | Statistiques, paramètres |
| Produit (fiche) | Voir/ajuster un produit précis | Actions de vente en masse |
| Stock | Vue d'ensemble des quantités | Écrans de vente |
| Achats | Réceptionner de la marchandise | Analyse de rentabilité |
| Assistant IA | Point d'entrée universel | Rien n'est hors sujet ici — c'est le seul écran "ouvert" |
| Rapports | Approfondir au-delà des 15s d'Accueil | Actions transactionnelles |
| Notifications | Liste des alertes passées | Configuration |
| Paramètres | Réglages du compte/boutique | Toute donnée métier (ventes, stock) |
| **Catalogue client** (côté client, pas commerçant) | Parcourir, ajouter par scan, valider un panier | Toute fonctionnalité de gestion — le client ne voit jamais l'envers du décor DAVEX |
| **Commande reçue** (côté caisse) | Vérifier une commande client avant encaissement | Édition libre des lignes — seulement valider ou rejeter |
| **Produit hors catalogue** | Vendre un article absent du stock | Gestion de catégorie ou de conditionnement — reporté à l'étape suivante |
| **Initialisation stock** | Proposer d'ajouter au stock un produit vendu hors catalogue | Blocage de la vente — cet écran apparaît toujours après, jamais avant l'encaissement |
| **Nouveau produit (manuel)** | Créer une fiche produit avec conditionnement | Achat/réception de facture — ça reste le rôle de l'écran Achats |

---

## 5. États du système

### 5.1 États vides
Jamais un écran vide sans proposition d'action (troisième loi DAVEX).
- Stock vide → proposition directe : "Ajoutez votre premier produit par photo ou scan."
- Historique de vente vide (nouveau commerce) → message d'encouragement + raccourci vers Vente.
- Aucune alerte sur Accueil → confirmation positive explicite ("Rien à signaler aujourd'hui"), pas un espace blanc silencieux.

### 5.2 États hors ligne
- Indicateur discret et permanent, jamais un bandeau bloquant : le commerçant doit pouvoir continuer sans friction visuelle.
- Toute action réalisée hors ligne reste visible immédiatement dans l'UI (optimistic UI) — la synchronisation réelle se fait en tâche de fond, sans que l'utilisateur ait à y penser.
- Aucune fonctionnalité de vente ou de stock n'est bloquée hors ligne ; seules les fonctions dépendant du cloud (recommandations avancées, consolidation multi-boutiques) affichent un état "disponible à la reconnexion", jamais une erreur.

### 5.3 États de synchronisation
- Trois états visuels seulement, pour rester simple : à jour / en cours / en attente de connexion — pas de jargon technique ("event", "conflit", "delta") exposé à l'utilisateur.
- En cas de conflit résolu automatiquement (règles définies dans l'architecture technique), aucune interruption ; en cas d'anomalie nécessitant vérification humaine, elle apparaît comme une alerte normale sur Accueil, pas comme un message d'erreur système.

---

## 6. Animations et micro-interactions

- **Confirmation de vente** : animation courte et satisfaisante (check visuel, retour haptique léger) — renforce la sensation de maîtrise après chaque transaction.
- **Transition Vente → panier vide** : fluide, immédiate, sans écran de chargement perceptible.
- **Assistant en écoute (vocal)** : indicateur visuel simple et rassurant (onde ou pulsation), qui disparaît dès la fin de la capture.
- **Alerte apparaissant sur Accueil** : légère mise en évidence, jamais intrusive au point d'interrompre une tâche en cours.
- Règle générale : toute animation doit raccourcir la perception du temps d'attente, jamais l'allonger artificiellement pour "faire joli".

---

## 7. Prototype interactif — note de faisabilité

Je ne peux pas produire un fichier Figma exécutable directement depuis cette conversation. Deux chemins possibles pour la suite :

1. **Transfert à un designer** : ce document (IA, flows, design system, écrans, états) donne une base suffisamment précise pour un montage Figma en quelques heures plutôt que de partir d'une page blanche.
2. **Prototype cliquable alternatif** : je peux construire un prototype HTML interactif (écrans reliés entre eux, cliquable) directement dans la conversation, comme étape intermédiaire avant Figma — utile pour tester le flow de vente ou d'assistant avec de vrais utilisateurs avant l'investissement design complet.

---

## 8. Documentation UI — notes de handoff

- Toutes les valeurs de couleur, typographie et espacement ci-dessus sont des **rôles**, pas des valeurs figées — à verrouiller avec la charte de marque DAVEX avant implémentation.
- Chaque écran listé en section 4 doit être développé comme **composant isolé**, cohérent avec la deuxième loi DAVEX (une tâche complète par écran) — cela facilite aussi le découpage en tickets de développement.
- Les états vides, hors ligne et de synchronisation (section 5) doivent être livrés **avec** chaque écran dès la première version, pas ajoutés après coup — ce sont eux qui font la différence perçue entre "logiciel" et "compagnon".

---

## 9. Fidélisation client — DAVEX Client (PWA persistante)

Cette section prolonge le parcours client (§2.5) avec la couche de mémoire et de fidélisation définie dans l'architecture technique (§14). Rien de nouveau à installer pour le client : la même PWA se souvient simplement de lui d'une visite à l'autre.

### 9.1 Principe : une mémoire progressive, jamais un compte imposé
- **Palier 1 — reconnaissance anonyme** : dès la deuxième visite (même sans avoir rien partagé), la PWA reconnaît le navigateur et peut afficher les boutiques déjà visitées.
- **Palier 2 — PWA installée** : le client ajoute DAVEX à son écran d'accueil ; son historique devient plus riche et disponible hors ligne.
- **Palier 3 — numéro partagé** : le profil se synchronise sur le cloud, pour ne rien perdre en cas de changement de téléphone.

Ces trois paliers ne sont **jamais présentés comme une progression obligatoire** — un client peut rester au palier 1 indéfiniment sans que rien ne soit dégradé dans son expérience de base (commander reste possible sans jamais s'identifier).

### 9.2 Nouveaux écrans côté client

| Écran | Rôle unique | Accessible depuis |
|---|---|---|
| **Répertoire de mes boutiques** | Retrouver en un tap les commerces déjà visités | Ouverture de la PWA sans nouveau scan, ou lien "Voir mes boutiques" après une commande |
| **Mon historique** | Revoir commandes passées et tickets numériques | Répertoire de mes boutiques |
| **Mes autorisations** | Voir/retirer le consentement donné à chaque boutique, individuellement | Répertoire de mes boutiques |
| **Invitation à installer** | Proposer d'ajouter DAVEX à l'écran d'accueil | Apparaît une seule fois, juste après la première commande confirmée — jamais avant, jamais en interruption d'un parcours en cours |

### 9.3 Le répertoire de boutiques — la première chose qu'un client fidèle revoit
Contrairement au catalogue (toujours celui d'une seule boutique à la fois), le répertoire est **la seule vue transverse** que le client obtient — jamais le commerçant. Chaque boutique y apparaît avec sa dernière visite et, le cas échéant, une promotion active — mais toujours limitée à ce que cette boutique a choisi de montrer à ce client précis (cohérent avec le cloisonnement par tenant de l'architecture, §14.3).

### 9.4 Où et comment apparaissent les promotions
Une promotion n'est jamais poussée de force dans un flow en cours (ex. jamais une interruption pendant la constitution d'un panier). Elle apparaît :
- comme un repère visuel discret sur la ligne de la boutique concernée, dans le répertoire ;
- comme une notification, si la PWA est installée et que le client l'a autorisé ;
- par WhatsApp en repli, pour un client qui n'a pas installé la PWA mais a partagé son numéro.

Le contenu est identique quel que soit le canal — seule la manière dont il atteint le client change (voir architecture §14.6).

### 9.5 Le consentement reste réversible, boutique par boutique
L'écran "Mes autorisations" présente une bascule **par boutique**, jamais une bascule globale — retirer son consentement à une boutique n'affecte ni l'historique ni les autorisations données à une autre. Cohérent avec le principe qu'un commerçant garde la maîtrise de sa propre relation, jamais partagée avec un autre commerçant même via la même plateforme.

### 9.6 Ce qui ne change pas
Toutes les règles déjà posées pour le parcours client restent valables ici : zéro compte obligatoire pour commander (§2.5), consentement énoncé au moment du choix et jamais pré-coché (§2.6), et le catalogue lui-même reste toujours rechargé à neuf à chaque boutique — seule la mémoire du client, elle, persiste.

