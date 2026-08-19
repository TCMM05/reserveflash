# ADR 0002 - Pivot Local-First : le téléphone est la source de vérité (R0.1)

- Statut : Accepté
- Date : 2026-08-18
- Décideurs : Product Owner (demande corrective écrite, traitée comme
  modification officielle du cahier des charges v1.0)
- Amende : ADR 0001 (voir section "Conséquences sur ADR 0001" ci-dessous)

## Contexte

La baseline R0 (Fondation) a été conçue avec un backend FastAPI comme source
de vérité potentielle des incidents (schéma SQLAlchemy/PostgreSQL,
persistence runtime en mémoire en attendant le branchement Postgres prévu en
R4) et un mobile Flutter agissant principalement comme client de ce backend
(cache local + file de synchronisation, section 8.1).

Le Product Owner a formalisé, par une demande écrite détaillée traitée comme
modification officielle du cahier des charges, un correctif architectural
nommé **R0.1 "Local-First"** avant toute poursuite du développement R1. Les
points clés de cette demande (reproduits intégralement dans l'historique de
la conversation ayant produit cette livraison, résumés ici) :

1. Toutes les données métier (incidents, faits, réserves, preuves, PDF)
   doivent être stockées localement sur le téléphone pour la V1 ; aucune
   dépendance PostgreSQL/Supabase/stockage cloud ne doit être requise pour un
   fonctionnement normal.
2. SQLite/Drift reste la base V1, structurée et versionnée (migrations
   locales) - pas de simple fichier JSON.
3. Chaque preuve (photo, BL, PDF) garde en base au minimum : id, incident
   associé, type de document, date/heure de capture, chemin local, SHA-256,
   statut de disponibilité. Aucune perte de preuve sur coupure réseau ou
   échec IA.
4. Le backend devient minimal et sans état : protéger la clé OpenAI, recevoir
   le strict nécessaire, appeler le provider IA, valider la structure de la
   réponse, renvoyer des `CandidateFacts`. Il ne doit plus être la base
   centrale des incidents.
5. La clé OpenAI ne doit jamais être embarquée dans l'app Flutter (flux
   obligatoire Flutter -> Backend -> OpenAI -> Backend -> Flutter).
6. L'app doit fonctionner intégralement hors ligne (création, saisie, photos,
   audio, consultation, confirmation manuelle, génération de dossier sans
   IA) ; une opération IA nécessitant Internet passe en état `pending`,
   retriable, sans perte.
7. Le pipeline IA -> `CandidateFacts` -> validation utilisateur ->
   `ConfirmedFacts` -> Reserve Composer déterministe -> PDF reste
   intégralement en vigueur (renforce ADR 0001).
8. Correctif de sécurité : un champ confirmé (ex: `packaging_condition`)
   pouvait contenir une attribution de responsabilité et ressortir telle
   quelle dans la réserve - garde-fou déterministe requis avant le Reserve
   Composer, avec tests adversariaux.
9. Fonctionnalité "Exporter mes données / Sauvegarde ReserveFlash" et
   "Importer une sauvegarde", format documenté et versionné, restauration
   testable, stockage géré par l'utilisateur (Drive/OneDrive/local).
10. Le PDF final doit être partageable via le partage natif OS, sans
    dépendre du serveur ReserveFlash.
11. PostgreSQL n'est plus une dépendance runtime obligatoire pour la V1 ; le
    code déjà écrit peut être conservé pour un usage cloud futur mais ne doit
    plus bloquer le démarrage/fonctionnement de l'app.
12. Garder une architecture interfaces/repositories pour permettre d'ajouter
    le cloud plus tard sans réécrire le moteur métier.
13. Pas de création de compte cloud obligatoire pour démarrer un incident en
    V1.
14. Confidentialité par défaut : les dossiers restent sur le téléphone ; ne
    transmettre à l'IA que le strict nécessaire, documenté précisément.

## Décision

**Le téléphone (SQLite/Drift, via `AppDatabase` et `LocalIncidentRepository`,
voir `mobile/lib/data/local/`) devient la source de vérité canonique d'un
dossier ReserveFlash pour la V1.** Le backend cesse d'être un candidat à ce
rôle et devient un service d'IA sans état (voir ADR ci-dessous et
`docs/architecture.md` pour le détail des routes).

Corollaires directement issus de cette décision :

- **Le Reserve Composer tourne désormais sur l'appareil**
  (`mobile/lib/domain/reserve_composer.dart`,
  `mobile/lib/domain/templates/fr_v1.dart`), pour que "générer un dossier à
  partir des données locales quand l'IA n'est pas nécessaire" (point 6) soit
  réellement possible sans réseau. Voir section "Conséquences sur ADR 0001"
  ci-dessous : ceci renverse explicitement une décision prise dans l'ADR
  0001.
- **Le garde-fou anti-attribution de responsabilité**
  (`app/domain/liability_guard.py` côté backend,
  `mobile/lib/domain/liability_guard.dart` côté mobile) s'exécute
  obligatoirement avant toute composition de réserve, dans les deux
  implémentations, en défense en profondeur (correctif point 8).
- **Une file `AiOperationQueue`** (remplace la `SyncOperations` générique de
  R0, voir `mobile/lib/data/local/app_database.dart`) porte uniquement les
  opérations qui nécessitent réellement le réseau : transcription audio,
  extraction depuis photo/document. Toute autre opération (créer un
  incident, confirmer des faits, composer une réserve) est 100% locale et
  synchrone, donc ne peut jamais être bloquée par l'absence de réseau.
