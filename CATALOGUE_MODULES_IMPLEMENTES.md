# Catalogue fonctionnel de Lynkstor Business

Ce document décrit les modules réellement accessibles dans l’application après
l’adaptation du catalogue Lynkstore.

## 1. Tableau de bord

- Synthèse du chiffre d’affaires, des encaissements, dépenses et dettes.
- Indicateurs de stock faible et accès rapide à la caisse.
- Aperçu journalier et accès aux rapports.
- Affichage adapté aux droits de l’utilisateur et aux modules du secteur.

## 2. Caisse et ventes

- Recherche et sélection de produits, services et codes-barres.
- Panier, quantités et contrôle du stock disponible.
- Vente d’un article qui n’existe pas encore dans le catalogue.
- Configuration facultative de cet article après la vente, sans modifier
  rétroactivement le stock.
- Paiements en espèces, crédit client, MTN MoMo et Orange Money.
- Reçu, copie, partage, PDF et impression thermique ESC/POS.
- Retours et annulations audités, remboursement ou avoir, remise en stock
  facultative.

## 3. Produits et stock

- Création et modification d’un produit ou d’un service.
- Photo par caméra ou galerie, conservée localement.
- Prix de vente, prix d’achat, quantité, unité, code-barres et seuil critique.
- Distinction produit suivi en stock / service sans stock.
- Ajustements et historique des mouvements.
- Détection automatique du stock faible ou épuisé.

## 4. Inventaire

- Sessions de comptage physique.
- Saisie des quantités réellement constatées.
- Calcul des écarts.
- Validation et ajustement du stock avec traçabilité.

## 5. Clients

- Fiche client, téléphone, adresse/quartier et solde.
- Historique des mouvements de dette et paiements.
- Encaissement en espèces ou Mobile Money.

## 6. Dettes

- Liste des clients débiteurs et total restant.
- Encaissement partiel ou total.
- Blocage du surpaiement et mise à jour du solde client.
- Prise en compte des ventes à crédit et des retours.

## 7. Dépenses

- Catégories de dépenses.
- Saisie du montant, du motif et de la date.
- Consultation selon les permissions.
- Intégration dans les rapports de résultat.

## 8. Fournisseurs

- Annuaire fournisseur avec coordonnées.
- Association d’un fournisseur principal à un produit.
- Quantité de réapprovisionnement suggérée par produit.
- Utilisation de cette relation par les alertes de stock.

## 9. Achats et réapprovisionnement

- Sélection du fournisseur et des articles.
- Réception d’un achat.
- Mise à jour automatique du stock.
- Réévaluation des alertes après réapprovisionnement.

## 10. Devis et suivi de commande

- Création d’un devis client avec produits ou services.
- Quantités, prix et total.
- Le cycle de commande est actuellement porté par le devis, puis la facture et
  la livraison ; il n’existe pas encore d’écran « Commandes » indépendant.

## 11. Factures

- Création d’une facture depuis une vente.
- Lignes, total, référence et historique.
- Liaison avec le client et le flux de livraison.

## 12. Livraisons

- Liste et suivi des livraisons.
- États de progression : à préparer, en route, livré.
- Accès rapide à l’appel du client.

## 13. Employés et rôles

- Création et consultation des employés.
- Rôles et permissions par fonction.
- Invitation locale par code à usage unique.
- Verrouillage de session par PIN et biométrie facultative.

## 14. Pointage

- Enregistrement de l’arrivée et du départ.
- Historique des présences.
- Disponible pour la quincaillerie, le grossiste, l’imprimerie et les autres
  secteurs employant du personnel.

## 15. Rapports

- Synthèse journalière des ventes, encaissements et dépenses.
- Marge et répartition des résultats.
- Indicateurs issus des données locales.

## 16. Sauvegarde et restauration

- Sauvegarde locale chiffrée.
- Export de transfert vers un autre téléphone.
- Contrôle d’intégrité avant restauration.
- Les notifications, règles d’automatisation et relations
  fournisseur-produit sont incluses dans la sauvegarde.

## 17. Assistant IA local

- Modèle conversationnel Qwen3-0.6B Q4_K_M au format GGUF.
- Téléchargement unique depuis Hugging Face avec vérification SHA-256.
- Inférence locale Android via llama.cpp, avec CPU et Vulkan si disponible.
- Contexte construit depuis les ventes, stocks et dettes du commerce.
- Fonctionnement hors ligne après installation du modèle.
- Lecture seule : l’assistant ne modifie pas les données de gestion.

## 18. Centre de notifications

- Compteur de messages non lus dans l’interface.
- Filtres : tout, non lu, stock, catalogue et système.
- Marquage lu, tout marquer lu, archivage et suppression des messages lus.
- Actions profondes vers la fiche produit, le fournisseur ou le brouillon.

## 19. Automatisations

- Règle par défaut de seuil critique propre à chaque produit.
- Déduplication des alertes pendant 24 heures.
- Fermeture automatique de l’alerte après réapprovisionnement.
- Création d’une alerte lorsqu’un article libre doit encore être configuré.
- Préparation d’un message fournisseur avec produit, stock et quantité suggérée.
- Amélioration facultative du brouillon par l’IA locale.
- Ouverture de SMS ou WhatsApp avec message prérempli ; l’utilisateur confirme
  lui-même l’envoi.

## 20. Paramètres, sécurité et synchronisation

- Choix Français / English appliqué aux écrans et aux reçus.
- Mode performance.
- PIN, biométrie et contrôle d’accès par rôles.
- État de l’abonnement et de la synchronisation cloud.
- Architecture offline-first : les opérations essentielles restent locales.

## Profils sectoriels corrigés

- **Quincaillerie** : caisse, stock, clients, dettes, dépenses, fournisseurs,
  achats, devis, factures, livraisons, employés, pointage, rapports,
  sauvegardes et IA.
- **Grossiste** : ajout garanti de la caisse, des employés et du pointage.
- **Imprimerie** : ajout garanti de la caisse, des employés et du pointage.
- Les commerces existants sont réparés sans retirer leurs modules déjà choisis.

