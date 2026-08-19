"""Tests adversariaux du garde-fou anti-attribution de responsabilité (R0.1,
correctif point 8 de la demande "Local-First").

Rejoue le bug signalé explicitement par le donneur d'ordre : R0 laissait
`packaging_condition = "transporteur responsable"` traverser tel quel
jusqu'à la réserve finale. Chaque test ci-dessous prouve soit (a) que la
confirmation d'un tel champ est bloquée avant même d'atteindre le Reserve
Composer, soit (b) que même en contournant l'étape de confirmation (ex: futur
appelant direct de compose_reserve), le composer lui-même refuse de produire
un texte contenant ce type de contenu - défense en profondeur explicitement
demandée par le cahier des charges.
"""

from __future__ import annotations

import pytest

from app.application.use_cases.confirm_facts import confirm_facts
from app.domain.errors import LiabilityAttributionError
from app.domain.fact_set import ConfirmedFactData
from app.domain.liability_guard import screen_confirmed_fact, screen_confirmed_facts
from app.domain.reserve_composer import compose_reserve
from app.domain.value_objects import IssueType
from app.infrastructure.db.in_memory_repository import InMemoryIncidentRepository


def _fact(**overrides):
    base = dict(issue_type=IssueType.PACKAGING_DAMAGE, user_confirmed=True)
    base.update(overrides)
    return ConfirmedFactData(**base)


# --- Cas nommément cité dans la demande corrective ------------------------


def test_reported_bug_packaging_condition_transporteur_responsable_is_blocked():
    """Cas exact signalé : packaging_condition = "transporteur responsable"
    doit être rejeté par le garde-fou, pas seulement absent d'un texte
    généré indépendamment (voir aussi test_reserve_composer.py::
    test_e2e07_out_of_scope_liability_never_appears, qui ne couvrait PAS ce
    chemin avant R0.1)."""
    fact = _fact(packaging_condition="transporteur responsable")
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "LIABILITY_ATTRIBUTION"
    assert exc_info.value.field_name == "packaging_condition"


def test_reported_bug_never_reaches_compose_reserve():
    """Défense en profondeur : même appelé directement (sans passer par le
    cas d'usage confirm_facts), compose_reserve() doit lui aussi refuser."""
    fact = _fact(product_condition="le transporteur est responsable du dommage")
    with pytest.raises(LiabilityAttributionError):
        compose_reserve([fact])


# --- Attribution de responsabilité (autres formulations) ------------------


@pytest.mark.parametrize(
    "field,value",
    [
        ("packaging_condition", "transporteur responsable"),
        ("packaging_condition", "faute du livreur"),
        ("product_condition", "dommage imputable au transporteur"),
        ("product_condition", "carton à la charge du fournisseur"),
        ("location_on_item", "coin endommagé, fautif : entrepôt"),
    ],
)
def test_liability_attribution_phrasings_are_blocked(field, value):
    fact = _fact(**{field: value})
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "LIABILITY_ATTRIBUTION"


# --- Promesse d'indemnisation ----------------------------------------------


@pytest.mark.parametrize(
    "value",
    [
        "sera indemnisé intégralement",
        "dédommagement prévu",
        "remboursement dû au client",
    ],
)
def test_indemnification_promises_are_blocked(value):
    fact = _fact(product_condition=value)
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "INDEMNIFICATION_PROMISE"


# --- Conclusion juridique ---------------------------------------------------


@pytest.mark.parametrize(
    "value",
    [
        "manquement contractuel du transporteur",
        "vice caché constaté",
        "négligence lors du transport",
    ],
)
def test_legal_conclusions_are_blocked(value):
    fact = _fact(packaging_condition=value)
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "LEGAL_CONCLUSION"


# --- Montant inventé ---------------------------------------------------


@pytest.mark.parametrize(
    "value",
    ["dommage estimé à 150€", "montant de 300 euros", "50 EUR de perte"],
)
def test_invented_amounts_are_blocked(value):
    fact = _fact(product_condition=value)
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "INVENTED_AMOUNT"


# --- Qualification juridique -------------------------------------------