- **Le backend garde son schéma PostgreSQL/SQLAlchemy/Alembic** (déjà
  construit et testé en R0) mais celui-ci devient un chemin optionnel/futur
  (multi-appareil, comptes équipe, tableau de bord web - hors scope V1), pas
  un prérequis de démarrage. Voir `docs/architecture.md`, section "V1
  Local-First vs. chemin cloud futur".
- **Architecture ports/adapters côté mobile** :
  `mobile/lib/domain/repositories/incident_repository.dart` définit
  l'interface `IncidentRepository` ; `LocalIncidentRepository` (Drift) est la
  seule implémentation V1. Une future `CloudIncidentRepository` pourra
  implémenter la même interface sans modification des use cases/écrans
  (point 12).
- **Aucune authentification requise pour créer un incident** : les tables
  locales (`LocalIncidents`, etc.) ont un `organizationId` nullable ; le flux
  de création d'incident ne dépend d'aucun appel réseau ni d'aucune session
  (point 13).

## Conséquences sur ADR 0001

ADR 0001 ("GATE zéro invention") énonçait, dans sa section Conséquences :
*"Le mobile ne duplique pas la logique de composition [...] dupliquer
créerait un risque de divergence entre deux implémentations d'un composant
dont l'exigence centrale est justement l'unicité déterministe."*

Cette décision est **explicitement renversée** par R0.1, point 6
("fonctionnement offline" - générer le dossier à partir des données locales
quand l'IA n'est pas nécessaire) : un Reserve Composer qui ne vivrait que
côté backend rendrait cette exigence impossible à tenir dès que l'appareil
est hors ligne, ce qui est le scénario central visé par le pivot Local-First
(un contrôleur qualité en zone d'entrepôt sans réseau fiable, cas d'usage
cité section 1 du cahier des charges).

Le risque de divergence identifié par ADR 0001 reste réel et n'est PAS
éliminé, seulement mitigé :

- Les deux implémentations (`backend/app/domain/reserve_composer.py` /
  `templates/fr_v1.py` et `mobile/lib/domain/reserve_composer.dart` /
  `templates/fr_v1.dart`) portent une docstring/commentaire de tête
  explicite indiquant qu'elles DOIVENT rester alignées et se référençant
  mutuellement.
- Les suites de tests adversariaux (`backend/tests/domain/
  test_reserve_composer.py` + `test_liability_guard.py` côté Python,
  `mobile/test/domain/reserve_composer_test.dart` +
  `liability_guard_test.dart` côté Dart) couvrent les MÊMES scénarios E2E-01
  à E2E-07 et les mêmes catégories de contenu interdit, avec les mêmes
  valeurs d'entrée quand c'est possible (ex: `packaging_condition =
  "transporteur responsable"` testé identiquement des deux côtés).
- **ROADMAP (non fait en R0.1, à faire avant une release publique)** :
  extraire un corpus de vecteurs de test partagés (JSON : faits en entrée +
  texte de réserve attendu + sha256 attendu) rejoué par les deux suites de
  tests, pour transformer la vérification manuelle actuelle ("les deux
  fichiers de test couvrent les mêmes cas, relus par un humain") en garantie
  automatisée d'identité bit-à-bit. Non fait ici car cela nécessite un
  harnais de test cross-langage (générateur JSON commun) hors du périmètre
  temporel de ce correctif ; documenté comme limitation connue (voir
  CHANGELOG.md et le README racine).
- Le backend CONSERVE sa propre implémentation du Reserve Composer : elle
  n'est pas retirée. Elle sert de référence pour la revue de code, de
  filet de sécurité pour un futur mode cloud (point 11/12), et reste
  exercée par les 75 tests backend existants.

## Alternatives rejetées

- **Rendre le réseau obligatoire au démarrage de l'app (mode "toujours en
  ligne")** : rejeté - contredit frontalement le point 6 de la demande et le
  cas d'usage central du produit (terrain/entrepôt, connectivité
  intermittente).
- **Garder le backend comme source de vérité et se contenter d'une cache
  locale plus robuste (retry réseau agressif)** : rejeté - un cache, même
  robuste, ne peut pas garantir "aucune perte de preuve" ni "génération du
  dossier sans IA" si l'app ne peut jamais écrire la donnée canonique tant
  qu'elle n'a pas atteint le serveur ; c'est le problème que ce pivot corrige
  explicitement (bug historique R0 : persistence runtime en mémoire, donc
  perdue au moindre redémarrage du process backend).
- **Faire composer la réserve par un appel HTTP au backend même en mode
  local (queue différée)** : rejeté pour la composition elle-même (seules
  les opérations IA passent en `pending`, jamais la composition
  déterministe) - ce mécanisme de file est retenu uniquement pour les
  opérations qui nécessitent authentiquement un modèle distant
  (transcription/extraction, point 6).
- **Supprimer entièrement le schéma PostgreSQL/SQLAlchemy déjà écrit** :
  rejeté - le point 11 demande explicitement sa conservation en vue d'un
  usage cloud futur (équipes, tableau de bord web) ; le supprimer aurait
  détruit un travail déjà testé sans bénéfice pour la V1 (il ne bloque déjà
  plus rien au runtime une fois ce correctif appliqué).
