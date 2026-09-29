# Audit UI/UX Lynkstor — 22 septembre 2026

## Conclusion

La base Flutter est structurée et possède déjà les outils nécessaires. Le principal frein est la coexistence de plusieurs directions visuelles et de composants partiellement raccordés, avec des problèmes de lisibilité et de fiabilité des indicateurs. Ajouter des animations ou remplacer la police ne résoudrait pas ces problèmes.

Périmètre : lecture du code de l'accueil, du shell, de la caisse, des composants et tokens ; inspection des deux références locales `docs/reference/template.jpeg` et `figma_make_thumb.png`. Ces images sont des références, pas des captures de la version exécutée. Les constats visuels sur l'application sont donc des déductions du code ; les débordements et le ressenti doivent encore être validés sur appareil. Aucun score esthétique arbitraire n'est attribué.

## Atouts à préserver

- Actions métier « Vendre » et « Encaisser » explicites sur l'accueil.
- Tokens de couleurs, espacements, typographie Plus Jakarta Sans et motion déjà centralisés.
- Chiffres tabulaires sur les KPI ; composants d'erreur avec nouvelle tentative.
- Navigation adaptée aux permissions et NavigationRail à partir de 840 dp.
- États hors ligne, synchronisation et abonnement présents dans le shell.
- Riverpod, go_router, Phosphor, flutter_animate et fl_chart déjà disponibles : aucune migration de stack nécessaire.

## Constats prioritaires

### P1 — Les indicateurs peuvent donner une impression fausse de l'activité

Dans `lib/features/dashboard/dashboard_screen.dart:224`, « Acomptes » utilise `MoneyFormat.formatCompact(0)` et un libellé fixe « 0 acompte ». Cela ne prouve pas l'absence d'acomptes. À connecter à une source métier vérifiée ou remplacer par un état « Indisponible »/retirer la carte.

La carte Ventes active `spark: true` (ligne 176). `lib/design_system/components/kumba_ornament.dart:103` dessine une courbe constante sans série de données. Dans une carte financière, elle suggère une tendance qui n'est pas calculée. Utiliser une série réelle et une période explicite, sinon supprimer la courbe.

### P1 — Contraste insuffisant sur une action principale

`lib/core/theme/app_colors.dart:34` définit `fab = #FF9800`, alias de `primary`, avec `onPrimary = #FFFFFF`. Le bouton principal utilise ce couple dans `lib/design_system/components/kumba_button.dart`, et la carte Vendre aussi.

Ratios calculés par luminance relative sRGB sur les aplats opaques :

| Couple | Ratio | Conséquence |
|---|---:|---|
| Blanc / orange #FF9800 | 2,16:1 | Insuffisant même pour du grand texte au seuil 3:1 |
| Gris #8B95A7 / fond KPI #F3FAF6 | 2,85:1 | Insuffisant pour les légendes de 11 dp |
| Encre #0F172A / orange #FF9800 | 8,28:1 | Correction possible conservant la couleur de marque |

