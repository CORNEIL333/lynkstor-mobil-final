# KUMBA — Parcours UX

## Première ouverture
Splash → contrôles DB → choix :
1. Créer mon commerce (wizard 3 étapes)
2. Rejoindre (guidage mode équipe)
3. Restaurer (après création + fichier .kumba)
4. Démonstration (données réalistes)

## Vente (chemin critique)
Accueil / FAB → Nouvelle vente → recherche/scan → panier → Encaisser → moyen de paiement → validation transaction → Reçu → partage / nouvelle vente

États : catalogue vide, stock insuffisant, crédit sans client (bloqué), succès, erreur métier lisible.

## Dette
Clients / Dettes → fiche client → Encaisser → montant + moyen → mouvement dette → nouveau solde

## Inventaire
Stock → Inventaire → démarrer → compter (auto-save ligne) → valider → ajustements stock tracés

## Sauvegarde
Plus → Sauvegardes → créer → fichier chiffré + checksum affiché → partager

## Pointage
Plus → Pointage → Arrivée / Départ (méthode PIN locale, pas de tracking permanent)

## Rôles (permissions)
Voir `lib/core/permissions/permissions.dart` — owner, manager, seller, stockManager, commercial, delivery, accountant.
