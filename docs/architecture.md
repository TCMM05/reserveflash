# Architecture - ReserveFlash Incident

Ce document explique les frontières entre couches et documente les décisions
structurantes de cette baseline. Il complète, sans le dupliquer, le cahier
des charges (`ReserveFlash_Incident_Cahier_des_Charges_v1.1_LocalFirst.pdf`,
"RÉFÉRENCE CONTRACTUELLE - REMPLACE V1.0" - SHA-256 vérifié dans
`docs/SPEC_BASELINE.md`) et le pivot R0.1 "Local-First" qu'il formalise
(voir `docs/adr/0002-local-first-pivot.md`), qui reste la référence
contractuelle pour le raisonnement de ce pivot (section 20.2 - "Décision de
baseline" du cahier v1.1).

**Cette version du document décrit l'architecture R0.1, mise à jour
R0.2.3** (le pivot architectural R0.1 est inchangé depuis R0.2 ; R0.2.3 ne
change aucun code métier/architectural, uniquement la documentation et la
traçabilité - voir section 7 pour le statut à jour des limitations). Pour
l'historique R0 -> R0.1 -> R0.2 -> R0.2.3, voir `CHANGELOG.md`.

## 1. Vue d'ensemble

```
mobile/   Flutter - SOURCE DE VÉRITÉ V1 (SQLite/Drift local), capture,
          revue des faits, composition de réserve, export, sauvegarde,
          partage - tout le cycle de vie d'un dossier (R0.1)
backend/  FastAPI - proxy IA sans état (/v1/ai/*, rôle primaire V1) +
          chemin CRUD incidents optionnel/futur (/v1/incidents/*, non
          appelé par le mobile V1 ET non monté par défaut depuis R0.2 -
          voir section 3 ci-dessous)
schemas/  Contrats JSON versionnés entre IA <-> domaine (CandidateFactSet,
          ConfirmedFactSet) - partagés par les deux implémentations du
          Reserve Composer (backend ET mobile, voir section 4)
prompts/  Prompts versionnés (à peupler en R2 - IA extraction)
rulepacks/ Règles juridiques versionnées, désactivables par défaut
benchmark/ Corpus CORE/STRESS + scorer (à peupler en R6 - qualification)
infra/    Docker, docker-compose (dev), CI/CD
docs/     Ce document, ADR, runbooks, docs/local_storage_schema.md
scripts/  Utilitaires (ex: backend/scripts/generate_openapi.py)
```

## 2. Règle de dépendance (section 5.3)

> "Les couches doivent dépendre vers le domaine, jamais vers le provider IA.
> Le domaine ne connaît ni OpenAI, ni Supabase, ni Flutter."

Concrètement dans `backend/` :

- `app/domain/` : aucune dépendance vers FastAPI, SQLAlchemy, un SDK IA ou
  storage. Uniquement pydantic (validation) et la bibliothèque standard.
- `app/application/` : orchestration (use cases) + `ports.py` (interfaces
  `AIProvider`, `StorageProvider`, `AuthProvider`, `IncidentRepository`, ...).
  Dépend du domaine, jamais de l'infrastructure concrète.
- `app/infrastructure/` : implémentations concrètes des ports (mocks en R0,
  adapters réels en R2+/R4). C'est la SEULE couche qui peut importer un SDK
  externe.
- `app/api/` : FastAPI, dépend de `application` (use cases) et `domain`
  (types), jamais directement de `infrastructure` (l'injection passe par
  `app/api/deps.py`, qui appelle les factories `app/infrastructure/*/​__init__.py`).

Concrètement dans `mobile/` (R0.1, point 12 de la demande corrective -
"Préparer l'avenir sans complexifier la V1") :

- `lib/domain/` : aucune dépendance Drift/SQLite/HTTP. Contient désormais le
  Reserve Composer local (`reserve_composer.dart`, `templates/fr_v1.dart`),
  le garde-fou (`liability_guard.dart`), les entités, et l'interface
  `repositories/incident_repository.dart`.
- `lib/data/local/` : SEULE implémentation V1 de `IncidentRepository`
  (`LocalIncidentRepository`, backée par Drift/`AppDatabase`). Une future
  `CloudIncidentRepository` (hors scope V1) implémenterait la même interface
  sans modifier `lib/domain/` ni les écrans.
- `lib/data/backup/`, `lib/data/share/` : services d'infrastructure
  (fichiers, partage OS) - dépendent de `lib/data/local/` et `lib/domain/`,
  jamais l'inverse.
- `lib/features/*/presentation/` : dépend du domaine et des repositories,
  jamais l'inverse.

## 3. Pivot Local-First (R0.1) - qui fait autorité sur quoi

Voir `docs/adr/0002-local-first-pivot.md` pour la décision complète. Résumé
opérationnel :

| Donnée | Source de vérité V1 | Le backend la voit-il ? |
|---|---|---|
| Incident, anomalies, faits confirmés, réserve composée | `mobile/lib/data/local/app_database.dart` (Drift/SQLite) | Jamais |
| Photos, BL, PDF exportés | Filesystem privé de l'app (chemin dans `LocalEvidenceAssets`) | Jamais |
| Extrait audio à transcrire | Envoyé une fois à `POST /v1/ai/transcribe`, jamais persisté côté serveur | Oui, le temps d'un appel HTTP |
| Texte à structurer (déjà transcrit/OCRisé) | Envoyé une fois à `POST /v1/ai/extract`, jamais persisté côté serveur | Oui, le temps d'un appel HTTP |
| Sauvegarde utilisateur (export/import) | Fichier `.rfbackup` géré par l'utilisateur (Drive/OneDrive/local) | Jamais |

`backend/app/api/routes/incidents.py` (CRUD incidents complet, hérité de R0)
reste dans le dépôt et reste testé, mais N'EST PAS appelé par l'app mobile
V1 - c'est un chemin optionnel conservé pour un usage cloud futur (point 11 :
multi-appareil, comptes équipe, tableau de bord web), explicitement hors
scope V1. Voir la docstring de ce fichier.

