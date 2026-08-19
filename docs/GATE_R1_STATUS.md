# Statut Gate R1 - "Capture Offline"

**Statut : CORRECTION VÉRIFIÉE PAR EXÉCUTION RÉELLE SUR DEUX ENVIRONNEMENTS
INDÉPENDANTS** (poste Windows de l'utilisateur : `flutter analyze`/
`flutter test`/`flutter build apk --debug` tous verts ; CI GitHub Actions,
run #8, commit `a6d0b34` : 4 jobs verts, 7m54s) **- IL NE RESTE QU'UNE
NOUVELLE RECETTE TERRAIN MANUELLE SUR APPAREIL AVANT TOUT NOUVEAU TAG.** La
recette terrain indépendante avait trouvé un défaut réel lors du parcours
manuel décrit plus bas : les photos et la note vocale capturées n'étaient
pas consultables/écoutables depuis l'app une fois enregistrées. Voir la
section "Correction ciblée post-recette terrain (photo/audio)" ci-dessous
pour le détail complet, y compris plusieurs bugs réels (tests, pas
fonctionnalité) trouvés et corrigés uniquement grâce à cette exécution
réelle - exactement la même rigueur que le reste de R1 initial (voir la
section "Exécution réelle" plus bas). Le tag `r1-candidate` existant
correspond au commit D'AVANT ce correctif - **ne pas le considérer comme
à jour.** Il reste : une nouvelle recette terrain manuelle sur appareil
ciblée spécifiquement sur le correctif photo/audio - la recette
indépendante précédente (parcours métier/offline) **ne couvre PAS encore
ce correctif**, confirmé explicitement par l'utilisateur. Conformément à
la demande corrective ("ne pas déclarer R1 PASS vous-même : livrer les
preuves et laisser la recette indépendante décider"), **aucune section de
ce document n'affirme que le Gate R1 est validé.**

## Rappel du Gate R1 (critère d'acceptation, verbatim de la demande)

> "R1 ne sera validée que si : un utilisateur peut installer l'APK sur un
> vrai téléphone Android, activer le mode avion, créer un incident, prendre
> un vrai BL en photo, prendre plusieurs photos d'un dommage, saisir une
> description, fermer complètement l'application, la rouvrir et retrouver
> le dossier et tous ses fichiers intacts. Aucun crash critique, aucune
> perte de données et aucune dépendance Internet sur ce parcours."

Ce critère est un parcours **manuel sur appareil réel** : aucun test
automatisé ne peut, à lui seul, le valider (voir tableau des tests
ci-dessous, notamment R1-T06/T09).

## Ce qui a été livré dans cette version candidate

Voir `CHANGELOG.md` (entrée `[0.2.0]`) pour le détail fichier par fichier.
En résumé :

- Toutes les fonctionnalités obligatoires 1 à 10 de la demande corrective
  ont une implémentation réelle (code écrit, revu ligne à ligne contre le
  schéma Drift et les patterns déjà prouvés en R0) : création d'incident,
  capture BL, sélection de type(s) de problème, capture guidée de preuves,
  note texte + audio best-effort, détail/reprise d'incident, suppression/
  correction avec confirmation, fonctionnement 100% offline (aucune
  dépendance réseau ajoutée), résilience aux interruptions (écriture
  atomique, transactions), permissions demandées au point d'usage.
- Un nouveau fichier de tests automatisés
  (`mobile/test/data/r1_capture_offline_test.dart`) exerçant réellement
  Drift/SQLite sur fichier et le vrai système de fichiers (jamais de mock
  mémoire), couvrant R1-T01/T02/T03/T04/T05/T07/T08.
- Tous les tests R0 existants sont conservés inchangés.

## Exécution réelle - mise à jour (bootstrap effectué)

Contrairement à la première version de ce document (rédigée avant tout
bootstrap réel, section historique conservée ci-dessous par transparence),
le bootstrap complet a maintenant été exécuté RÉELLEMENT, à deux reprises
indépendantes : sur le poste Windows de l'utilisateur, puis confirmé par
la CI GitHub Actions sur un runner Ubuntu propre (donc sur deux
environnements différents, ce qui renforce la preuve).

- **`flutter analyze`** : **0 erreur, 0 info.** (Deux bugs réels trouvés et
  corrigés au premier passage : import manquant de `LazyDatabase` -
  `package:drift/drift.dart`, pas `package:drift/native.dart` ; et un lint
  `prefer_const_constructors`. Voir commit `cd1be3b`.)
- **`flutter test`** : **61/61 tests verts**, y compris l'intégralité de
  `test/data/r1_capture_offline_test.dart` (R1-T01/T02/T03/T04/T05/T07/T08)
  et tous les tests R0 existants (zéro régression confirmée par exécution,
  pas seulement par lecture de code).
- **`flutter build apk --debug`** : **réussi.** APK produit :
  `app-debug.apk`, 185 591 137 octets, SHA-256
  `f353d6e1cc2e8c751574769f19d789274c22747d7aadf68cd8df2a79f9f7dea5`.
  - Bug réel trouvé et corrigé au passage : "Build failed due to use of
    deleted Android v1 embedding" - causé par un dossier `android/`
    incomplet sur le poste de l'utilisateur (`AndroidManifest.xml` et
    `MainActivity` absents, seuls les deux fichiers Gradle corrigés en
    R0.2 étaient présents/committés). Corrigé par `flutter create .
    --org com.reserveflash --platforms=android,ios` suivi d'une
    restauration ciblée des deux fichiers Gradle protégés
    (`git checkout -- android/app/build.gradle.kts
    android/build.gradle.kts`) pour ne pas perdre le correctif CameraX de
    R0.2 - vérifié : ces deux fichiers n'ont d'ailleurs pas été touchés
    par `flutter create .` cette fois (déjà présents).
  - Risque documenté du plugin `record: ^7.1.1` (voir section dédiée
    ci-dessous) : **ne s'est PAS matérialisé** - compile et build sans
    erreur liée à `record` sur les deux environnements testés.
- **CI GitHub Actions** : **verte, deux fois de suite**, sur un runner
  propre (donc indépendamment du poste Windows de l'utilisateur) :
  - Run CI #5, commit `cd1be3b` ("R1 hotfix... import LazyDatabase
    manquant + lint const") : vert, 8m11s.
  - Run CI #6, commit `e18980c` ("R1 bootstrap reel : exclusions analyzer
    plateforme + pubspec.lock/.metadata regeneres") : vert, 7m47s.

## Parcours manuel réel sur appareil Android - preuve obtenue

Le parcours manuel décrit dans le rappel du Gate R1 (en tête de ce
document) a été exécuté **réellement, sur un vrai téléphone Android**
(Samsung Galaxy A51, modèle `SM-A515F`, connecté en USB, `flutter run` en
mode debug puis vérifié aussi via lancement normal par l'icône - APK
installé, pas une simulation), avec le mode avion activé pendant tout le
parcours de capture. Captures d'écran collectées à chaque étape.

Déroulé confirmé, dans l'ordre :

1. **Accueil → Nouvelle réception problématique** : ouverture normale,
   formulaire "Nouvel incident" (Fournisseur/Transporteur optionnels).
2. **Photo du bon de livraison** : permission caméra demandée au point
   d'usage, autorisée, vraie photo prise avec l'appareil photo du
   téléphone (pas un simulateur), enregistrée avec vignette visible.
3. **Type(s) de problème** : sélection ("Emballage endommagé") confirmée.
4. **3 photos de preuves guidées** : prises et enregistrées, vignettes
   visibles dans le dossier.
5. **Description texte + note vocale** : commentaire texte saisi et
   conservé ; note vocale enregistrée et listée dans les preuves du
   dossier ("Enregistrée sur cet appareil") - le risque documenté sur
   `record: ^7.1.1` (voir section dédiée ci-dessous) ne s'est pas
   matérialisé, y compris à l'usage réel.
6. **Dossier terminé** : écran de confirmation "Dossier enregistré -
   Toutes les informations et preuves sont sauvegardées sur cet appareil,
   sans connexion requise. Vous pouvez fermer l'application en toute
   sécurité : le dossier sera intact à la réouverture."
7. **Fermeture complète + réouverture (R1-T02/R1-T05, mode avion actif)** :
   application totalement fermée (balayée hors des apps récentes) puis
   rouverte par l'icône. Le dossier est retrouvé identique : BL, 3 photos
   de preuves, note vocale, commentaire, type de problème - toutes les
   vignettes s'affichent correctement, aucune perte, aucun crash.
8. **Refus de permission caméra (R1-T06)** : sur un nouvel incident, la
   permission caméra a été explicitement refusée. L'app affiche un écran
   contrôlé : "L'accès à la caméra a été refusé. Vous pouvez l'autoriser
   dans les réglages de l'appareil, ou revenir en arrière : aucune donnée
   n'est perdue.", avec boutons "Ouvrir les réglages"/"Retour" - aucun
   crash, aucune perte de dossier.
9. **Suppression avec confirmation** : la suppression déclenche une popup
   explicite ("Supprimer tout le dossier ? Toutes les informations,
   photos et notes de ce dossier seront supprimées définitivement de cet
   appareil.") avec boutons Annuler/Supprimer le dossier - rien n'est
   supprimé sans confirmation active.
10. **Correction des informations** : formulaire d'édition (Fournisseur/
    Transporteur/Référence BL/Commentaire) fonctionnel, avec bouton
    Enregistrer.
11. **Mode avion (R1-T09) / aucun appel réseau (R1-T10)** : le mode avion
    est resté actif (icône visible dans la barre système sur toutes les
    captures) pendant l'intégralité du parcours ci-dessus, sans aucune
    dépendance réseau observée ni requise.

**Note de transparence sur le déroulé du diagnostic** : avant d'obtenir ce
résultat, deux problèmes d'environnement (pas de bug applicatif) ont
retardé le diagnostic et méritent d'être consignés : (1) une confusion
entre deux copies du dépôt sur le poste utilisateur - une copie non
suivie par git, contenant encore d'anciens écrans stub R0, a été testée
par erreur avant qu'on identifie le bon dépôt git (`reserveflash-git`),
et (2) la gestion de batterie Samsung (mode "Optimisé"/veille des apps
récemment installées) retardait le premier lancement à froid par l'icône
au point de sembler bloqué sur l'écran de démarrage - résolu en passant
l'app en "Non restreint" dans les réglages de batterie. Aucun des deux
points n'est un défaut du code livré ; ils sont documentés ici par souci
de traçabilité complète du parcours de validation.

Le tag `r1-candidate` a été créé sur le commit qui inclut cette mise à jour
documentaire (voir `git log`/`git tag -n1 r1-candidate`).

## Risque explicitement documenté : capture audio locale (`record`)

Conformément à l'instruction : *"Si l'intégration audio ajoute un risque
important au Gate R1, documenter clairement le point mais ne pas
compromettre caméra, fichiers et persistance."*

- `record: ^7.1.1` est le **seul nouveau plugin natif** ajouté en R1 (voir
  `mobile/pubspec.yaml`, commentaire détaillé à cette entrée). Un ajout de
  plugin natif similaire (`record: ^5.1.2`) avait déjà causé un échec réel
  de build en R0.2 (incompatibilité `record_linux`/
  `record_platform_interface`, voir `CHANGELOG.md` historique) - c'est donc
  un point de vigilance connu de ce projet, pas une hypothèse abstraite.
- La version 7.1.1 a été choisie après recherche du changelog officiel
  (pub.dev), pour son alignement avec le toolchain déjà prouvé de ce projet
  (AGP 9.x/Kotlin Gradle DSL, Flutter 3.47.0/Dart 3.13.0) - mais cela reste
  une analyse, pas une exécution réelle.
- **Isolation du risque, telle que codée** :
  `lib/features/voice_description/presentation/voice_description_screen.dart`
  encapsule TOUT usage de `record` dans des blocs `try/catch` complets. Si
  l'enregistrement audio échoue à l'exécution (permission refusée, plugin
  indisponible, erreur native quelconque), l'écran désactive uniquement la
  fonctionnalité audio pour la session et affiche un message - la saisie
  texte, la caméra (BL et preuves) et la persistance Drift ne sont
  JAMAIS affectées par cette branche de code (aucune dépendance croisée).
- **Si le premier `flutter build apk --debug` réel échoue à cause de
  `record`** : l'action recommandée est de retirer temporairement cette
  dépendance (comme cela avait déjà été fait proprement en R0.2, avec le
  même commentaire de traçabilité) et de livrer une R1 sans note vocale
  automatique (la saisie texte manuelle couvre alors seule le point 5),
  sans que cela ne remette en cause le reste du Gate R1 (caméra, fichiers,
  persistance restent intacts par construction - ce sont des chemins de
  code indépendants).

## Correction ciblée post-recette terrain (photo/audio) - vérifiée par exécution réelle (poste utilisateur)

La recette terrain indépendante, en déroulant le parcours réel sur le
Samsung Galaxy A51 (voir section ci-dessus), a signalé : *"une fois les
photos et l'audio enregistrés dans le dossier, je ne peux pas les lire, les
ouvrir ni écouter l'audio."* Vérification faite dans le code : exact -
`EvidenceThumbnailTile` (utilisé par S06/S09/S10/S17) n'avait aucun `onTap`,
et aucun lecteur audio n'existait dans le projet (`pubspec.yaml` ne
contenait que `record`, pour l'enregistrement, jamais un package de
lecture). Ce n'était ni une perte de données ni un crash (les fichiers sont
bien écrits et intègres, SHA-256 vérifié), mais un vrai trou d'usage.

