# Plan d’implémentation — passage de Kumba à un produit « Ready Go »

## 1. Verdict de départ

Le projet ne doit pas être présenté comme prêt pour la production tant que les
portes de validation décrites à la fin de ce document ne sont pas franchies.

Les priorités sont, dans cet ordre :

1. garantir qu’une sauvegarde contient réellement toutes les données utiles ;
2. garantir qu’une restauration recrée un état cohérent et vérifiable ;
3. transformer la synchronisation en réplication bidirectionnelle ;
4. rendre les promesses fonctionnelles conformes à ce qui fonctionne réellement ;
5. valider le tout sur des appareils Android physiques.

## 2. Principes d’architecture

- SQLite reste la base opérationnelle locale : l’application doit fonctionner
  hors ligne.
- Supabase devient la copie canonique distante pour la réplication et la reprise
  après perte d’un appareil.
- Une synchronisation réussie n’est pas considérée comme une sauvegarde.
- Une sauvegarde n’est valide que si une restauration automatisée la vérifie.
- Les ventes, paiements, mouvements de stock et de dette sont des événements
  immuables. Ils ne doivent pas être écrasés par une règle générique
  « dernier arrivé, dernier gagnant ».
- Les secrets `service_role` restent exclusivement dans les Edge Functions.
- Tous les fichiers envoyés dans Supabase Storage sont chiffrés sur le téléphone
  avant l’envoi.

## 3. Phase 0 — Baseline et garde-fous

Durée indicative : 1 à 2 jours.

### Travaux

- Geler un jeu de données de référence réaliste contenant toutes les tables.
- Documenter les parcours critiques :
  activation, vente, crédit, retour, sauvegarde, restauration et changement
  d’appareil.
- Ajouter une commande unique de validation :
  analyse Dart, tests Flutter, tests Edge Functions et tests SQL.
- Ajouter un identifiant de build visible dans Paramètres.
- Créer une matrice « fonctionnalité annoncée / réellement disponible ».

### Critère de sortie

- Une modification ne peut plus être publiée si l’analyse, les tests ou la
  comparaison de schéma échouent.

## 4. Phase 1 — Sauvegarde exhaustive v3

Durée indicative : 4 à 6 jours.

### Données obligatoires

- commerce et configuration métier ;
- utilisateurs, rôles et permissions, sans recopier leurs secrets ;
- catégories, produits et mouvements de stock ;
- sessions et lignes d’inventaire ;
- clients, ventes, lignes, paiements, dettes et retours ;
- dépenses et catégories ;
- fournisseurs, achats et lignes ;
- devis, factures et lignes ;
- livraisons, signatures et preuves ;
- présences ;
- notifications, règles et exécutions d’automatisation ;
- relations produit-fournisseur ;
- pièces jointes et photos.

Les appareils, jetons de session, files de synchronisation et historiques de
sauvegarde sont régénérés et ne doivent pas être restaurés comme des données
métier.

### Travaux

- Supprimer la limite actuelle de 5 000 ventes.
- Construire un registre central des tables sauvegardées.
- Ajouter un test qui échoue automatiquement lorsqu’une nouvelle table Drift
  n’est ni sauvegardée ni explicitement exclue.
- Remplacer le gros JSON en mémoire par un conteneur versionné :
  manifeste, données par table et médias.
- Sérialiser les gros volumes par flux ou par blocs.
- Utiliser un chiffrement authentifié de type AES-256-GCM, ou conserver
  chiffrement + HMAC avec une spécification documentée et testée.
- Conserver dans le manifeste :
  version du format, version du schéma, compteurs par table, empreinte de chaque
  ressource et empreinte globale.
- Ne plus ignorer silencieusement une pièce jointe trop volumineuse : bloquer la
  sauvegarde ou afficher précisément ce qui n’a pas été inclus.
- Ajouter une estimation de taille et un contrôle d’espace libre.

### Tests obligatoires

- sauvegarde et restauration de chaque table ;
- plus de 5 000 ventes ;
- pièces jointes absentes, corrompues et volumineuses ;
- mauvais mot de passe ;
- fichier tronqué ou modifié ;
- compatibilité des formats historiques v1 et v2 ;
- comparaison des compteurs et des données canoniques après restauration.

### Critère de sortie

- Le test automatique « base complète → sauvegarde → base vide → restauration »
  restitue 100 % des données métier attendues.

## 5. Phase 2 — Restauration transactionnelle

Durée indicative : 3 à 5 jours.

### Travaux

- Restaurer d’abord dans une base SQLite temporaire.
- Vérifier le manifeste, les clés étrangères, les compteurs et
  `PRAGMA integrity_check`.
