/// Correction ciblée post-recette terrain R1 : formatage `mm:ss` partagé par
/// le timer d'enregistrement (`voice_description_screen.dart`) et la
/// progression de lecture (`evidence_audio_player_screen.dart`) - fonction
/// pure, sans dépendance, testable isolément.
String formatMmSs(Duration duration) {
  final Duration clamped = duration.isNegative ? Duration.zero : duration;
  final String minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final String seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