**Correctif demandé et livré ici** (périmètre strictement limité à ce
point, sans toucher Drift, l'architecture Local-First ni le backend, comme
demandé) :

- **Photo/BL** : `EvidencePhotoViewerScreen` (nouveau) - plein écran,
  zoom/pan (`InteractiveViewer`), bouton retour explicite, reprendre
  (recapture avec remplacement explicite ancien->nouveau, jamais d'état où
  le dossier n'aurait ni l'un ni l'autre) et supprimer (avec confirmation
  partagée `rf_confirm_dialog.dart`), état contrôlé "introuvable"/
  "corrompu" si le fichier est manquant ou illisible (jamais de crash,
  même invariant que R1-T07 initial). Ouverte au tap de toute vignette
  photo/BL depuis S06/S09/S17.
- **Audio** : `EvidenceAudioPlayerScreen` (nouveau) - lecture/pause,
  durée/progression (`Slider` + affichage `mm:ss`), arrêter/recommencer
  (retour au début), supprimer, état contrôlé "introuvable"/"corrompu" sans
  même tenter d'ouvrir le lecteur natif dans ce cas. Ouverte au tap de la
  note vocale depuis S10/S17.
- **Timer d'enregistrement** : `voice_description_screen.dart` affiche
  désormais un chronomètre "Enregistrement en cours : mm:ss" pendant la
  capture (absent avant ce correctif).
