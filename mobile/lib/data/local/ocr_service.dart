/// Service d'OCR local (R2 - lot OCR `document_capture_screen.dart`,
/// section 3.2 "S06 - Capture document"). Reconnaissance de texte SUR
/// L'APPAREIL (`google_mlkit_text_recognition`) - aucun appel réseau, aucun
/// coût IA, contrairement à la transcription audio (qui, elle, appelle
/// OpenAI via le backend - voir `lib/data/ai_queue_processor.dart` et
/// `lib/data/remote/ai_api_client.dart`). Le texte reconnu est ensuite
/// transmis à `/v1/ai/extract` (champ `document_text`, déjà supporté côté
/// backend et par `AiApiClient.extractCandidateFacts` depuis R2) - même
/// endpoint et même schéma `CandidateFactData` que pour une note vocale,
/// seule la source du texte diffère.
///
/// Interface distincte de l'implémentation ML Kit (même principe que
/// `lib/data/remote/ai_api_client.dart::AiHttpTransport` et
/// `lib/data/local/evidence_storage.dart::EvidenceStorageService`) : ce
/// sandbox de développement n'a pas accès au SDK Flutter/Dart pour exécuter
/// le plugin natif `google_mlkit_text_recognition` (canal de plateforme,
/// nécessite un vrai appareil/émulateur) - passer par cette interface
/// permet à `test/data/ai_queue_processor_test.dart` de fournir un faux
/// [OcrService] fait à la main, sans jamais dépendre du plugin natif dans
/// les tests unitaires (même choix que pour `AiHttpTransport`, voir sa
/// docstring pour la justification complète de ce principe).
library;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

abstract interface class OcrService {
  /// Reconnaît le texte visible dans l'image déjà capturée et persistée sur
  /// disque au chemin [imagePath] (voir
  /// `EvidenceAsset.localFilePath`). Ne lève JAMAIS pour un texte absent ou
  /// illisible (photo floue, mauvais angle, document non textuel) : retourne
  /// une chaîne vide plutôt qu'une exception - même philosophie "ne jamais
  /// bloquer l'utilisateur" que le reste du pipeline IA (section "Échec
  /// IA"). Une extraction sur texte vide produira simplement un
  /// `CandidateFactData` sans champ (`requires_review: true`), jamais une
  /// erreur affichée pour ce cas précis.
  Future<String> recognizeText(String imagePath);
}

/// Implémentation réelle - `google_mlkit_text_recognition`, script Latin
/// (couvre le français, section 5.1 - autres scripts non nécessaires pour
/// la V1 France). Un [TextRecognizer] neuf par appel plutôt qu'un singleton
/// partagé : évite tout état de plateforme partagé entre deux
/// reconnaissances concurrentes (en pratique, `AiQueueProcessor` traite déjà
/// la file séquentiellement - défense ceinture-bretelles) et garantit que
/// `close()` (libération des ressources natives ML Kit) est systématique,
/// y compris en cas d'exception (`try`/`finally`).
final class MlKitOcrService implements OcrService {
  const MlKitOcrService();

  @override
  Future<String> recognizeText(String imagePath) async {
    final TextRecognizer recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await recognizer.processImage(inputImage);
      // DEBUG TEMPORAIRE (diagnostic terrain R2, "Non détecté" malgré une
      // photo lisible par un humain) - confirme si ML Kit lit vraiment du
      // texte sur les photos prises en émulateur (webcam) ; à retirer une
      // fois la cause confirmée. Visible dans la console `flutter run`.
      // ignore: avoid_print
      print(
        '[DEBUG OCR] ${recognizedText.text.isEmpty ? "(vide)" : recognizedText.text}',
      );
      return recognizedText.text;
    } finally {
      await recognizer.close();
    }
  }
}