Créer des couples sémantiques fond/texte, puis propager aux composants. Ne pas simplement modifier `onPrimary` : certains composants imposent encore `Colors.white`. Les seuils et les tests sont décrits dans la [documentation Flutter sur l'accessibilité](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling).

### P1 — Le chargement initial de la caisse manque de récupération

`lib/features/sales/sale_screen.dart:68` attend produits et clients sans gestion d'exception ni contrôle `mounted` avant `setState`. L'écran affiche un chargement tant que `_loading` reste vrai (ligne 357). En cas d'échec du service, risque de chargement persistant sans nouvelle tentative ; en quittant pendant le chargement, risque de mise à jour d'un écran détruit. Ajouter un état d'erreur récupérable et préserver le panier lors des nouvelles tentatives.

### P2 — Trois références de design concurrentes

`docs/DESIGN_SYSTEM_V2.md` décrit un hero bleu photographique, des illustrations clay et un dock marine. Le thème actuel emploie un header marine/orange et une navigation claire ; plusieurs commentaires parlent encore de bleu/turquoise ou de style iOS. `template.jpeg` et la miniature Figma ne représentent pas la même composition.

Décision recommandée : documenter la direction réellement retenue avant une refonte générale ; conserver provisoirement marine/orange de l'implémentation actuelle en corrigeant sa lisibilité. Une référence ancienne ne suffit pas à autoriser un changement de marque. La miniature Figma, peu définie et limitée à un écran d'entrée, ne permet pas d'auditer tous les parcours.

### P2 — La navigation conçue n'est pas celle exécutée

Le routeur monte `ShellScaffold` (`lib/app/router.dart:168`). Celui-ci construit sa propre barre Accueil/Ventes/Stock/Assistant. `KumbaFloatingNavBar`, avec action centrale Vendre et entrée Plus, n'a pas d'appel dans `lib` hors de sa déclaration. L'auditer seul donnerait une conclusion erronée sur l'application.

Unifier la navigation active et sa documentation ; garder l'accès rapide à la caisse et un menu découvrable. Préserver les destinations filtrées par permissions et la navigation tablette. Les cartes Vendre/Encaisser de l'accueil restent visibles sans filtre local alors que les routes sont protégées : risque de chemin vers un refus d'accès, pas preuve de contournement des permissions.

### P2 — Accessibilité des interactions incomplète

`lib/design_system/components/kumba_pressable.dart:33` repose sur GestureDetector sans gestion explicite du focus, de l'activation clavier ou du rôle bouton. Cela ne signifie pas absence totale de sémantique Flutter, mais le contrat d'accessibilité n'est pas assuré. Vérifier le nom, le rôle, l'état et l'activation de chaque carte interactive.

Le bouton de repli Lynk (`dashboard_screen.dart:242`) a une surface de 40 × 40 et aucun libellé explicite à cet endroit. Prévoir une cible Android de 48 × 48 dp et un intitulé annonçant développer/replier. Vérifier avec l'[Accessibility Guideline API](https://docs.flutter.dev/ui/accessibility/accessibility-testing), puis TalkBack.

### P2 — Mise à l'échelle et mode sombre à vérifier

Les cartes d'action font 156 dp de haut, les KPI 124 dp, dans deux colonnes ; les légendes KPI font 11 dp. Le risque de coupure augmente avec les montants longs et le texte agrandi. La carte Lynk inclut une ligne de titre non flexible. Vérifier 320/390 dp et une échelle de texte à 200 %, sans réduire le texte pour masquer le problème.

La caisse impose `AppColors.pageBg` même quand `dark` est vrai ; l'accueil garde certaines cartes blanches et fonds KPI clairs. Le mode sombre existe mais son application est partielle. Les surfaces claires peuvent être intentionnelles ; leur cohérence et tous les contrastes restent à vérifier séparément.

### P2 — Mouvement réduit et mode performance ne sont pas uniformes

L'accueil combine les préférences pour l'avatar, mais `KumbaReveal` ne lit que `MediaQuery.disableAnimations`. La caisse utilise notamment `.animate(target: reduce ? 0 : 1).fadeIn(...)` : revenir à la valeur initiale peut laisser le contenu transparent selon la configuration des effets. À vérifier par un test ciblé ; en mode réduit, rendre directement l'état final visible. Ne jamais retarder une action de caisse pour une animation d'entrée.

## Plan de correction

1. Fiabilité : acomptes, courbe, états de chargement et reprise en caisse.
2. Accessibilité : couples de couleurs, cibles tactiles, focus et libellés.
3. Cohérence : une direction documentée, composants réellement branchés, surfaces clair/sombre.
4. Adaptation : hauteur fondée sur le contenu, grands montants, petits écrans, texte agrandi.
5. Finition : hiérarchie, rythme des espacements, icônes et transitions utiles.

Direction proposée : outil de commerce chaleureux, lisible rapidement ; marine pour la structure, orange pour l'action primaire avec texte sombre, couleurs sémantiques pour alertes et statuts. Réserver les illustrations à l'identité ou à l'onboarding, limiter leur compétition avec les chiffres métier. Conserver Plus Jakarta Sans tant qu'aucun défaut concret ne justifie un remplacement.

## Outils et preuves attendues

- Flutter DevTools pour inspecter le layout et profiler sur une cible représentative ; une mesure desktop/debug ne prouve pas la fluidité Android.
- Tests de widgets pour les états, permissions, chargements, retours et accessibilité ; captures/goldens pour contrôler la composition. Ne pas actualiser les goldens uniquement pour faire passer un échec.
- Figma si une maquette précise est fournie ; comparer le rendu Flutter à la référence au même viewport. Figma n'est pas obligatoire pour corriger le code.
- TalkBack, thème sombre, texte agrandi, clavier ouvert, navigation retour et fonctionnement hors ligne pour les parcours critiques.
- Scénarios : accueil → vente → panier → règlement → reçu ; client → dette → encaissement ; stock → recherche → produit.

Cet audit n'est ni un test utilisateur terrain, ni une validation visuelle de toutes les routes. Le skill associé formalise ces contrôles pour les prochaines améliorations.

## Vérifications réalisées

- Skill `lynkstor-ui-senior` installé dans `C:/Users/migco/.codex/skills/lynkstor-ui-senior` ; validateur officiel `quick_validate.py` : `Skill is valid!`. Copie source conservée dans `tool/skills/lynkstor-ui-senior` ; empreintes SHA-256 du SKILL.md identiques.
- `flutter test test/widget/prototype_integration_test.dart --no-pub --reporter compact` : **3 tests réussis, 1 échoué**. Les actions du header passent à 320 et 1000 dp ; les données catalogue passent leur contrôle.
- Le test du parcours de recherche échoue à la ligne 106 : `find.text('Beignet fourré')` correspond au champ de recherche et au résultat alors que l'assertion attend un seul widget. Ce sélecteur ambigu empêche la vérification de navigation ; cet échec ne démontre pas un défaut de recherche dans l'application. Corriger le ciblage du test avant de considérer ce parcours validé.
- Aucun fichier applicatif Flutter modifié pendant cet audit. Pas de validation sur téléphone physique ni de capture actuelle du dashboard.
