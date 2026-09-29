# Politique de Confidentialité — KUMBA Business

**Dernière mise à jour : 26 Juillet 2026**

La présente Politique de Confidentialité décrit la manière dont l'application mobile **KUMBA Business** collecte, utilise et protège vos données personnelles et commerciales.

---

## 1. Engagement Offline-First & Protection de la Vie Privée

**KUMBA Business** est une application conçue selon le principe **Offline-First / Local-First**. 

- **Vos données commerciales restent sur votre appareil** : Vos transactions, listes de produits, identités clients, dettes, factures et rapports sont stockés localement sur votre téléphone dans une base de données SQLite sécurisée et chiffrée (AES).
- **Aucune transmission sans votre consentement** : Aucune donnée commerciale n'est transmise à des serveurs tiers sauf si vous configurez explicitement une URL de synchronisation HTTP dans les paramètres.

---

## 2. Données Collectées & Autorisations d'Appareil

### 2.1 Caméra
- **Usage** : Utilisée exclusivement pour le scan de codes-barres de vos articles en caisse et pour la prise de photos d'illustration de vos produits ou factures.
- **Stockage** : Les images capturées restent uniquement sur votre appareil.

### 2.2 Biométrie & PIN
- **Usage** : Le capteur d'empreinte digitale ou la reconnaissance faciale (via Android `local_auth`) est utilisé uniquement pour déverrouiller l'accès local à l'application.
- **Stockage** : Vos données biométriques ne sont jamais lues ni stockées par l'application ; elles sont gérées de manière totalement sécurisée par le système d'exploitation Android.

### 2.3 Réseau & Connexion Internet
- **Usage** : Utilisé pour détecter l'état de la connexion (mode hors-ligne vs en ligne) et transmettre la file d'attente de synchronisation uniquement vers l'URL de serveur que vous avez configurée.

---

## 3. Sécurité des Données

- **Chiffrement local** : Vos sauvegardes sont chiffrées avec l'algorithme **AES** et protégées par checksum et clé de transfert unique (`transferKey`).
- **Permissions d'accès (RBAC)** : L'accès aux fonctionnalités sensibles de l'application est restreint par rôle utilisateur (Propriétaire, Gérant, Vendeur, Livreur, Comptable).

---

## 4. Partage & Revente de Données

Nous ne vendons, ne louons, ni ne partageons vos données personnelles ou commerciales avec aucune entreprise tierce ou partenaire publicitaire.

---

## 5. Vos Droits & Suppression des Données

Puisque vos données sont conservées localement sur votre appareil :
- Vous pouvez **exporter l'intégralité de vos données** à tout moment depuis le menu Sauvegardes.
- Vous pouvez **supprimer définitivement toutes vos données** en réinitialisant l'application ou en désinstallant KUMBA Business de votre téléphone.

---

## 6. Contact

Pour toute question concernant cette Politique de Confidentialité, vous pouvez contacter notre équipe support à : `support@kumba-business.com`.
