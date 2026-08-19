"""Exceptions du domaine. Elles portent un code stable reutilisable par la couche
API pour respecter la taxonomie d'erreurs (section 9.3) sans que le domaine
connaisse HTTP."""

from __future__ import annotations


class DomainError(Exception):
    """Base pour toute violation de regle metier."""

    code: str = "DOMAIN_ERROR"

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class UnconfirmedFactSetError(DomainError):
    """Invariant 6.3 : ConfirmedFactSet.user_confirmed doit etre true avant
    toute generation de reserve. Leve si on tente de composer une reserve a
    partir d'un jeu de faits non valide par l'utilisateur."""

    code = "UNCONFIRMED_FACT_SET"


class UnresolvedUnknownFieldError(DomainError):
    """GATE zero invention : un champ marque UNKNOWN par l'utilisateur ne doit
    jamais etre transforme en affirmation dans le texte de reserve (section 6.3,
    15.2 'Reserve finale contenant un fait non confirme = 0')."""

    code = "UNRESOLVED_UNKNOWN_FIELD"


class InvalidStateTransitionError(DomainError):
    """Transition d'etat metier hors du graphe autorise (section 2.2)."""

    code = "INVALID_STATE_TRANSITION"


class TemplateNotFoundError(DomainError):
    """Aucun template de reserve versionne pour (langue, issue_type) demande
    (section 2.4 - Templates versionnes par langue et type d'incident)."""

    code = "TEMPLATE_NOT_FOUND"


class CrossTenantAccessError(DomainError):
    """Tentative d'acces a une ressource d'une autre organisation (SEC-04,
    scenario E2E-09). Doit se traduire en 403/404 cote API, jamais en fuite
    d'information sur l'existence de la ressource."""

    code = "FORBIDDEN"


class ConflictingRevisionError(DomainError):
    """section 8.2 - conflit bloquant (ex: ConfirmedFactSet modifie sur deux
    appareils). Jamais de fusion automatique."""

    code = "CONFLICT"


class AIUnavailableError(DomainError):
    """section 7.4 - Timeout / indisponibilite provider IA. Mappe vers 503
    AI_UNAVAILABLE (section 9.3). Ne doit jamais faire perdre une preuve
    (GATE de resilience, section 7.4)."""

    code = "AI_UNAVAILABLE"


class AIInvalidOutputError(DomainError):
    """section 7.4 - Sortie structuree LLM invalide apres au plus 1 tentative
    de reparation controlee. Mappe vers 422 AI_INVALID_OUTPUT."""

    code = "AI_INVALID_OUTPUT"


class AIRateLimitedError(DomainError):
    """section 7.4 - Provider rate limit. Mappe vers 429 RATE_LIMITED, UX non
    bloquante (queue + retry exponentiel cote backend)."""

    code = "RATE_LIMITED"


class LiabilityAttributionError(DomainError):
    """Correctif R0.1 (point 8 de la demande corrective) : un champ texte
    libre d'un ConfirmedFactData (ex: packaging_condition, product_condition)
    contient une attribution de responsabilite, une promesse d'indemnisation,
    une conclusion ou qualification juridique, ou un montant invente. Levee
    par app.domain.liability_guard AVANT toute composition de reserve
    (app.domain.reserve_composer.compose_reserve), conformement au GATE zero
    invention (section 2.4) : le Reserve Composer ne doit jamais pouvoir
    produire un texte engageant une responsabilite, meme si la donnee
    provient d'un champ "confirme" par l'utilisateur.

    Contrairement aux autres DomainError, celle-ci porte des attributs
    additionnels (violation_code, field_name) pour permettre a l'UI mobile
    d'indiquer precisement quel champ reformuler (section 9.2 - "message
    utilisateur safe")."""

    code = "LIABILITY_ATTRIBUTION_BLOCKED"

    def __init__(self, message: str, *, violation_code: str, field_name: str) -> None:
        super().__init__(message)
        self.violation_code = violation_code
        self.field_name = field_name
