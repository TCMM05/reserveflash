/// Couche d'I/O fichier pour les preuves (photos/audio/bon de livraison) -
/// R1 "Capture Offline", point 2/4/9 de la demande corrective.
///
/// Référencée depuis R0.1 par la docstring de
/// `lib/domain/repositories/incident_repository.dart::registerEvidenceAsset`
/// ("le repository ne gère jamais l'écriture binaire elle-même") : ce
/// fichier est la SEULE partie de l'app qui écrit/lit des octets sur le
/// disque de l'appareil pour les preuves. Aucune dépendance Drift ici -
/// frontière stricte symétrique à celle de `incident_repository.dart` (qui
/// n'importe, lui, aucun package `dart:io`/`path_provider`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/evidence_asset.dart' as domain;

const Uuid _uuid = Uuid();

/// Résultat d'une vérification d'intégrité disque pour une preuve
/// individuelle (point 9 - détection `missing`/`corrupted`, R1-T07).
final class EvidenceIntegrityCheck {
  const EvidenceIntegrityCheck({
    required this.availabilityStatus,
    this.recalculatedSha256,
  });

  final domain.EvidenceAvailability availabilityStatus;

  /// `null` si le fichier est `missing` (rien à hasher) ; sinon le SHA-256
  /// recalculé à l'instant, que le statut soit `available` ou `corrupted`.
  final String? recalculatedSha256;
}

