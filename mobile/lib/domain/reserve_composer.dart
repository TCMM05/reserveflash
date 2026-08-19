/// Reserve Composer - GATE zéro invention (section 2.4) - miroir Dart de
/// `backend/app/domain/reserve_composer.py`.
///
///   "Le Reserve Composer est un composant déterministe. Il ne reçoit pas le
///   texte libre utilisateur ni la réponse brute LLM ; seulement le
///   ConfirmedFactSet typé."
///
/// Depuis R0.1 (pivot Local-First, point 6) : ce module tourne SUR
/// L'APPAREIL, pour que "générer un dossier à partir des données locales
/// quand l'IA n'est pas nécessaire" fonctionne réellement hors ligne, sans
/// aller-retour serveur. C'est le SEUL point d'entrée mobile pour produire
/// un texte de réserve : n'importe aucun provider IA, aucun client HTTP -
/// seulement des `ConfirmedFactData` (déjà `userConfirmed = true` par
/// construction) et le registre de templates versionnés
/// (`lib/domain/templates/`).
///
/// Invariant vérifié ici (section 6.3 + 15.2) :
///   "Réserve finale contenant un fait non confirmé" doit toujours valoir 0.
/// Garanti par le système de types : `ConfirmedFactData` ne peut pas exister
/// avec `userConfirmed = false`.
///
/// Deuxième invariant, ajouté en R0.1 (correctif point 8) : une réserve ne
/// doit jamais pouvoir contenir une attribution de responsabilité, une
/// promesse d'indemnisation, une conclusion/qualification juridique ou un
/// montant inventé - même si ce contenu provient d'un champ « confirmé » par
/// l'utilisateur. Voir `lib/domain/liability_guard.dart`. L'appel est fait
/// ICI, dans l'unique point d'entrée de composition, pour qu'aucun appelant
/// (présent ou futur) ne puisse l'oublier.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors/domain_errors.dart';
import 'fact_set/confirmed_fact_data.dart';
import 'liability_guard.dart';
import 'templates/fr_v1.dart' as fr_v1;

typedef _ParagraphFn = String Function(ConfirmedFactData fact);

final Map<String, _ParagraphFn> _templateRegistry = <String, _ParagraphFn>{
  fr_v1.templateVersionFrV1: fr_v1.composeIssueParagraph,
};

final Map<String, String> _prudenceMentionRegistry = <String, String>{
  fr_v1.templateVersionFrV1: fr_v1.prudenceMentionFrV1,
};

/// Résultat déterministe de la composition. `sha256` permet de vérifier
/// qu'une réserve n'a pas été altérée après génération, et de détecter une
/// révision de faits non répercutée (invariant "une révision de faits
/// confirmés invalide automatiquement la réserve et le PDF précédents").
class ComposedReserve {
  const ComposedReserve({
    required this.text,
    required this.templateVersion,
    required this.prudenceMention,
    required this.sha256,
  });

  final String text;
  final String templateVersion;
  final String prudenceMention;
  final String sha256;
}

/// Compose la réserve globale ordonnée à partir d'un ou plusieurs
/// `ConfirmedFactData` (section 2.5 - incidents multiples : "1 colis
/// manquant + 2 cartons écrasés + 1 produit rayé").
///
/// Déterministe : mêmes faits + même version de template => même texte et
/// même hash, à l'identique, pour toute relecture ou audit.
///
/// Lève [LiabilityAttributionException] (voir liability_guard.dart) si un
/// champ confirmé contient un contenu interdit, et [TemplateNotFoundException]
/// si `templateVersion` est inconnue.
ComposedReserve composeReserve(
  List<ConfirmedFactData> facts, {
  String templateVersion = fr_v1.templateVersionFrV1,
}) {
  final _ParagraphFn? paragraphFn = _templateRegistry[templateVersion];
  if (paragraphFn == null) {
    throw TemplateNotFoundException(
      "Aucun template de réserve pour la version '$templateVersion'.",
    );
  }
  if (facts.isEmpty) {
    throw ArgumentError('composeReserve requiert au moins un ConfirmedFactData.');
  }

  // Garde-fou déterministe R0.1 (point 8) : lève avant toute composition si
  // un champ confirmé contient un contenu interdit.
  screenConfirmedFacts(facts);

  final String text = facts.map(paragraphFn).join('\n\n');
  final String digest = sha256.convert(utf8.encode(text)).toString();

  return ComposedReserve(
    text: text,
    templateVersion: templateVersion,
    prudenceMention: _prudenceMentionRegistry[templateVersion]!,
    sha256: digest,
  );
}
