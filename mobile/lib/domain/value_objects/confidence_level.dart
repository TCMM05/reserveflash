/// Confiance associée à un champ candidat IA (S07/S11, section 2.3).
enum ConfidenceLevel {
  high('HIGH'),
  medium('MEDIUM'),
  low('LOW'),
  ambiguous('AMBIGUOUS');

  const ConfidenceLevel(this.wireValue);

  final String wireValue;
}

/// Origine d'un champ candidat (schema CandidateFactSet).
enum FactSource {
  ocr('OCR'),
  voiceTranscript('VOICE_TRANSCRIPT'),
  textInput('TEXT_INPUT'),
  llmNormalization('LLM_NORMALIZATION');

  const FactSource(this.wireValue);

  final String wireValue;
}

/// Statut de synchronisation affiché à l'écran (section 8.1 : "Local / En
/// attente / Synchronisé / Erreur").
enum SyncStatus {
  local('local'),
  pending('pending'),
  synced('synced'),
  error('error');

  const SyncStatus(this.wireValue);

  final String wireValue;
}