/// Service d'I/O fichier pour les preuves - stateless, aucune dépendance
/// externe hors `dart:io`/`path_provider`/`crypto`/`uuid`.
///
/// Invariant central (points 4 et 9 de la demande corrective R1) :
/// "chaque photo sauvegardée AVANT toute opération réseau/IA" et "une photo
/// validée ne doit jamais disparaître parce qu'une étape ultérieure
/// échoue" - réalisé ici par une écriture ATOMIQUE (fichier temporaire dans
/// le MÊME répertoire que la destination finale, puis `rename`) : soit le
/// fichier final existe intégralement, soit il n'existe pas du tout, jamais
/// un état partiel visible d'un autre code de l'app (R1-T05/T09).
final class EvidenceStorageService {
  /// [documentsDirectoryProvider] est injectable UNIQUEMENT pour les tests
  /// (voir test/data/r1_capture_offline_test.dart) : `flutter test` exécute
  /// du Dart pur, sans canal de plateforme disponible pour
  /// `path_provider` - injecter un dossier temporaire réel évite de
  /// dépendre d'un mock de canal de plateforme, tout en gardant la même
  /// garantie testée qu'en production (vraie écriture disque). En usage
  /// normal (runtime app), ce paramètre est TOUJOURS omis :
  /// `getApplicationDocumentsDirectory()` (espace privé réel de l'app,
  /// point 2) reste le comportement par défaut.
  const EvidenceStorageService({
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : _documentsDirectoryProvider = documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectoryProvider;

  /// Répertoire privé de l'app dédié aux preuves d'un incident
  /// (`<documents-de-l'app>/evidence/<incidentId>/`), créé si nécessaire.
  /// En production, `getApplicationDocumentsDirectory()` (path_provider)
  /// pointe vers l'espace privé de l'app sur l'appareil (point 2 - "photo
  /// conservée dans l'espace privé de l'app"), jamais un dossier public
  /// partagé.
  Future<Directory> evidenceDirectoryFor(String incidentId) async {
    final Directory appDocs = await _documentsDirectoryProvider();
    final Directory dir = Directory('${appDocs.path}/evidence/$incidentId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copie ATOMIQUEMENT le fichier temporaire produit par un plugin de
  /// capture (`camera`/`record`, situé hors de l'espace privé structuré de
  /// l'app - cache temporaire du plugin) vers l'espace privé de l'app, en
  /// calculant son SHA-256 au passage, et retourne un [domain.EvidenceAsset]
  /// prêt à être persisté via `IncidentRepository.registerEvidenceAsset`.
  ///
  /// Ne parle JAMAIS à Drift (frontière stricte, voir docstring de classe)
  /// et ne fait AUCUN appel réseau (point 8/9 - fonctionnement 100% offline).
  ///
  /// [id] est généré ICI, pas par le repository : asymétrie assumée avec
  /// `createIncident`/`addIssue` (voir docstring de
  /// `IncidentRepository.registerEvidenceAsset`, qui exige un
  /// [domain.EvidenceAsset] déjà entièrement formé en entrée).
  Future<domain.EvidenceAsset> captureFromFile({
    required String incidentId,
    required String sourcePath,
    required domain.EvidenceDocumentType documentType,
    required String mimeType,
    String? issueId,
    String extension = 'jpg',
  }) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError(
        'Fichier source introuvable pour la capture de preuve : $sourcePath',
      );
    }
    final List<int> bytes = await source.readAsBytes();

    final String id = _uuid.v4();
    final Directory dir = await evidenceDirectoryFor(incidentId);
    final String finalPath = '${dir.path}/$id.$extension';
    final File tempFile = File('$finalPath.tmp');

    // Écriture atomique (points 4/9) : le fichier temporaire est écrit dans
    // le MÊME répertoire que la destination finale (garantit que le
    // `rename` ci-dessous reste une opération atomique du système de
    // fichiers, jamais une copie inter-volume qui pourrait être
    // interrompue), puis renommé vers le nom final. Un kill du process
    // entre les deux lignes suivantes ne laisse jamais `finalPath` dans un
    // état partiel : soit il n'existe pas encore (seul `.tmp` traîne,
    // jamais référencé par aucune métadonnée puisque `registerEvidenceAsset`
    // n'est appelé qu'APRÈS le retour de cette méthode), soit il existe déjà
    // intégralement (le `rename` a terminé).
    await tempFile.writeAsBytes(bytes, flush: true);
    await tempFile.rename(finalPath);

    final String sha256Hex = sha256.convert(bytes).toString();

    return domain.EvidenceAsset(
      id: id,
      incidentId: incidentId,
      issueId: issueId,
      documentType: documentType,
      localFilePath: finalPath,
      sha256: sha256Hex,
      mimeType: mimeType,
      bytes: bytes.length,
      capturedAtDevice: DateTime.now().toUtc(),
    );
  }

  /// Supprime le fichier binaire d'une preuve (point 7 - "supprimer une
  /// photo avec confirmation" ; la confirmation elle-même est de la
  /// responsabilité de l'écran appelant, jamais de ce service). Idempotent :
  /// ne lève pas si le fichier est déjà absent (état `missing` légitime,
  /// point 9).
  Future<void> deleteFile(String localFilePath) async {
    final File file = File(localFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Relit le fichier référencé par [asset] et recalcule son SHA-256 pour
  /// détecter un état `missing` (fichier absent) ou `corrupted` (hash
  /// différent de celui enregistré à la capture) - point 9/R1-T07 :
  /// "fichier local manquant ou corrompu -> UI contrôlée, aucun crash". Ne
  /// lève JAMAIS : toute erreur de lecture (permission, verrou OS...) est
  /// traitée comme `missing`, jamais propagée en exception non gérée vers
  /// l'UI (invariant central de R1-T07).
  Future<EvidenceIntegrityCheck> verify(domain.EvidenceAsset asset) async {
    try {
      final File file = File(asset.localFilePath);
      if (!await file.exists()) {
        return const EvidenceIntegrityCheck(
          availabilityStatus: domain.EvidenceAvailability.missing,
        );
      }
      final List<int> bytes = await file.readAsBytes();
      final String recalculated = sha256.convert(bytes).toString();
      if (asset.sha256 != null && asset.sha256 != recalculated) {
        return EvidenceIntegrityCheck(
          availabilityStatus: domain.EvidenceAvailability.corrupted,
          recalculatedSha256: recalculated,
        );
      }
      return EvidenceIntegrityCheck(
        availabilityStatus: domain.EvidenceAvailability.available,
        recalculatedSha256: recalculated,
      );
    } on FileSystemException {
      // Fichier référencé mais illisible (droits, verrou OS, disque
      // externe démonté...) : traité comme "missing" du point de vue de
      // l'utilisateur (point 9), jamais comme un crash (R1-T07).
      return const EvidenceIntegrityCheck(
        availabilityStatus: domain.EvidenceAvailability.missing,
      );
    }
  }

  /// Relit les octets bruts du fichier référencé par [asset] - ajouté pour
  /// R2 : `lib/data/ai_queue_processor.dart` en a besoin pour transmettre un
  /// audio déjà capturé à `AiApiClient.transcribe` (l'IA n'est JAMAIS
  /// appelée pendant la capture elle-même, uniquement plus tard via la file
  /// `AiOperationQueue` - voir docstring de ce fichier et de
  /// `ai_queue_processor.dart`), tout en respectant la frontière stricte de
  /// cette classe (SEULE partie de l'app qui lit/écrit des octets pour les
  /// preuves).
  ///
  /// Contrairement à [verify] (qui traite un fichier absent comme un état
  /// `missing` normal, jamais une exception - R1-T07), cette méthode lève
  /// [StateError] si le fichier est introuvable : un appelant qui a
  /// spécifiquement besoin du CONTENU d'une preuve doit être informé
  /// immédiatement de son indisponibilité (échec explicite et traçable de
  /// l'opération IA en cours), jamais recevoir un tableau d'octets vide
  /// silencieux.
  Future<Uint8List> readBytes(domain.EvidenceAsset asset) async {
    final File file = File(asset.localFilePath);
    if (!await file.exists()) {
      throw StateError(
        'Fichier de preuve introuvable pour la lecture : '
        '${asset.localFilePath} (preuve ${asset.id}).',
      );
    }
    final List<int> bytes = await file.readAsBytes();
    return Uint8List.fromList(bytes);
  }
}
