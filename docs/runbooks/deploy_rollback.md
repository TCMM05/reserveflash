# Runbook - Déploiement et rollback (backend)

Statut : squelette R0. À enrichir en R7 - Publication (section 18) avec les
détails réels de l'environnement de production choisi (non décidé à ce
stade de la baseline).

## Pré-requis avant tout déploiement

- [ ] `python -m pytest tests -q` vert sur `backend/` (section 15.4).
- [ ] `python -m alembic check` ne rapporte aucune dérive de schéma.
- [ ] `openapi.json` régénéré et identique au commit (`scripts/generate_openapi.py`).
- [ ] Aucun secret détecté (`gitleaks`, job CI `secret-scan`).
- [ ] Image `reserveflash-backend:staging` construite avec succès (job CI
      `build-staging`).
- [ ] Checklist de recette section 19 du cahier des charges cochée.

## Déploiement

1. Construire l'image versionnée :
   ```
   docker build -f infra/docker/backend/Dockerfile -t reserveflash-backend:<tag> .
   ```
2. Appliquer les migrations AVANT de basculer le trafic (section 5.1 -
   "aucune migration manuelle production") :
   ```
   docker run --rm -e RESERVEFLASH_DATABASE_URL=... reserveflash-backend:<tag> \
     python -m alembic upgrade head
   ```
3. Déployer la nouvelle révision (mécanisme spécifique à l'hébergeur choisi -
   non figé en R0).
4. Vérifier `GET /health` sur la nouvelle révision avant bascule complète du
   trafic.

## Rollback

1. Revenir à l'image `reserveflash-backend:<tag-précédent>` (aucun downtime
   attendu côté code applicatif si les migrations de la nouvelle version
   sont rétrocompatibles - voir point 2).
2. Migrations : n'exécuter `alembic downgrade` qu'après confirmation que la
   révision précédente n'a écrit AUCUNE donnée dans un format incompatible
   avec l'ancien schéma. Par défaut, préférer un rollback applicatif seul
   (garder le nouveau schéma, qui doit être conçu rétrocompatible - additive
   only tant que la migration inverse n'a pas été testée en staging).
3. Consigner l'incident dans `CHANGELOG.md` (section "Limitations connues").

## Bon de livraison (section 17.2)

Chaque déploiement doit être accompagné du bon de livraison standard défini
section 17.2 du cahier des charges (version application, commit Git, tag,
version backend/prompt/schema/rule pack, benchmark ID + SHA-256, SHA-256
APK/AAB, environnement testé, limitations connues, décision Gate PASS/FAIL).
