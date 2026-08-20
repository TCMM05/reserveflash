"""Garde-fou deterministe applique aux CandidateFactData (R2, section
"Validation semantique obligatoire" de la demande de demarrage R2).

Contexte : app/domain/liability_guard.py protege deja la reserve finale en
rejetant un ConfirmedFactData contenant une attribution de responsabilite,
une promesse d'indemnisation, une conclusion/qualification juridique ou un
montant invente - mais seulement APRES que l'utilisateur a confirme le
champ. Le risque R2 est different : le pipeline IA (transcription + extraction,
app/infrastructure/ai/openai_provider.py) peut proposer un CandidateFactData
contenant deja ce type de contenu interdit (ex: l'utilisateur dit "c'est
clairement la faute du transporteur" et un extracteur mal cadre ecrit
`packaging_condition = "transporteur responsable"`). Si ce candidat est
affiche tel quel a l'ecran de revue (F09), l'utilisateur peut le confirmer
sans le relire attentivement - le contenu interdit contournerait alors
liability_guard cote confirmation puisqu'il aurait ete "invente" comme valeur
proposee plutot que saisi par l'utilisateur lui-meme.

Principe de ce module (defense en profondeur, meme philosophie que
liability_guard.py, section "Gestion de l'incertitude" et "Validation
semantique obligatoire" de la demande R2) :

  1. Aucun champ candidat dont la valeur texte libre contient un motif
     interdit (app.domain.liability_guard.FORBIDDEN_PATTERNS - source
     unique, voir ce module) n'est jamais transmis a l'ecran de revue. Le
     champ est retire du candidat (jamais reecrit/sanitise silencieusement -
     il disparait, il ne devient pas une fausse valeur "propre").
  2. Une quantite negative dans un champ de quantite connu
     (expected_quantity / received_quantity / affected_quantity) est
     physiquement impossible : elle indique une hallucination ou une erreur
     de parsing du LLM, jamais une donnee reelle. Le champ est retire.
  3. Tout retrait force `requires_review=True` (meme si le candidat
     l'affichait deja a `False`) : l'utilisateur voit alors explicitement
     qu'il manque une information plutot que de croire le dossier complet.

Deterministe, aucun appel reseau, aucune sanitization silencieuse - un champ
retire n'est PAS remplace par une version "nettoyee" du meme texte (memes
principes que liability_guard.py). Ne leve jamais d'exception : contrairement
au ConfirmedFactData (ou un contenu interdit doit bloquer explicitement la
confirmation), un CandidateFactData degrade proprement en retirant le champ
fautif plutot qu'en faisant echouer toute l'extraction (section "Echec IA" de
la demande R2 : "aucune boucle infinie de retries", "ne jamais bloquer
l'utilisateur")."""

from __future__ import annotations

from app.domain.fact_set import CandidateFactData
from app.domain.liability_guard import FORBIDDEN_PATTERNS

# Champs de quantite connus du schema V1 (schemas/candidate_fact_set.v1.schema.json,
# section "Champs V1 prioritaires" de la demande R2). Une valeur negative sur
# l'un de ces champs est toujours invalide - une quantite ne peut pas etre
# negative dans le monde reel.
_KNOWN_QUANTITY_FIELDS: frozenset[str] = frozenset(
    {"expected_quantity", "received_quantity", "affected_quantity"}
)


def _first_forbidden_violation(value: str) -> str | None:
    for violation_code, pattern in FORBIDDEN_PATTERNS.items():
        if pattern.search(value):
            return violation_code
    return None


def _is_invalid_quantity(field_name: str, value: object) -> bool:
    if field_name not in _KNOWN_QUANTITY_FIELDS:
        return False
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    return value < 0


def screen_candidate_fact_data(candidate: CandidateFactData) -> CandidateFactData:
    """Retourne un CandidateFactData equivalent a `candidate`, prive de tout
    champ contenant un contenu interdit (liability/indemnisation/conclusion
    ou qualification juridique/montant invente) ou une quantite negative.

    Ne modifie jamais `candidate` en place (immutabilite Pydantic standard du
    projet) : retourne le meme objet si rien n'a ete retire (pas d'allocation
    inutile), sinon une copie avec `fields` et `requires_review` mis a jour.
    """
    screened_fields = {}
    removed_field_names: list[str] = []

    for field_name, field in candidate.fields.items():
        value = field.value
        violation = _first_forbidden_violation(value) if isinstance(value, str) else None
        if violation is not None or _is_invalid_quantity(field_name, value):
            removed_field_names.append(field_name)
            continue
        screened_fields[field_name] = field

    if not removed_field_names:
        return candidate

    return candidate.model_copy(update={"fields": screened_fields, "requires_review": True})
