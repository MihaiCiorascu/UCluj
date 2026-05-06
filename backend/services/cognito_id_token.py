from __future__ import annotations

import time
import threading
from typing import Any

import httpx
from jose import jwt, JWTError

from app.config import settings

_lock = threading.Lock()
_jwks_cache: dict[str, Any] = {}
_jwks_fetched_at: float = 0.0
_JWKS_TTL = 3600  # 1 hour


def _jwks_url() -> str:
    return (
        f"https://cognito-idp.{settings.cognito_region}.amazonaws.com"
        f"/{settings.cognito_user_pool_id}/.well-known/jwks.json"
    )


def _get_jwks() -> dict:
    global _jwks_cache, _jwks_fetched_at
    with _lock:
        if time.time() - _jwks_fetched_at < _JWKS_TTL and _jwks_cache:
            return _jwks_cache
        resp = httpx.get(_jwks_url(), timeout=10)
        resp.raise_for_status()
        _jwks_cache = resp.json()
        _jwks_fetched_at = time.time()
        return _jwks_cache


def verify_id_token(id_token: str) -> dict:
    if not settings.cognito_user_pool_id:
        raise RuntimeError("COGNITO_USER_POOL_ID is not configured")

    jwks = _get_jwks()
    issuer = (
        f"https://cognito-idp.{settings.cognito_region}.amazonaws.com"
        f"/{settings.cognito_user_pool_id}"
    )

    try:
        claims = jwt.decode(
            id_token,
            jwks,
            algorithms=["RS256"],
            audience=settings.cognito_app_client_id,
            issuer=issuer,
        )
    except JWTError as exc:
        raise ValueError(f"Invalid Cognito token: {exc}") from exc

    return claims
