# Offline-first

## Principe
Toute opération métier validée est écrite en **transaction SQLite locale** avant confirmation UI.

## Fonctionne hors ligne
- Création commerce
- Ventes + reçus
- Produits / stock / inventaire
- Clients / dettes
- Dépenses
- Achats (réception)
- Devis / factures locales
- Livraisons / pointage
- Rapports locaux
- Sauvegarde fichier

## File de sync
Table `sync_queue` : UUID, payload, idempotency key, tentatives, statut  
`local | pending | syncing | synced | conflict | error`

Sans endpoint configuré : les opérations restent **pending** (pas de faux « synchronisé »).

## UX
Bannière hors ligne + compteur d’opérations en attente.