## 4. GATE zéro invention (section 2.4) - comment il est *appliqué*, pas
   seulement documenté

Le risque identifié en section 0.3 (leçon DevisGuard) est qu'une "bonne
performance sur un périmètre contrôlé" masque une génération de texte non
fiable. Cette baseline traite ça comme une contrainte de *typage*, pas
seulement de discipline d'équipe - désormais identiquement des deux côtés
(backend ET mobile, depuis R0.1) :

1. `ConfirmedFactData` (Python : `app/domain/fact_set.py` ; Dart :
   `lib/domain/fact_set/confirmed_fact_data.dart`) ne peut PAS être construit
   sans confirmation explicite - `UnconfirmedFactSetError`/invariant de type
   lève avant même que l'objet existe.
2. **(R0.1, correctif point 8)** `ConfirmedFactData` confirmé ne suffit plus
   à garantir un contenu acceptable dans une réserve : un champ texte libre
   (`packaging_condition`, `product_condition`, ...) peut contenir une
   attribution de responsabilité, une promesse d'indemnisation, une
   conclusion/qualification juridique ou un montant inventé.
   `liability_guard.dart`/`liability_guard.py` filtrent ce contenu
   DÉTERMINISTIQUEMENT, à deux endroits : dès la confirmation (retour
   immédiat utilisateur) ET juste avant `compose_reserve()`/`composeReserve()`
   (défense en profondeur - aucun appelant ne peut l'oublier). Voir
   `docs/adr/0002-local-first-pivot.md` et les tests adversariaux
   `test_liability_guard.py`/`liability_guard_test.dart` (rejouent
   explicitement `packaging_condition = "transporteur responsable"`, le cas
   cité dans la demande corrective).
3. `reserve_composer.py`/`reserve_composer.dart::compose_reserve()`
   n'acceptent QUE des `ConfirmedFactData` en entrée - aucune String libre,
   aucune sortie LLM brute. Signature vérifiée explicitement par
   `tests/domain/test_reserve_composer.py::test_zero_unconfirmed_fact_in_final_reserve_gate`.
4. `templates/fr_v1.py`/`fr_v1.dart` ne contiennent aucun appel réseau,
   aucun import IA : templating pur, déterministe (même entrée = même
   sortie, vérifié par hash SHA-256 des deux côtés).
5. Le pipeline IA (`AIProvider`, `app/api/routes/ai.py`) ne peut produire
   qu'un `CandidateFactData` (schema séparé, `requires_review` obligatoire) -
   il n'existe littéralement aucune fonction dans le code qui convertit un
   `CandidateFactData` en `ConfirmedFactData` sans passer par l'acte de
   confirmation utilisateur (F09, `LocalIncidentRepository.confirmFacts` côté
   mobile - c'est désormais un acte 100% local, pas un appel réseau).

## 5. Pourquoi le Reserve Composer existe maintenant à DEUX endroits

Ce choix a changé en R0.1 (auparavant : un seul endroit, côté backend). Voir
`docs/adr/0002-local-first-pivot.md`, section "Conséquences sur ADR 0001",
pour le raisonnement complet (nécessité du fonctionnement offline, point 6)
et la mitigation du risque de divergence entre les deux implémentations
(tests adversariaux miroirs, ROADMAP d'un corpus de vecteurs de test
partagé).

## 6. Stockage local - voir docs/local_storage_schema.md

Le schéma Drift complet (9 tables), le format de sauvegarde
`reserveflash_backup.v1`, et la stratégie de migration de schéma (v1 -> v2)
sont documentés séparément dans `docs/local_storage_schema.md` (point 16 de
la demande corrective - "schéma de stockage local" explicitement requis dans
la livraison).

## 7. Limitations connues de cette baseline (mise à jour R0.2.3)

Documentées ici pour éviter toute ambiguïté lors de la recette (section 16
du cahier des charges). Les limitations #1 et #6 ci-dessous, actives lors
des livraisons R0/R0.1/R0.2, sont **résolues depuis R0.2.1/R0.2.2** (preuve
par exécution réelle - voir `docs/GATE_R0.1_STATUS.md` et `CHANGELOG.md`) et
conservées ici seulement pour l'historique de la recette :

| # | Limitation | Périmètre prévu pour la résoudre |
|---|---|---|
| 1 | ~~Le mobile Flutter n'a pas pu être compilé/analysé/testé~~ **RÉSOLU (R0.2.1, reconfirmé R0.2.2)** : `flutter analyze` 0 erreur/0 info, 52/52 tests passés, APK debug construit - exécution réelle sur le poste de l'utilisateur. La CI (`.github/workflows/ci.yml`, job `mobile`) a également tourné avec succès sur un vrai runner GitHub Actions (R0.2.2). | Fait |
| 2 | La duplication Backend/Mobile du Reserve Composer n'est vérifiée identique que par lecture humaine des deux suites de tests (mêmes scénarios E2E-01 à E2E-07, mêmes cas adversariaux) - pas encore par un corpus de vecteurs de test partagé rejouable automatiquement des deux côtés. | ROADMAP, voir ADR 0002 |
| 3 | `generate_export`/l'écran S13 produisent un document placeholder, pas encore un vrai PDF avec mise en page, chronologie et preuves intégrées. | R3 - Composer & dossier |
| 4 | Le pipeline IA réel (OpenAI) n'est pas implémenté : `build_ai_provider` lève `NotImplementedError` si `RESERVEFLASH_AI_PROVIDER=openai`. Seul le mock déterministe existe (branché aux deux routes `/v1/ai/*`). | R2 - IA extraction |
| 5 | Aucun rule pack n'est actif (comportement voulu, pas une limitation - voir section 11.3 et `rulepacks/README.md`). | N/A - conforme au cahier des charges |
| 6 | ~~`LocalIncidentRepository` n'a pas de test d'intégration exécuté~~ **RÉSOLU (R0.2.1)** : `mobile/test/data/local_incident_repository_test.dart` exécuté et vert sur une vraie base SQLite fichier (créer→fermer→rouvrir→retrouver). | Fait |
| 7 | L'écran de restauration de sauvegarde (import) et l'écran d'export ne sont pas encore câblés dans l'UI (`BackupService` existe et est testé structurellement, mais aucun écran S01-S20 ne l'appelle encore). | R1/R3 - à cabler avec les écrans de compte/historique |
| 8 | Le backend conserve `app/infrastructure/db/models.py` + Alembic (schéma PostgreSQL complet, testé contre un vrai PostgreSQL) comme chemin optionnel/futur, non branché au runtime - voir section 3 ci-dessus. | Post-V1, si un besoin cloud est confirmé |
| 9 | **iOS - réserve future explicite, non bloquante pour R0** : jamais construit ni testé (nécessite un poste macOS/Xcode, indisponible dans ce contexte). Android est entièrement prouvé par exécution réelle. | À prouver par un développeur équipé macOS avant toute release iOS |
| 10 | Le backup export/import n'est pas encore chiffré (intégrité SHA-256 + refus d'archive corrompue faits en R0.2 ; chiffrement pas fait) - voir `docs/security.md` SEC-09. Ne pas déclarer conforme R4. | R4 - Backup & intégrité |

## 8. Ce qui N'A PAS changé depuis R0 (pour éviter toute confusion)

- La machine à états `IncidentStatus` (section 2.2) et son graphe de
  transitions - identiques des deux côtés, inchangés.
- Les schémas JSON versionnés (`schemas/*.schema.json`) - `ConfirmedFactData`
  a le même contrat, avec en plus le filtrage `liability_guard` appliqué
  avant toute composition.
- Le rule pack (`rulepacks/`) - toujours désactivé par défaut, inchangé.
- La CI (lint, tests, secret scan) - étendue (nouveaux tests, nouveau job
  `flutter build apk --debug`), pas remplacée.
