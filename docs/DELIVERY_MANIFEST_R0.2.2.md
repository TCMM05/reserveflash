# Manifeste de livraison - R0.2.2 (clôture documentaire/build)

Ce document rassemble, en un seul endroit, tout ce qu'il faut pour
vérifier indépendamment cette livraison, en réponse au point 7 de la
demande de clôture R0.2.2 : *"livrer un manifeste final séparé contenant
ZIP/APK/commit/tag/versions/SHA."*

## Environnement ayant produit ce résultat (reproductibilité)

| Outil | Version |
|---|---|
| Flutter | 3.47.0 |
| Dart | 3.13.0 |
| Java (Android) | 17 (JDK bundlé Android Studio) |
| Android SDK | 36.0.0 |
| Gradle | 9.3.1 |
| OS de build | Windows (poste réel de l'utilisateur, pas un CI) |

`.github/workflows/ci.yml` (`FLUTTER_VERSION`) a été aligné sur cette
version exacte (3.47.0) dans cette clôture - voir CHANGELOG.md.

## Commit / tag Git

- Commit de code (hotfixes R0.2.1) : `3266752`.
- Voir `git log`/`git tag -n1` pour le commit et le tag exacts de CETTE
  clôture R0.2.2 - volontairement non figés en dur ici pour la même
  raison que dans `docs/GATE_R0.1_STATUS.md` (un document ne peut pas
  citer avec exactitude le hash du commit qui le contient sans devenir
  obsolète dès sa prochaine modification).

## Archive source (ZIP)

Générée par `git archive` depuis le tag de cette livraison - contenu
strictement identique au code committé.

- `ReserveFlash_R0.2.1_Hotfix.zip` (livraison R0.2.1, précédente) :
  SHA-256 `1147994981558dea49b961b6032dd8cf977b1dee69d5035f88798a6efec8c1f3`
- Archive R0.2.2 (celle-ci) : SHA-256 fourni dans le message de livraison
  qui accompagne ce document (même raison que ci-dessus : l'archive
  contient ce fichier).

## APK Android debug

- Fichier : `app-debug.apk`
- Taille : 183 865 201 octets
- SHA-256 : `08fe8ac120e38befaf7cc9bb753b63ff8d86308f674490ead639ca9e2077ada7`
- SHA-1 (généré par Gradle, `app-debug.apk.sha1`, recalculé indépendamment
  sur la copie transférée - identique) : `7826ade1fc3267e34ff60ddf683c7affe8387fbf`
- **Limitation de transmission connue** : ce fichier fait 175,3 MiB, ce qui
  dépasse la limite de 30 MiB des pièces jointes de cette conversation - il
  n'a donc PAS pu être transmis via ce canal. Il reste disponible sur le
  poste de l'utilisateur, à
  `C:\Dev\Application claude\Reserveflash\repo\mobile\build\app\outputs\flutter-apk\app-debug.apk`.
  Une vérification indépendante du SHA-256 ci-dessus nécessite que
  l'utilisateur transmette ce fichier à l'équipe par un autre canal (le
  SHA-1 fourni par Gradle constitue en attendant une preuve d'intégrité du
  transfert vers cet environnement, mais pas une preuve indépendante
  vis-à-vis de l'équipe qui ne l'a pas reçu).

## `pubspec.lock`

Committé pour la première fois dans cette clôture (voir CHANGELOG.md,
point 3 de la demande R0.2.2) - reflète exactement les versions résolues
par le `flutter pub get` du build réellement validé (même horodatage que
l'exécution qui a produit l'APK ci-dessus : 2026-08-19T14:59:43+02:00).

## `flutter analyze`

0 erreur, et désormais 0 `info` visé (14 corrigés dans cette clôture :
`const` manquants + `withOpacity` déprécié → `withValues`) - **ce résultat
n'a PAS encore été reconfirmé par une nouvelle exécution réelle** au
moment de la rédaction de ce manifeste ; à vérifier par le prochain
`flutter analyze` sur le poste de l'utilisateur avant de le considérer
comme prouvé, conformément au principe "preuve par exécution" de ce
projet.

## Cahier des charges de référence

**Résolu après la clôture initiale, dans le même cycle R0.2.2** - voir
`docs/SPEC_BASELINE.md`. Le cahier v1.1 a été déposé dans la conversation
le 2026-08-19 ; son SHA-256 a été recalculé indépendamment par ce
développeur (`sha256sum`) et confirmé **identique** au hash cité par
l'équipe (`1c6b3db672d9d622679ecd6c8b20908e575e2702eeb4dcc839609b21ea5ccd1b`).
Les 33 pages ont été lues intégralement ; les clauses citées dans les
retours de recette (endpoint d'historique, chiffrement de sauvegarde,
formulation du Gate R0, R4 intégrité) ont chacune une source exacte
(section/page) désormais consignée dans `SPEC_BASELINE.md`.

## CI GitHub Actions réelle

**Non exécutée** - ce bac à sable n'est pas connecté à un dépôt GitHub
distant ; aucun push n'a été effectué. Le fichier `.github/workflows/ci.yml`
est syntaxiquement valide et désormais aligné sur Flutter 3.47.0, mais son
exécution verte reste à démontrer sur un vrai runner GitHub Actions, par
un push vers un dépôt réel.
