# Statut Gate R1 - "Capture Offline"

**Statut : NON VALIDÉ.** Ce document liste les preuves livrées avec la
version candidate R1 et ce qu'il reste à vérifier. Conformément à la
demande corrective ("ne pas déclarer R1 PASS vous-même : livrer les preuves
et laisser la recette indépendante décider"), **aucune section de ce
document n'affirme que le Gate R1 est atteint** - c'est à la recette
indépendante de le constater sur un vrai appareil.

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

## Ce qui N'A PAS encore été fait (honnêteté de livraison)

- **Aucune exécution réelle du SDK Flutter** n'a eu lieu au moment de la
  rédaction de ce document. Ce contexte de développement ne dispose pas du
  SDK Flutter (même limitation que pour R0, déjà documentée à plusieurs
  reprises dans `docs/GATE_R0.1_STATUS.md`) : ni `flutter analyze`, ni
  `flutter test`, ni `flutter build apk --debug` n'ont pu être lancés ici.
  **C'est le prochain bloquant avant toute recette** - voir
  `mobile/README.md`, section "Bootstrap", pour la procédure déjà éprouvée
  sur ce projet (R0.1/R0.2/R0.2.1).
- Aucun APK n'a donc encore été produit pour cette version candidate.
- Aucune capture d'écran ni vidéo du parcours réel n'a pu être produite
  (nécessite l'exécution ci-dessus sur un vrai téléphone).
- La CI GitHub Actions n'a pas encore tourné sur le commit R1 (le commit/
  tag `r1-candidate` n'existe pas encore au moment de la rédaction de ce
  document).

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

## Tests obligatoires R1 - statut

| Test | Statut | Détail |
|---|---|---|
| R1-T01 création d'un incident offline | ✅ Automatisé, non exécuté ici | `r1_capture_offline_test.dart`, groupe R1-T01 |
| R1-T02 fermeture/réouverture → incident retrouvé | ✅ Automatisé, non exécuté ici | groupe R1-T02 |
| R1-T03 preuve photo enregistrée + SHA-256 conservé | ✅ Automatisé, non exécuté ici | groupe R1-T03 |
| R1-T04 plusieurs photos dans le même incident | ✅ Automatisé, non exécuté ici | groupe R1-T04 |
| R1-T05 kill/restart → données intactes | ✅ Automatisé, non exécuté ici | groupe R1-T05 |
| R1-T06 refus permission caméra → aucune perte/crash | 🟡 Manuel requis | code défensif en place (`CameraCapturePage`), non vérifiable par `flutter test` (canal de plateforme réel requis) |
| R1-T07 fichier local manquant/corrompu → UI contrôlée | ✅ Automatisé, non exécuté ici | groupe R1-T07 (missing + corrupted) |
| R1-T08 suppression avec confirmation | ✅ Automatisé (niveau persistance) + 🟡 confirmation UI à vérifier manuellement | groupe R1-T08 ; `rf_confirm_dialog.dart` est un widget partagé, non couvert par un widget test dans ce lot |
| R1-T09 mode avion pendant tout le parcours | 🟡 Manuel requis | aucune dépendance réseau ajoutée par construction (voir CHANGELOG), à confirmer sur appareil réel |
| R1-T10 aucun appel réseau déclenché par la capture locale | ✅ Garanti par construction + documenté | ni `LocalIncidentRepository` ni `EvidenceStorageService` n'importent de client HTTP ; à confirmer aussi en mode avion réel |
| Tests R0 (zéro régression) | ✅ Conservés inchangés | non ré-exécutés ici (même limitation SDK ci-dessus) |

**"Automatisé, non exécuté ici"** signifie : le test est écrit avec la même
rigueur qu'un test qui tournerait réellement (même pattern que
`local_incident_repository_test.dart` en R0.2/R0.2.1, qui s'est révélé
fiable une fois exécuté), mais n'a pas pu être lancé dans ce contexte de
développement faute de SDK Flutter. **Ne pas compter une ligne de ce
tableau comme "PASS" avant exécution réelle avec résultat vert.**

## Prochaines étapes avant recette

1. Exécuter le bootstrap réel (`mobile/README.md`) sur un poste avec SDK
   Flutter : `flutter pub get`, `flutter analyze`, `flutter test`,
   `flutter build apk --debug`.
2. Corriger les éventuelles erreurs réelles révélées (attendu : au moins
   `record` à surveiller en priorité, voir section risque ci-dessus -
   même méthode "vagues" qu'en R0).
3. Installer l'APK sur un vrai téléphone Android, activer le mode avion,
   et dérouler le parcours complet du Gate R1 (cité en tête de ce
   document).
4. Une fois le parcours réussi sans crash ni perte de données : commit,
   tag `r1-candidate`, push, CI GitHub Actions verte, puis livraison
   complète (ZIP, APK, SHA-256, captures d'écran, idéalement vidéo).
5. La décision PASS/FAIL du Gate R1 revient à la recette indépendante, pas
   à ce document ni à son auteur.
