from __future__ import annotations

import time
from pathlib import Path

import httpx
from fastapi import APIRouter

from app.config import settings
from clients.sportradar_client import SportradarClient, SportradarError

router = APIRouter(prefix="/admin", tags=["admin-diag"])

SUPERLIGA_SEASON_ID = "sr:season:131507"

_FIXTURES_CACHE = Path(__file__).parent / "_sr_fixtures_cache.json"
_STANDINGS_CACHE = Path(__file__).parent / "_sr_standings_cache.json"


@router.get("/sportradar/diag")
async def sportradar_diag() -> dict:
    """Probe Sportradar from inside the running backend.

    Returns the raw outcome of one season-standings call so we can see whether
    the deployed environment can actually reach Sportradar with the configured key.
    Never returns the API key value itself, only its length.
    """
    info: dict = {
        "base_url": settings.sportradar_base_url,
        "api_key_configured": bool(settings.sportradar_api_key),
        "api_key_length": len(settings.sportradar_api_key or ""),
        "season_id": SUPERLIGA_SEASON_ID,
    }

    if not settings.sportradar_api_key:
        info["status"] = "error"
        info["error_type"] = "ConfigError"
        info["error_message"] = "SPORTRADAR_API_KEY is empty in deployed env"
        return info

    client = SportradarClient()
    started = time.monotonic()
    try:
        data = await client.season_standings(SUPERLIGA_SEASON_ID)
    except SportradarError as exc:
        info["latency_ms"] = int((time.monotonic() - started) * 1000)
        info["status"] = "error"
        info["status_code"] = exc.status
        info["detail"] = exc.detail
        return info
    except Exception as exc:
        info["latency_ms"] = int((time.monotonic() - started) * 1000)
        info["status"] = "error"
        info["error_type"] = type(exc).__name__
        info["error_message"] = str(exc)[:500]
        return info

    info["latency_ms"] = int((time.monotonic() - started) * 1000)

    if not data:
        info["status"] = "empty"
        info["note"] = "Sportradar returned None or empty body"
        return info

    standings = data.get("standings", []) or []
    group_names: list[str] = []
    for standing in standings:
        if standing.get("type") != "total":
            continue
        for group in standing.get("groups", []) or []:
            name = group.get("name", "")
            rows = group.get("standings", []) or []
            group_names.append(f"{name} ({len(rows)} teams)")

    info["status"] = "ok"
    info["groups_count"] = len(group_names)
    info["groups"] = group_names
    return info


@router.get("/sportradar/raw")
async def sportradar_raw() -> dict:
    """Single raw httpx call to Sportradar, no retries, 30s timeout.

    Bypasses SportradarClient so we see exactly what one call does from inside
    App Runner: real status code, body snippet, elapsed time.
    """
    info: dict = {
        "base_url": settings.sportradar_base_url,
        "api_key_configured": bool(settings.sportradar_api_key),
        "api_key_length": len(settings.sportradar_api_key or ""),
    }
    if not settings.sportradar_api_key:
        info["status"] = "error"
        info["error_message"] = "SPORTRADAR_API_KEY is empty"
        return info

    url = f"{settings.sportradar_base_url.rstrip('/')}/seasons/sr%3Aseason%3A131507/standings.json"
    started = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, params={"api_key": settings.sportradar_api_key})
        info["latency_ms"] = int((time.monotonic() - started) * 1000)
        info["status_code"] = resp.status_code
        body = resp.text or ""
        info["body_length"] = len(body)
        info["body_snippet"] = body[:300]
        return info
    except httpx.TimeoutException as exc:
        info["latency_ms"] = int((time.monotonic() - started) * 1000)
        info["status"] = "timeout"
        info["error_message"] = str(exc)[:300]
        return info
    except Exception as exc:
        info["latency_ms"] = int((time.monotonic() - started) * 1000)
        info["status"] = "error"
        info["error_type"] = type(exc).__name__
        info["error_message"] = str(exc)[:500]
        return info


@router.post("/cache/clear")
async def cache_clear() -> dict:
    """Delete on-disk Sportradar cache files. Endpoints will refetch on next call."""
    cleared: list[str] = []
    for path in (_FIXTURES_CACHE, _STANDINGS_CACHE):
        if path.exists():
            try:
                path.unlink()
                cleared.append(path.name)
            except Exception as exc:
                cleared.append(f"{path.name} (failed: {exc})")
    return {"cleared": cleared}
