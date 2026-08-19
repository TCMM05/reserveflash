"""Value objects et enums du domaine metier.

Le domaine ne connait ni FastAPI, ni SQLAlchemy, ni aucun provider IA/storage
(section 5.3 - regle de dependance). Ce module ne doit importer que la
bibliotheque standard.
"""

from __future__ import annotations

from enum import StrEnum


class IssueType(StrEnum):
    """Types d'anomalie declarables (F05, section 2.1)."""

    PACKAGING_DAMAGE = "PACKAGING_DAMAGE"
    PRODUCT_DAMAGE = "PRODUCT_DAMAGE"
    MISSING_QTY = "MISSING_QTY"
    WRONG_QTY = "WRONG_QTY"
    WRONG_PRODUCT = "WRONG_PRODUCT"
    VISIBLE_NONCONFORMITY = "VISIBLE_NONCONFORMITY"
    OTHER = "OTHER"


class IncidentStatus(StrEnum):
    """Etats metier d'un incident (section 2.2)."""

    DRAFT_LOCAL = "draft_local"
    SYNCING = "syncing"
    EXTRACTION_PENDING = "extraction_pending"
    REVIEW_REQUIRED = "review_required"
    FACTS_CONFIRMED = "facts_confirmed"
    RESERVE_READY = "reserve_ready"
    EVIDENCE_COMPLETE = "evidence_complete"
    EXPORTED = "exported"
    ARCHIVED = "archived"

    @property
    def allowed_next(self) -> frozenset[IncidentStatus]:
        """Transitions principales autorisees (section 2.2). Une transition hors
        de cet ensemble doit etre rejetee par le domaine plutot que silencieusement
        acceptee."""
        graph: dict[IncidentStatus, frozenset[IncidentStatus]] = {
            IncidentStatus.DRAFT_LOCAL: frozenset(
                {IncidentStatus.SYNCING, IncidentStatus.REVIEW_REQUIRED}
            ),
            IncidentStatus.SYNCING: frozenset(
                {IncidentStatus.EXTRACTION_PENDING, IncidentStatus.DRAFT_LOCAL}
            ),
            IncidentStatus.EXTRACTION_PENDING: frozenset({IncidentStatus.REVIEW_REQUIRED}),
            IncidentStatus.REVIEW_REQUIRED: frozenset({IncidentStatus.FACTS_CONFIRMED}),
            IncidentStatus.FACTS_CONFIRMED: frozenset({IncidentStatus.RESERVE_READY}),
            IncidentStatus.RESERVE_READY: frozenset({IncidentStatus.EVIDENCE_COMPLETE}),
            IncidentStatus.EVIDENCE_COMPLETE: frozenset({IncidentStatus.EXPORTED}),
            IncidentStatus.EXPORTED: frozenset(
                {IncidentStatus.ARCHIVED, IncidentStatus.REVIEW_REQUIRED}
            ),
            IncidentStatus.ARCHIVED: frozenset({IncidentStatus.REVIEW_REQUIRED}),
        }
        return graph[self]

    def can_transition_to(self, target: IncidentStatus) -> bool:
        return target in self.allowed_next

    def path_to(self, target: IncidentStatus) -> list[IncidentStatus] | None:
        """Plus court chemin (BFS) dans le graphe de transitions section 2.2,
        utilisé quand un événement métier (ex: export génère) doit faire
        avancer l'incident de plusieurs étapes d'un coup sans sauter d'état
        interdit. Retourne None si aucun chemin n'existe."""
        if self == target:
            return [self]
        from collections import deque

        queue: deque[list[IncidentStatus]] = deque([[self]])
        visited = {self}
        while queue:
            path = queue.popleft()
            for nxt in path[-1].allowed_next:
                if nxt in visited:
                    continue
                new_path = [*path, nxt]
                if nxt == target:
                    return new_path
                visited.add(nxt)
                queue.append(new_path)
        return None


class FactSource(StrEnum):
    """Origine d'un champ candidat (schema CandidateFactSet)."""

    OCR = "OCR"
    VOICE_TRANSCRIPT = "VOICE_TRANSCRIPT"
    TEXT_INPUT = "TEXT_INPUT"
    LLM_NORMALIZATION = "LLM_NORMALIZATION"


class ConfidenceLevel(StrEnum):
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    AMBIGUOUS = "AMBIGUOUS"


class SyncStatus(StrEnum):
    """Statut affiche a l'ecran (section 8.1) : Local / En attente / Synchronise / Erreur."""

    LOCAL = "local"
    PENDING = "pending"
    SYNCED = "synced"
    ERROR = "error"


class EvidenceAssetType(StrEnum):
    PHOTO_DELIVERY_DOCUMENT = "PHOTO_DELIVERY_DOCUMENT"
    PHOTO_EVIDENCE = "PHOTO_EVIDENCE"
    PHOTO_FINAL_DOCUMENT = "PHOTO_FINAL_DOCUMENT"
    AUDIO_DESCRIPTION = "AUDIO_DESCRIPTION"


class OrganizationRole(StrEnum):
    """section 2.6 - ADMIN avance = ROADMAP, non implemente en 1.0."""

    OWNER = "OWNER"
    MEMBER = "MEMBER"
