# ADR 0001 - GATE zéro invention : composeur de réserve déterministe séparé du LLM

- Statut : Accepté (amendé par ADR 0002 - voir note ci-dessous)
- Date : 2026-08-18
- Décideurs : Product Manager, Architecte logiciel & IA, Expert IA/Automation
  (comité produit, section 0.1)

> **Note (R0.1)** : la sous-décision "le mobile ne duplique pas la logique
> de composition" (section Conséquences ci-dessous) a été renversée par
> [ADR 0002](0002-local-first-pivot.md) pour permettre la génération de
> dossier hors ligne. Le reste de cet ADR (composeur déterministe, entrée
> strictement typée `ConfirmedFactData`, interdiction du LLM comme auteur du
> texte final) reste intégralement en vigueur, désormais appliqué de façon
> identique dans les deux implémentations (backend ET mobile).

## Contexte

Le retour d'expérience interne DevisGuard (section 0.3, 20.1) montre qu'un
modèle atteignant 94,4 % de recall sur un corpus "CORE" contrôlé est tombé à
25 % sur un corpus "STRESS" (formulations variées, négations, contradictions).
Une bonne performance mesurée sur un périmètre contrôlé ne garantit PAS la
généralisation sémantique. Pour ReserveFlash, le risque est direct : un texte
de réserve halluciné (quantité inventée, gravité exagérée, attribution de
faute) devient une pièce potentiellement produite comme preuve - l'enjeu est
donc plus élevé qu'un simple contenu généré affiché à l'utilisateur.

## Décision

Le texte de réserve n'est jamais produit par un appel LLM. Il est composé par
un module déterministe (`app/domain/reserve_composer.py`) qui :

1. N'accepte en entrée QUE des `ConfirmedFactData` - un type qui ne peut pas
   exister avec `user_confirmed=False` (contrainte au niveau du système de
   types, pas d'une simple convention).
2. N'effectue aucun appel réseau, aucune inférence : uniquement du templating
   Python pur, versionné par langue et type d'incident.
3. Est testé pour le déterminisme strict (même entrée -> même sortie, même
   hash SHA-256) et pour l'absence de vocabulaire interdit (adjectifs de
   gravité non confirmés, attribution de responsabilité, montants).

Le rôle du LLM est strictement borné à la transcription et à l'extraction de
*candidats* (section 7.1), jamais à la décision finale.

## Conséquences

- Le mobile ne duplique pas la logique de composition (voir
  `mobile/README.md`) : dupliquer créerait un risque de divergence entre deux
  implémentations d'un composant dont l'exigence centrale est justement
  l'unicité déterministe.
- Toute nouvelle règle de formulation doit passer par une nouvelle version de
  template (`fr_v2`, ...), jamais par une modification du prompt IA - cela
  garde le domaine (`app/domain/templates/`) auditable indépendamment du
  provider IA.
- Le corpus STRESS (section 15.1, 240 cas) reste nécessaire malgré cette
  architecture : il valide la qualité de l'*extraction candidate*, pas la
  composition (qui est déterministe et donc non sujette à ce risque une fois
  les faits confirmés).

## Alternatives rejetées

- **Laisser le LLM rédiger directement la réserve à partir des faits
  confirmés** : rejeté - même avec des faits confirmés en entrée, un LLM
  génératif reste non déterministe et peut reformuler de façon à introduire
  une nuance de gravité ou une tournure implicitement accusatoire non voulue
  par l'utilisateur.
- **Post-validation du texte LLM par un second modèle ("LLM-as-judge")** :
  rejeté pour la release 1.0 - ajoute de la latence et de la complexité sans
  éliminer le risque de fond (le juge est lui-même un LLM). Reste une piste
  ROADMAP si le besoin de formulations plus riches émerge après retour
  terrain.
