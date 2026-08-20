import '../fact_set/candidate_fact_data.dart';

/// Une extraction candidate du pipeline IA pour une anomalie donnée -
/// pendant candidat de `ConfirmedFactSet`
/// (`lib/domain/entities/confirmed_fact_set.dart`), miroir mobile de
/// `backend/app/domain/entities.py`.
///
/// EN ATTENTE de revue utilisateur (écran F09/S11) : ne doit JAMAIS être lue
/// par `lib/domain/reserve_composer.dart` (GATE zéro invention, section
/// 2.4) - seule `ConfirmedFactSet`, obtenue après confirmation explicite,
/// peut alimenter le composeur de réserve. Contrairement à
/// `ConfirmedFactSet`, il n'existe pas de notion de `revision` numérotée :
/// une nouvelle extraction (nouvelle photo, nouvel enregistrement) crée
/// simplement une nouvelle ligne plus récente (`createdAt`), l'historique
/// n'ayant pas la même portée contractuelle qu'une confirmation.
final class CandidateFactSet {
  const CandidateFactSet({
    required this.id,
    required this.issueId,
    required this.schemaVersion,
    required this.candidateData,
    required this.createdAt,
    this.promptVersion,
    this.model,
  });

  final String id;
  final String issueId;
  final String schemaVersion;
  final CandidateFactData candidateData;
  final DateTime createdAt;

  // Traçabilité (section 7.2) : quelle version de prompt / quel modèle a
  // produit ce candidat - permet de corréler un résultat inattendu avec un
  // changement de `prompts/extraction_fr_v1.txt` ou de modèle OpenAI sans
  // avoir à rejouer l'appel.
  final String? promptVersion;
  final String? model;
}