- **Nouveau plugin natif** : `just_audio: ^0.10.6` (lecture locale
  uniquement - jamais de source réseau/streaming). Choisi après recherche
  du changelog officiel (pub.dev) : la 0.10.6 ("Support AGP 9" + migration
  des fichiers de build Android vers `.kts`) est explicitement alignée sur
  le même toolchain déjà prouvé pour `record` (AGP 9.x/Kotlin Gradle DSL,
  Flutter 3.47.0/Dart 3.13.0). **C'est, comme `record` l'avait été pour R1
  initial, le point de risque de build le plus élevé de ce correctif - à
  vérifier en priorité lors du prochain `flutter pub get`/`flutter build
  apk --debug` réel.**

**Tests ajoutés** (`mobile/test/features/evidence_viewer_test.dart`) -
**exécutés réellement sur le poste de l'utilisateur, tous verts** :

- formatage `mm:ss` (fonction pure, testée directement).
- photo disponible → tap sur la vignette ouvre bien la visionneuse plein
  écran.
- photo → reste consultable (fichier + métadonnées) après fermeture/
  réouverture d'une seconde connexion base (équivalent réel R1-T02/T05).
- photo manquante / corrompue → message contrôlé, aucune exception levée.
- suppression depuis la visionneuse → retire réellement le fichier et la
  métadonnée.