@pytest.mark.parametrize(
    "value",
    ["cas de force majeure", "infraction constatée lors du transport"],
)
def test_legal_qualifications_are_blocked(value):
    fact = _fact(packaging_condition=value)
    with pytest.raises(LiabilityAttributionError) as exc_info:
        screen_confirmed_fact(fact)
    assert exc_info.value.violation_code == "LEGAL_QUALIFICATION"


def test_faute_lourde_is_blocked_even_though_liability_pattern_matches_first():
    """« faute lourde » contient à la fois un motif LIABILITY_ATTRIBUTION
    (« faute ») et un motif LEGAL_QUALIFICATION (« faute lourde ») : le
    garde-fou doit bloquer dans tous les cas, quel que soit le code de
    violation renvoyé (les deux sont interdits en réserve)."""
    fact = _fact(packaging_condition="relève d'une faute lourde")
    with pytest.raises(LiabilityAttributionError):
        screen_confirmed_fact(fact)


# --- Non-régression : constats factuels légitimes doivent PASSER ----------


@pytest.mark.parametrize(
    "field,value",
    [
        ("packaging_condition", "carton enfoncé sur un angle"),
        ("packaging_condition", "emballage déchiré, film plastique arraché"),
        ("product_condition", "rayure visible sur la face avant"),
        ("product_condition", "verre fissuré sur 5 cm"),
        ("location_on_item", "coin inférieur gauche"),
        ("product_label", "Ballon eau chaude 200L"),
    ],
)
def test_legitimate_factual_observations_are_never_blocked(field, value):
    """Non-régression : le garde-fou ne doit PAS bloquer un constat factuel
    neutre - sinon il empêcherait l'usage normal de l'application."""
    fact = _fact(**{field: value})
    screen_confirmed_fact(fact)  # ne doit lever aucune exception


def test_screen_confirmed_facts_checks_every_fact_in_sequence():
    ok_fact = _fact(packaging_condition="carton écrasé")
    bad_fact = _fact(
        issue_type=IssueType.PRODUCT_DAMAGE, product_condition="transporteur fautif"
    )
    with pytest.raises(LiabilityAttributionError):
        screen_confirmed_facts([ok_fact, bad_fact])


# --- Intégration avec le cas d'usage F09 (confirm_facts) -------------------


def test_confirm_facts_use_case_rejects_liability_attribution_at_confirmation():
    """Le rejet doit se produire dès F09 (confirmation), pas seulement à la
    composition (F10) - retour immédiat à l'utilisateur, conformément au
    cahier des charges ('garde-fou déterministe AVANT le Reserve
    Composer')."""
    from datetime import UTC, datetime
    from uuid import uuid4

    from app.domain.entities import Incident, Issue
    from app.domain.value_objects import IncidentStatus

    repo = InMemoryIncidentRepository()
    org_id = uuid4()
    incident_id = uuid4()
    issue_id = uuid4()
    now = datetime.now(UTC)

    repo.create_incident(
        Incident(
            id=incident_id,
            organization_id=org_id,
            creator_id=uuid4(),
            status=IncidentStatus.DRAFT_LOCAL,
            local_created_at=now,
            occurred_at=now,
        ),
        idempotency_key="test-liability-guard",
    )
    repo.save_issue(
        Issue(
            id=issue_id,
            incident_id=incident_id,
            issue_type=IssueType.PACKAGING_DAMAGE.value,
            sort_order=0,
            status="open",
        )
    )

    with pytest.raises(LiabilityAttributionError):
        confirm_facts(
            repo=repo,
            organization_id=org_id,
            incident_id=incident_id,
            issue_id=issue_id,
            fact_payload={
                "issue_type": IssueType.PACKAGING_DAMAGE.value,
                "packaging_condition": "transporteur responsable",
            },
            confirmed_by=uuid4(),
            schema_version="confirmed_fact_set.v1",
        )

    # Rien n'a été persisté : la tentative rejetée ne laisse pas de trace
    # dans le repository (pas de ConfirmedFactSet orphelin).
    assert repo.latest_confirmed_fact_set(issue_id) is None