- Proposer deux modes explicites :
  - remplacement exact du commerce ;
  - import/fusion contrôlé.
- Pour un remplacement, créer automatiquement un snapshot de secours.
- Ne remplacer les données actives qu’après validation complète de la base
  temporaire.
- Restaurer les médias dans un répertoire temporaire, puis les déplacer lors du
  commit final.
- En cas d’échec, supprimer les fichiers temporaires et conserver la base
  d’origine intacte.
- Sur un nouvel appareil, créer un nouvel identifiant d’appareil et imposer la
  définition d’un nouveau PIN propriétaire.
- Restaurer les employés et rôles, mais leur imposer une nouvelle inscription
  sécurisée au lieu de transférer leurs PIN.

### Critère de sortie

- Une coupure simulée à chaque étape ne produit ni commerce partiel ni média
  orphelin.

## 6. Phase 3 — Sauvegardes automatiques et cloud

Durée indicative : 3 à 5 jours.

### Travaux

- Créer automatiquement une sauvegarde lorsque l’application revient au premier
  plan si la dernière sauvegarde date de plus de 24 heures.
- Ajouter ensuite une tâche Android WorkManager comme second mécanisme.
- Appliquer une rétention locale configurable, par exemple 7 sauvegardes
  quotidiennes et 4 hebdomadaires.
- Créer un bucket Supabase Storage privé dédié aux sauvegardes.
- Organiser les objets sous
  `business_id/device_id/backup_id.kumba`.
- Envoyer uniquement des fichiers déjà chiffrés.
- Faire générer par l’Edge Function une autorisation d’envoi limitée dans le
  temps ; ne jamais exposer `service_role` dans Flutter.
- Stocker en base les métadonnées, empreintes, état d’envoi et date de dernière
  restauration testée.
- Ajouter reprise d’envoi, idempotence et suppression distante selon la politique
  de rétention.
- Prévoir un export explicite vers un emplacement choisi par l’utilisateur.

### Point d’attention

Les sauvegardes Postgres gérées par Supabase ne couvrent pas les objets Storage.
Le plan de reprise doit donc traiter séparément la base et les fichiers.

### Critère de sortie

- La perte complète du téléphone peut être récupérée avec un nouvel appareil,
  les identifiants autorisés et le secret de récupération.

## 7. Phase 4 — Socle de synchronisation cloud

Durée indicative : 5 à 8 jours.

### Schéma cible

Créer, via une migration révisée :

- `sync_events` : journal append-only avec séquence serveur monotone ;
- `sync_entities` : état courant versionné des entités mutables ;
- `device_cursors` : dernier événement confirmé par appareil ;
- `device_sync_tokens` : jetons hachés, expirables et révocables ;
- index sur `(business_id, server_sequence)` et
  `(business_id, entity_type, entity_id)` ;
- unicité sur `(business_id, idempotency_key)`.

### Règles de conflit

- ventes, paiements, retours, mouvements de stock et de dette :
  événements immuables et idempotents ;
- produit, client, fournisseur et paramètres :
  version serveur + détection de modification concurrente ;
- suppression :
  tombstone synchronisé, jamais suppression silencieuse immédiate ;
- stock :
  calculé depuis les mouvements, pas synchronisé comme une valeur libre ;
- conflit non résolu :
  placé dans une file visible, sans écraser automatiquement les données.

### Edge Functions

- ajouter un `push` par lot dans une transaction ;
- retourner les accusés de réception et le nouveau curseur ;
- renforcer `pull` avec pagination, curseur et reprise ;
- limiter taille, débit et nombre d’événements ;
- auditer chaque refus d’autorisation ;
- vérifier systématiquement l’appartenance du jeton au commerce ;
- rendre toutes les opérations idempotentes.

### Sécurité

- RLS activée sur toutes les tables exposées ;
- accès `anon` et `authenticated` révoqué si l’accès passe exclusivement par les
  Edge Functions ;
- `service_role` uniquement côté serveur ;
- fonctions privilégiées placées hors schéma exposé, avec droits `EXECUTE`
  explicitement révoqués puis accordés au seul rôle nécessaire ;
- rotation et révocation des jetons appareil ;
- test des séparations entre deux commerces.

### Critère de sortie

- Deux appareils ne peuvent jamais lire ou modifier les données d’un autre
  commerce.

## 8. Phase 5 — Synchronisation bidirectionnelle Flutter

Durée indicative : 6 à 10 jours.

### Travaux

- Remplacer le push élément par élément par des lots.
- Implémenter `pullSince(cursor)`.
- Appliquer chaque lot distant dans une transaction SQLite.
- Persister le curseur seulement après commit local.
- Ajouter les tombstones et les versions aux tables concernées.
- Couvrir tous les modules métier, pas uniquement ventes, produits, clients et
  dépenses.