- **Lecture audio réelle NON testée automatiquement** : `just_audio`
  n'a, comme `record`/`camera`, aucun canal de plateforme disponible en
  `flutter test` pur - le comportement complet de
  `EvidenceAudioPlayerScreen` (lecture/pause, fichier manquant/corrompu,
  suppression) reste **manuel requis sur un vrai appareil**, à vérifier
  lors de la prochaine recette terrain.

**Exécution réelle obtenue (poste Windows de l'utilisateur)** :

- **`flutter analyze`** : **0 erreur, 0 info.** (Un bug réel trouvé et
  corrigé au premier passage : `evidence_viewer_test.dart` important
  seulement `evidence_asset.dart as domain` sans importer séparément
  `incident.dart as domain`, qui définit la classe `Incident` -
  `undefined_class` sur les 4 usages. Corrigé par l'ajout de l'import
  manquant, même convention que le reste du projet.)
- **`flutter test`** : **67/67 tests verts**, y compris les 6 tests du
  nouveau fichier `evidence_viewer_test.dart`, et zéro régression sur les
  61 tests R0/R1 déjà verts. Deux bugs réels trouvés et corrigés
  uniquement grâce à cette exécution réelle (aucun n'aurait été détecté
  par simple relecture de code) :
  - Les tests impliquant `Image.file` (photo réelle sur disque) restaient
    bloqués indéfiniment : à l'intérieur d'un `testWidgets()`, tout appel
    dart:io réellement asynchrone doit être exécuté via
    `tester.runAsync()` - y compris AVANT le premier `pumpWidget`, ce que
    la documentation officielle ne précise pas explicitement pour ce cas.
    Diagnostiqué par une trace disque synchrone (indépendante du testeur)
    qui a localisé précisément l'opération bloquante.
  - Le test de suppression restait bloqué (`pumpAndSettle timed out`) : un
    aller-retour unique `runAsync`/`pumpAndSettle` de 50ms ne suffisait
    pas pour une suppression réelle (fichier + base) déclenchée depuis
    l'écran lui-même. Corrigé par une boucle de plusieurs petits
    aller-retours temps réel/temps simulé, plus robuste qu'un délai fixe.
- **`flutter build apk --debug`** : **réussi.** `just_audio: ^0.10.6` (le
  seul nouveau plugin natif de ce correctif, point de risque le plus élevé
  identifié à l'avance) s'intègre sans erreur au toolchain du projet
  (Gradle 9.3.1/AGP 9.x) - le risque documenté ne s'est pas matérialisé,
  même constat que pour `record` en R1 initial.

**CI GitHub Actions** : ~~à confirmer~~ **FAIT** - run #8, commit
`a6d0b34` ("docs(R1): consigner la vérification réelle du correctif
photo/audio"), 4 jobs verts (Backend, Mobile analyze/test/build debug,
Secret scan, Build staging image), 7m54s. Deuxième environnement
indépendant confirmé (runner GitHub Ubuntu propre), même preuve à deux
environnements que pour R1 initial.

**Reste à faire avant tout nouveau tag** : réinstaller l'APK et
reconfirmer manuellement sur un vrai téléphone : ouverture plein écran
d'une photo, lecture/pause d'une note vocale, suppression/reprise, mode
avion. Comme pour R1 initial, aucun verdict PASS n'est déclaré ici avant
cette dernière étape - la recette terrain indépendante précédente ne
couvre pas ce correctif (confirmé explicitement).

## Tests obligatoires R1 - statut

| Test | Statut | Détail |
|---|---|---|
| R1-T01 création d'un incident offline | ✅ Exécuté réellement, vert | `r1_capture_offline_test.dart`, groupe R1-T01 - `flutter test` réel (poste utilisateur + CI) |
| R1-T02 fermeture/réouverture → incident retrouvé | ✅ Exécuté réellement, vert | groupe R1-T02 |
| R1-T03 preuve photo enregistrée + SHA-256 conservé | ✅ Exécuté réellement, vert | groupe R1-T03 |
| R1-T04 plusieurs photos dans le même incident | ✅ Exécuté réellement, vert | groupe R1-T04 |
| R1-T05 kill/restart → données intactes | ✅ Exécuté réellement, vert | groupe R1-T05 |
| R1-T06 refus permission caméra → aucune perte/crash | ✅ Exécuté réellement, vert | code défensif (`CameraCapturePage`) confirmé sur appareil réel (Samsung Galaxy A51) : écran de refus contrôlé affiché, aucun crash, aucune perte de dossier - voir "Parcours manuel réel" ci-dessus |
| R1-T07 fichier local manquant/corrompu → UI contrôlée | ✅ Exécuté réellement, vert | groupe R1-T07 (missing + corrupted) |
| R1-T08 suppression avec confirmation | ✅ Exécuté réellement, vert (persistance + confirmation UI) | groupe R1-T08 (persistance) + dialogue `rf_confirm_dialog.dart` ("Supprimer tout le dossier ?", boutons Annuler/Supprimer le dossier) confirmé affiché sur appareil réel - voir "Parcours manuel réel" ci-dessus |
| R1-T09 mode avion pendant tout le parcours | ✅ Exécuté réellement, vert | parcours complet (création → BL → type de problème → preuves → description/vocal → clôture → fermeture/réouverture) déroulé de bout en bout en mode avion actif sur appareil réel, aucune erreur réseau, aucune donnée perdue - voir "Parcours manuel réel" ci-dessus |
| R1-T10 aucun appel réseau déclenché par la capture locale | ✅ Garanti par construction + confirmé en usage réel | ni `LocalIncidentRepository` ni `EvidenceStorageService` n'importent de client HTTP ; confirmé aussi par l'usage réel en mode avion (R1-T09 ci-dessus) |
| Tests R0 (zéro régression) | ✅ Exécutés réellement, tous verts | 61/61 tests, poste utilisateur ET CI GitHub Actions (2 environnements) |

**"Exécuté réellement, vert"** signifie : soit lancé pour de vrai via
`flutter test` sur le poste Windows de l'utilisateur ET confirmé
indépendamment par la CI GitHub Actions sur un runner Ubuntu propre (CI
#5/#6, voir section "Exécution réelle" ci-dessus), soit - pour R1-T06,
R1-T08 (volet UI) et R1-T09, qui nécessitent un vrai canal de plateforme
(permission système, radio réseau) qu'aucun test automatisé ne peut
simuler fidèlement - déroulé manuellement sur un vrai téléphone Android en
conditions réelles (voir "Parcours manuel réel sur appareil Android" plus
haut). Dans les deux cas, il ne s'agit pas d'une simple lecture de code.
Ces constats manuels restent des observations rapportées par l'utilisateur
testeur, pas une validation formelle du Gate R1 - cette dernière revient à
la recette indépendante (voir section suivante).

## Prochaines étapes avant recette

1. ~~Exécuter le bootstrap réel~~ **FAIT** - `flutter analyze` (0/0),
   `flutter test` (61/61), `flutter build apk --debug` (réussi), sur le
   poste utilisateur ET en CI GitHub Actions (voir ci-dessus).
2. ~~Corriger les éventuelles erreurs réelles révélées~~ **FAIT** - 3 bugs
   réels trouvés et corrigés (import `LazyDatabase`, lint const, dossier
   `android/` incomplet) ; `record` n'a posé aucun problème.
3. ~~Installer l'APK sur un vrai téléphone Android, activer le mode avion,
   et dérouler le parcours complet du Gate R1~~ **FAIT** - déroulé sur un
   Samsung Galaxy A51 (SM-A515F), mode avion actif, voir "Parcours manuel
   réel sur appareil Android - preuve obtenue" ci-dessus pour le détail
   point par point (création d'incident, photo BL, type de problème,
   photos de preuve, description texte + vocale, clôture du dossier,
   fermeture/réouverture avec persistance intacte, refus de permission
   caméra géré sans crash, suppression avec confirmation, correction des
   informations).
4. ~~Tag `r1-candidate`~~ **FAIT** (mais désormais dépassé par le correctif
   ci-dessus - voir point 6).
5. La décision PASS/FAIL du Gate R1 revient à la recette indépendante, pas
   à ce document ni à son auteur - ce document se limite à livrer les
   preuves ci-dessus.
6. ~~Correction ciblée post-recette terrain (visionneuse photo + lecteur
   audio)~~ **BOOTSTRAP RÉEL + CI FAITS** : `flutter analyze` (0/0),
   `flutter test` (67/67), `flutter build apk --debug` (réussi) sur le
   poste de l'utilisateur, ET CI GitHub Actions verte (run #8, commit
   `a6d0b34`, 4 jobs, 7m54s) - voir section dédiée ci-dessus pour le détail
   des bugs réels trouvés et corrigés au passage. **Reste à faire** : une
   nouvelle recette terrain manuelle ciblée sur : ouverture plein écran
   d'une photo, lecture/pause d'une note vocale, suppression/reprise, mode
   avion. Ce n'est qu'une fois cette recette terrain confirmée que la
   livraison complète (ZIP, APK, SHA-256, captures d'écran, `CHANGELOG.md`,
   ce document) et un nouveau tag pourront être préparés.
