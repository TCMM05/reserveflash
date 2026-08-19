import 'package:share_plus/share_plus.dart';

/// Partage natif du dossier PDF (F14, point 10 de la demande corrective).
///
/// "Le PDF final doit pouvoir être partagé via le partage natif Android/iOS
/// (mail, WhatsApp, Drive, OneDrive, autres apps). Le partage ne doit pas
/// nécessiter le serveur ReserveFlash."
///
/// Cette classe est un wrapper mince autour de `share_plus`
/// (`Share.shareXFiles`), qui délègue entièrement à la feuille de partage du
/// système d'exploitation - aucune requête réseau vers le backend
/// ReserveFlash n'est faite ici, ni possible (aucune dépendance HTTP dans ce
/// fichier).
class ReserveShareService {
  const ReserveShareService();

  /// Ouvre la feuille de partage native pour le PDF à [pdfFilePath].
  /// [incidentLabel] est utilisé comme texte d'accompagnement (ex: nom du
  /// fournisseur/référence livraison), jamais transmis à un service distant.
  Future<void> sharePdf({
    required String pdfFilePath,
    String? incidentLabel,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(pdfFilePath, mimeType: 'application/pdf')],
        subject: incidentLabel == null
            ? 'Dossier ReserveFlash'
            : 'Dossier ReserveFlash - $incidentLabel',
      ),
    );
  }
}