- Déclencher une synchronisation :
  au démarrage, au retour réseau, après mutation et périodiquement.
- Différencier clairement :
  hors ligne, en attente, synchronisé, conflit et erreur définitive.
- Ajouter une action de relance pour les éléments en erreur.
- Compacter les événements déjà confirmés sans perdre l’audit nécessaire.

### Scénarios de test

- appareil A et B modifient le même produit hors ligne ;
- vente créée deux fois après plusieurs reprises réseau ;
- suppression effectuée hors ligne ;
- jeton révoqué ;
- application tuée pendant le pull ;
- serveur répond partiellement ou hors ordre ;
- 10 000 événements en attente ;
- changement d’heure du téléphone.

### Critère de sortie

- Deux appareils convergent vers le même état après reconnexion, sans doublon de
  vente, paiement, dette ou stock.

## 9. Phase 6 — Équipe et fonctions actuellement incomplètes

Durée indicative : 4 à 7 jours.

### Invitations employé

- déplacer les invitations dans Supabase ;
- code à usage unique, expiration, rôle et commerce signés côté serveur ;
- permettre réellement l’inscription depuis un autre téléphone ;
- révoquer les invitations et appareils depuis le compte propriétaire.

### Mobile Money

- renommer immédiatement la fonction actuelle en
  « Enregistrer une référence Mobile Money » ;
- ne pas afficher « paiement vérifié » sans API opérateur ou agrégateur ;
- ajouter l’intégration réelle plus tard avec webhook signé, idempotence et état
  `pending/success/failed`.

### Impression

- annoncer uniquement PDF/impression système tant qu’un transport Bluetooth
  ESC/POS réel n’est pas branché ;
- tester les formats 58 et 80 mm sur au moins deux modèles d’imprimantes avant
  d’activer la mention Bluetooth.

### Biométrie, caméra et scanner

- tests sur appareils physiques ;
- comportement explicite quand la permission est refusée ;
- reprise correcte après interruption Android.

## 10. Phase 7 — Validation et exploitation

Durée indicative : 5 à 8 jours.

### Tests automatisés

- tests unitaires BackupService et moteur de synchronisation ;
- tests d’intégration Flutter avec base réelle ;
- tests Deno des Edge Functions, succès et erreurs ;
- tests SQL des contraintes, RLS et fonctions ;
- analyse Supabase Database Advisors ;
- tests de charge sur push, pull et Storage.

### Tests terrain

- Android 8, 10, 12, 14 et 16 ;
- téléphone bas de gamme avec peu de stockage ;
- réseau instable, mode avion et changement Wi-Fi/mobile ;
- mise à jour depuis une base existante ;
- perte du téléphone puis restauration ;
- deux appareils actifs pendant plusieurs jours.

### Observabilité

- erreurs anonymisées et corrélées par identifiant d’opération ;
- métriques de backlog, âge du dernier sync, sauvegarde la plus récente et taux
  d’échec ;
- alertes sur échec répété des sauvegardes et de la synchronisation ;
- procédure documentée de révocation d’un appareil et de reprise après incident.

## 11. Portes GO / NO-GO

### GO 1 — Bêta locale sur un téléphone

- sauvegarde v3 exhaustive ;
- restauration transactionnelle réussie ;
- parcours vente/crédit/retour validés sur téléphone ;
- mise à jour conservant les données validée.

### GO 2 — Bêta cloud multi-appareils

- push et pull bidirectionnels ;
- tous les modules utiles couverts ;
- tests de conflit à deux appareils réussis ;
- séparation stricte des commerces vérifiée ;
- restauration depuis sauvegarde cloud réussie.

### GO 3 — Lancement public

- aucun défaut critique ouvert ;
- test de reprise après perte d’appareil réussi ;
- rétention et supervision actives ;
- politique de confidentialité et procédure support prêtes ;
- validation terrain signée sur la matrice Android ;
- exercice de restauration Supabase/Postgres et Storage documenté.

## 12. Ordre recommandé et charge réaliste

Pour un développeur principal connaissant le projet :

- sauvegarde et restauration fiables : 1,5 à 2 semaines ;
- synchronisation cloud complète : 2,5 à 4 semaines ;
- fonctions secondaires, sécurité et validation terrain : 1,5 à 2,5 semaines.

Charge totale réaliste : environ 5 à 8 semaines, hors délais d’accès aux comptes,
retours du terrain et intégrations opérateurs Mobile Money.

Une sortie plus rapide est possible uniquement en réduisant honnêtement le
périmètre à un fonctionnement local sur un seul téléphone.

