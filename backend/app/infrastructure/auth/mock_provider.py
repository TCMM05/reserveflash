"""Adapter auth de développement/tests. Implémente
app.application.ports.AuthProvider avec un registre en mémoire de tokens ->
AuthContext, sans dépendance à Supabase Auth ni à un serveur JWT réel.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID

from app.application.ports import AuthContext, AuthProvider


class InvalidTokenError(Exception):
    """Mappée en 401 AUTH_REQUIRED côté API (section 9.3)."""


@dataclass
class MockAuthProvider(AuthProvider):
    _tokens: dict[str, AuthContext] = field(default_factory=dict)

    def register_token_for_test(
        self, token: str, *, user_id: UUID, organization_id: UUID, role: str = "MEMBER"
    ) -> None:
        self._tokens[token] = AuthContext(
            user_id=user_id, organization_id=organization_id, role=role
        )

    def verify_token(self, token: str) -> AuthContext:
        context = self._tokens.get(token)
        if context is None:
            raise InvalidTokenError("Token invalide, expiré ou révoqué.")
        return context

    def create_magic_link(self, email: str) -> str:
        return f"mock://magic-link?email={email}"
