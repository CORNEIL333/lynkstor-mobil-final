# KUMBA Business — Architecture technique

## État initial
Projet Flutter 3.35 / Dart 3.9 créé from scratch selon le Master Prompt.

## Stack
- **UI** : Flutter Material 3, design system custom (pas de template générique)
- **État** : Riverpod
- **Navigation** : go_router
- **Base locale** : Drift (SQLite) — offline-first
- **Sécurité** : flutter_secure_storage, SHA-256 (PIN/mot de passe), AES sauvegardes
- **Sync** : file d’attente locale (SyncQueue) + états ; backend optionnel

## Couches
```
Présentation (screens/widgets)
  → Services / cas d’usage
    → AppDatabase (Drift)
      → SQLite local
```

Les règles métier (stock, dettes, ventes) ne sont **pas** dans les widgets.

## Modules livrés
| Module | Persistance | Offline | Audit |
|--------|-------------|---------|-------|
| Onboarding / création commerce | Oui | Oui | Oui |
| Auth PIN | Secure storage | Oui | — |
| Dashboard KPI | Agrégats SQL | Oui | — |
| Ventes + paiements | Transaction atomique | Oui | Oui |
| Stock + mouvements | Obligatoire | Oui | Oui |
| Inventaire | Oui | Oui | Ajustements tracés |
| Clients + dettes | Mouvements only | Oui | Oui |
| Dépenses | Oui | Oui | Oui |
| Fournisseurs / achats | Oui (réception → stock) | Oui | — |
| Devis / factures | Oui | Oui | — |
| Livraisons | Oui | Oui | — |
| Employés / pointage | Oui | Oui | — |
| Rapports | Calculs déterministes | Oui | — |
| Sauvegarde chiffrée | Fichier .kumba + checksum | Oui | Oui |
| Assistant IA local | Lecture seule données | Oui | Pas d’action auto |
| Sync queue | Oui | File d’attente | — |

## Invariants métier
1. Une vente validée est écrite en transaction **avant** l’UI de succès.
2. Une dette ne change que via `DebtMovements`.
3. Un stock ne change que via `StockMovements`.
4. Une sauvegarde « succès » implique fichier existant + checksum.
5. Mobile Money : référence saisie manuellement — **jamais** de PIN opérateur demandé.

## Structure `lib/`
Voir Master Prompt §42 — respectée.

## Performance
- Mode performance (settings) : flou/nav bar allégés
- Listes paginées (limite ventes 100 par défaut)
- Base en background isolate (NativeDatabase.createInBackground)
