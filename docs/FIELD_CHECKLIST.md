# Checklist terrain — 7 jours (1 page)

**Produit** : Lynkstor Business · **Objectif** : valider GO pilote avant scale / Play Store  
**Appareils** : 1 bas de gamme + 1 milieu · **Réseau** : online + mode avion

Cocher chaque case. Un **NO** sur un item 🔴 bloque le GO production élargi.

---

## Jour 0 — Installation

| # | Test | OK |
|---|------|----|
| 0.1 | Installer l’APK release (idéalement **keystore pro**, sinon debug pilote) | ☐ |
| 0.2 | Créer commerce avec **code agent** (cloud) **ou** démo locale | ☐ |
| 0.3 | PIN 4 chiffres + biométrie si dispo | ☐ |
| 0.4 | Langue FR ↔ EN bascule sans crash | ☐ |

---

## Caisse & stock (🔴 bloquant)

| # | Test | OK |
|---|------|----|
| 1.1 | Ajouter 10 produits (prix, stock, 1 favori) | ☐ |
| 1.2 | Vente cash multi-lignes → reçu → stock diminué | ☐ |
| 1.3 | Vente crédit **avec** client → dette créée | ☐ |
| 1.4 | Vente crédit **sans** client → refus (pas de crash) | ☐ |
| 1.5 | Stock insuffisant → refus vente | ☐ |
| 1.6 | Encaissement dette partiel + total | ☐ |
| 1.7 | Retour / annulation (rôle owner/manager) → restock | ☐ |
| 1.8 | Seller **ne peut pas** retour / backup | ☐ |
| 1.9 | MoMo : saisie **référence manuelle** (pas de faux USSD) | ☐ |
| 1.10 | Scanner code-barres (si caméra) | ☐ |

---

## Offline (🔴 bloquant)

| # | Test | OK |
|---|------|----|
| 2.1 | Mode avion 2 h : vendre, stock, dettes, dépenses | ☐ |
| 2.2 | Bannière hors ligne visible | ☐ |
| 2.3 | Reprise réseau : sync cloud si compte lié (pas d’erreur bloquante) | ☐ |
| 2.4 | Redémarrage téléphone → données intactes + PIN | ☐ |
| 2.5 | Verrouillage après fond d’écran (~2 min) | ☐ |

---

## Backup & reprise (🔴)

| # | Test | OK |
|---|------|----|
| 3.1 | Export sauvegarde / transfert `.kumba` | ☐ |
| 3.2 | Réinstall app → restore → PIN + données OK | ☐ |
| 3.3 | « PIN oublié » message cohérent (pas de backdoor) | ☐ |

---

## Cloud & admin (🟠 si multi-appareils)

| # | Test | OK |
|---|------|----|
| 4.1 | Admin [lynkstor-admin.pages.dev](https://lynkstor-admin.pages.dev/) login | ☐ |
| 4.2 | Générer codes activation agent | ☐ |
| 4.3 | Nouvel appareil + code → commerce dans Supabase | ☐ |
| 4.4 | Démo locale **n’apparaît pas** comme abonné cloud | ☐ |
| 4.5 | 2 appareils même commerce (si requis) : vente A visible côté B après sync | ☐ |

---

## Hardware & perf (🟠)

| # | Test | OK |
|---|------|----|
| 5.1 | Reçu PDF / partage WhatsApp | ☐ |
| 5.2 | Impression thermique réelle (si client a imprimante) | ☐ |
| 5.3 | Mode performance ON : UI fluide bas de gamme | ☐ |
| 5.4 | 50+ ventes du jour : dashboard / liste OK | ☐ |
| 5.5 | Aucun crash 7 jours (noter modèle téléphone) | ☐ |

---

## Verdict terrain

| Critère | Décision |
|---------|----------|
| Tous 🔴 OK | **GO pilote élargi** |
| 1+ 🔴 KO | **NO GO** — corriger avant plus de clients |
| 🟠 KO seulement | GO mono-appareil ; multi-appareils / print plus tard |

**Commerce pilote** : _______________  
**Téléphones** : _______________  
**Dates** : _______ → _______  
**Signé** : _______________

---

## Suite après terrain OK

1. Keystore release sauvegardé hors machine (`tool/create_release_keystore.ps1`)
2. Build signé : `powershell -File tool/build_release_apk.ps1` (+ `-Bundle` pour Play)
3. Crash reporting (Sentry / Firebase) si budget
4. Voir `docs/PRODUCTION_READY.md` et `docs/ANDROID_RELEASE.md`
