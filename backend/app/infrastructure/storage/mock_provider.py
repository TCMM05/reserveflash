"""Adapter storage de développement/tests - stockage en mémoire, aucun bucket
réel. Implémente app.application.ports.StorageProvider.

À remplacer par un adapter S3-compatible / Supabase Storage réel en
changeant RESERVEFLASH_STORAGE_PROVIDER (section 5.1). Respecte la même
contrainte que la cible réelle : jamais d'URL publique permanente (SEC-03).
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

from app.application.ports import PresignedUpload, StorageProvider, UploadConfirmation


@dataclass
class _InMemoryObject:
    content_type: str
    bytes_written: bytes = b""


@dataclass
class MockStorageProvider(StorageProvider):
    """Garde tout en mémoire process ; parfaitement suffisant pour les tests
    et le développement local sans dépendance externe."""

    _objects: dict[str, _InMemoryObject] = field(default_factory=dict)

    def create_presigned_upload(
        self, *, organization_id: UUID, incident_id: UUID, content_type: str
    ) -> PresignedUpload:
        object_key = f"org/{organization_id}/incidents/{incident_id}/{uuid.uuid4()}"
        self._objects[object_key] = _InMemoryObject(content_type=content_type)
        return PresignedUpload(
            upload_url=f"mock://upload/{object_key}",
            object_key=object_key,
            expires_at=datetime.now(UTC) + timedelta(seconds=300),
            fields={"key": object_key},
        )

    def write_for_test(self, object_key: str, payload: bytes) -> None:
        """Aide de test uniquement : simule l'écriture faite par le client
        directement sur l'URL signée (jamais via ce backend en production)."""
        default = _InMemoryObject(content_type="application/octet-stream")
        obj = self._objects.setdefault(object_key, default)
        obj.bytes_written = payload

    def confirm_upload(self, object_key: str) -> UploadConfirmation:
        obj = self._objects.get(object_key)
        if obj is None:
            raise KeyError(f"Objet inconnu : {object_key}")
        digest = hashlib.sha256(obj.bytes_written).hexdigest()
        return UploadConfirmation(
            object_key=object_key,
            sha256=digest,
            bytes=len(obj.bytes_written),
            mime_type=obj.content_type,
        )

    def create_signed_download(self, object_key: str, ttl_seconds: int = 300) -> str:
        if object_key not in self._objects:
            raise KeyError(f"Objet inconnu : {object_key}")
        return f"mock://download/{object_key}?ttl={ttl_seconds}"

    def delete(self, object_key: str) -> None:
        self._objects.pop(object_key, None)

    def put_object(
        self,
        *,
        organization_id: UUID,
        incident_id: UUID,
        data: bytes,
        content_type: str,
        key_hint: str,
    ) -> UploadConfirmation:
        object_key = f"org/{organization_id}/incidents/{incident_id}/{key_hint}/{uuid.uuid4()}"
        self._objects[object_key] = _InMemoryObject(content_type=content_type, bytes_written=data)
        return UploadConfirmation(
            object_key=object_key,
            sha256=hashlib.sha256(data).hexdigest(),
            bytes=len(data),
            mime_type=content_type,
        )
