"""Chargement et validation des RulePack (rulepacks/*.yaml à la racine du
monorepo - section 5.2). Aucune règle n'est jamais lue depuis un prompt LLM
(section 11.1) : uniquement depuis ces fichiers versionnés dans le dépôt."""

from __future__ import annotations

import pathlib

import yaml

from app.domain.rule_pack import RulePack, RulePackStatus

# reserveflash/backend/app/infrastructure/rulepacks/loader.py -> reserveflash/rulepacks/
_DEFAULT_RULEPACKS_DIR = pathlib.Path(__file__).resolve().parents[4] / "rulepacks"


def load_all_rule_packs(directory: pathlib.Path = _DEFAULT_RULEPACKS_DIR) -> list[RulePack]:
    packs: list[RulePack] = []
    for path in sorted(directory.glob("*.yaml")):
        with path.open(encoding="utf-8") as f:
            raw = yaml.safe_load(f)
        packs.append(RulePack.model_validate(raw))
    return packs


def list_active_rule_packs(directory: pathlib.Path = _DEFAULT_RULEPACKS_DIR) -> list[RulePack]:
    """section 11.3 : seuls les packs ACTIVE peuvent produire des rappels
    visibles. Aucune activation automatique - un pack le devient uniquement
    via une revue humaine qui modifie le fichier source (section 18.1)."""
    return [p for p in load_all_rule_packs(directory) if p.status is RulePackStatus.ACTIVE]
