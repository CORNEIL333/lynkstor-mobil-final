---
name: lynkstor-ui-senior
description: Auditer et améliorer l'interface Flutter de Lynkstor/Kumba avec une démarche UI/UX de production, des composants cohérents et une validation visuelle et fonctionnelle. Utiliser pour ses écrans, parcours, accessibilité, thème et animations.
---

# Lynkstor UI senior

Transformer une demande UI en amélioration observable de l'usage : encaisser vite, lire les montants sans ambiguïté, retrouver ses produits et comprendre l'état hors ligne. Ne pas prétendre avoir travaillé dans une entreprise ou posséder une expérience humaine ; démontrer la qualité par les décisions et leurs preuves.

## Commencer par le produit réel

- Identifier le projet par `pubspec.yaml` et ses routes. Ce skill cible Flutter, Riverpod et go_router ; ne pas appliquer de recettes CSS/React ou migrer le framework.
- Lire les instructions du dépôt, puis les tokens de `lib/core/theme`, composants de `lib/design_system` et écrans effectivement montés par `lib/app/router.dart`. Un composant existant mais inutilisé ne prouve pas le rendu actif.
- Lire `docs/UI_UX_AUDIT_2026-09-22.md` s'il existe comme point de départ historique ; revérifier chaque constat avant de le reprendre. Comparer les références présentes dans `docs/reference` et les documents design aux demandes récentes de l'utilisateur. Une ancienne maquette ne doit pas annuler une décision récente.
- Respecter le périmètre : audit demandé → diagnostic et priorités ; modification demandée → implémentation et vérification jusqu'au résultat. Ne pas transformer un audit en refonte non sollicitée.

## Diagnostic et direction

Relier chaque défaut à un écran, une preuve et une conséquence : lisibilité, tâche bloquée, fausse information, coût d'interaction ou incohérence. Distinguer observation exécutée, preuve statique et hypothèse à tester. Ne pas inventer une note de design ou prétendre avoir vu une capture non inspectée.

Hiérarchiser : exactitude des données et récupération d'erreur, accessibilité, parcours, cohérence visuelle, puis finition. Une sparkline nécessite des données et une période ; une donnée absente ne vaut pas zéro. Une sauvegarde/synchronisation ne doit pas être présentée comme terminée sans confirmation métier.

Conserver la direction de marque la mieux étayée. En cas de références contradictoires, avancer sur les corrections indépendantes et expliciter l'hypothèse visuelle. Ne pas imposer automatiquement une palette unique, des dégradés, du glassmorphism, une nouvelle police ou une grille asymétrique à un ERP.

## Implémentation Flutter

- Réutiliser les tokens et composants actifs ; définir les couleurs par rôle avec leur foreground. Vérifier les couleurs forcées localement : changer `onPrimary` seul peut ne rien corriger.
- Préserver services, montants, données locales, permissions, routes et textes FR/EN. Les actions visibles doivent correspondre aux droits, sans retirer les protections de route/service.
- Donner à chaque écran une hiérarchie claire et une action principale. Séparer visuellement total, montant payé et reste dû ; conserver le panier après erreur.
- Prévoir chargement, vide, erreur récupérable, succès, désactivé et traitement en cours selon le parcours. Protéger l'envoi contre les doubles taps et vérifier `mounted` après attente asynchrone.
- Adapter par contraintes et contenu. Éviter les hauteurs fixes pour des cartes textuelles ; ne pas utiliser de réduction automatique du texte ou bloquer TextScaler pour dissimuler un débordement. Conserver lisibles les grands montants FCFA.
- Préférer contrôles Material adaptés ou ajouter explicitement focus, raccourcis d'activation et Semantics aux interactions personnalisées. Une icône décorative n'a pas besoin d'une annonce répétée ; une action iconique a besoin d'un nom.
- Vérifier les surfaces et états de chaque thème séparément. Viser 4,5:1 pour le texte normal et au moins 3:1 pour le grand texte ; ne pas considérer un petit texte secondaire comme exempté. Cibles Android 48 × 48 dp, iOS 44 × 44 points ; l'icône peut être plus petite que la cible.
- Respecter mouvement réduit ET mode performance. Rendre l'état final visible sans animation quand ils l'exigent, plutôt que ramener une animation de fade à zéro. Éviter effets continus coûteux et animations retardant la saisie/vente.
- Employer les dépendances présentes (Phosphor, flutter_animate, fl_chart) seulement si utiles. Ne pas installer une bibliothèque pour un effet réalisable simplement avec Flutter.

## Outils au service du résultat

Utiliser Flutter DevTools pour le layout, rebuilds et timings lorsqu'une exécution est disponible. Utiliser Figma pour une référence ou des variables fournies, après lecture du skill Figma requis ; ne pas rendre sa présence obligatoire. Pour une cible web, utiliser l'outil navigateur disponible ; pour une app native, outils Flutter/appareil accessibles. Ne pas supposer qu'une API d'automatisation est disponible.

Les skills UI/UX Pro Max ou motion installés peuvent compléter une question précise ; leurs recettes esthétiques restent subordonnées au contexte métier et aux choix de l'utilisateur. Consulter les sources officielles pour une API/version incertaine :

- https://docs.flutter.dev/ui/accessibility/ui-design-and-styling
- https://docs.flutter.dev/ui/accessibility/accessibility-testing
- https://docs.flutter.dev/ui/adaptive-responsive/best-practices

## Vérifier avant de livrer une modification

Rendre les écrans modifiés avec des données représentatives, inspecter les captures avant/après à viewport identique. Tester un petit téléphone (320/360 dp), un téléphone standard (390 dp) et tablette si concernée ; clair/sombre, texte jusqu'à 200 %, clavier, SafeArea et mouvement réduit. Ne pas modifier une référence golden avant d'avoir compris et examiné le diff.

Exécuter l'analyse et les tests ciblés pertinents, dont les guidelines Flutter pour contraste, labels et cibles si les composants interactifs changent. Vérifier le parcours métier touché, ses états d'échec et les rôles concernés. Pour une modification de performance, mesurer sur une cible représentative ; ne pas annoncer 60 fps sur la seule base du code. TalkBack se vérifie sur appareil quand disponible.

Si l'environnement empêche un rendu, livrer les preuves statiques et contrôles disponibles, nommer précisément le contrôle manquant et ne pas annoncer la validation visuelle comme faite. Ne pas élargir une petite correction en campagne de tests exhaustive sans motif.

Livrer : problème résolu, fichiers pertinents, captures réellement obtenues, contrôles passés/échoués et limites restantes. La sophistication des outils ne remplace pas ces preuves.
