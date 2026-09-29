# Statut des fonctionnalités & Limites résolues (Android)

1. **Sync multi-appareils** : ✅ File d'attente locale + Client HTTP de synchronisation ([http_sync_client.dart](file:///c:/Users/migco/Desktop/client%20davex/kumba/lib/core/sync/http_sync_client.dart)) + Serveur HTTP de référence ([sync_server.dart](file:///c:/Users/migco/Desktop/client%20davex/kumba/server/sync_server.dart)).
2. **Scanner caméra** : ✅ Scanner haute performance natif via `mobile_scanner` avec permission runtime.
3. **Paiement Mobile Money** : ✅ **Référence manuelle** (pas de push USSD / API opérateur) — le caissier saisit la réf. reçue après paiement client ([mobile_money_service.dart](../lib/core/network/mobile_money_service.dart)).
4. **Impression thermique** : ✅ PDF 58/80 mm + bytes ESC/POS — valider **imprimante réelle** sur terrain ([esc_pos_printer_service.dart](../lib/core/utils/esc_pos_printer_service.dart)).
5. **Biométrie & Sécurité** : ✅ Auth biométrique `local_auth` + Verrouillage 2 min + Sauvegarde AES.
6. **Langues** : ✅ Support bilingue complet Français / Anglais avec sélecteur dynamique.
7. **Signature Android Pro** : ✅ Configuration `key.properties` dans `build.gradle.kts` pour Play Store.
8. **iOS** : Hors scope délibéré (plateforme Android mobile-first prioritaire).
9. **Assistant IA « Lynk »** : ✅ Réinventé le 2026-09-25 en architecture
   hybride (voir [LOCAL_AI.md](LOCAL_AI.md)) — chiffres métier calculés
   localement (instantanés, hors ligne) + questions libres via Llama 3.2-3B
   sur Cloudflare Workers AI. L'ancien GGUF embarqué (196 Mo, modèle détruit
   par requantification) a été retiré. Limite assumée : les questions libres
   exigent le réseau ; repli local honnête hors ligne.

## Console d'administration (dashboard Neon/Cloudflare)

Limites connues, relevées lors de la recette navigateur du 2026-09-25 :

1. **Activation express sans agent** : le champ « Agent commercial » est
   vide tant qu'aucun staff `role=commercial` n'existe — comportement
   attendu, pas un bug.
2. **Révocation de sessions** : ✅ résolu le 2026-09-25 (`token_version`) —
   le token HMAC porte `tv` ; chaque requête admin relit `role`, `status` et
   `token_version` dans `staff_accounts` et renvoie 401 si le compte est
   supprimé/désactivé ou sa version bumpée. Leviers UI : colonne « Actions »
   de l'onglet Équipe (Révoquer/désactiver, Réactiver) ; leviers API :
   `POST /api/v1/admin/staff/update` (status/role/password) et suppression
   du compte. ⚠️ Toute modification MANUELLE de `password_hash`, `role` ou
   `status` en SQL doit incrémenter `token_version` pour révoquer les
   sessions existantes (sinon le rôle change à la prochaine requête mais le
   mot de passe émis reste utilisable jusqu'à reconnexion).

Résolu depuis : **navigation mobile** — sous ≤900 px la sidebar devient un
tiroir hors-canvas (barre supérieure sticky + hamburger 44 px, scrim,
fermeture par onglet/Échap, `visibility:hidden` hors focus clavier, tables à
scroll horizontal propre) ; recette navigateur validée le 2026-09-25.
