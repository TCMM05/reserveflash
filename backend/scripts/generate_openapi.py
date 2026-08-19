#!/usr/bin/env python3
"""Régénère backend/openapi.json à partir de l'app FastAPI.

section 9.2 : "OpenAPI commité/généré et utilisé pour tests contractuels."
À exécuter après tout changement de schéma de requête/réponse (app/api/schemas.py)
ou de route (app/api/routes/*.py) ; le fichier généré est commité dans le dépôt.
"""

from __future__ import annotations

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from app.main import create_app  # noqa: E402


def main() -> None:
    app = create_app()
    output = pathlib.Path(__file__).resolve().parents[1] / "openapi.json"
    payload = json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"
    output.write_text(payload, encoding="utf-8")
    print(f"OpenAPI écrit dans {output}")


if __name__ == "__main__":
    main()
