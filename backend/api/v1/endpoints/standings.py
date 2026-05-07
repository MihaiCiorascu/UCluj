from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, Query, Request

from app.config import settings
from clients.sportradar_client import SportradarClient
from core.dependencies import get_feature_service, get_stadium_map
from core.models import StandingsRow
from core.security import get_current_user
from services.feature_service import FeatureService
from services.fixture_service import FixtureService

logger = logging.getLogger(__name__)

router = APIRouter()

SUPERLIGA_SEASON_ID = "sr:season:131507"   # Superliga 25/26
SUPERLIGA_GROUP_REGULAR = "Superliga"
SUPERLIGA_GROUP_CHAMPIONSHIP = "Championship Round"
SUPERLIGA_GROUP_RELEGATION = "Relegation Round"

_CACHE_PATH = Path(__file__).parent / "_sr_standings_cache.json"
_CACHE_TTL_SECONDS = 6 * 3600  # refresh every 6 h (one matchday = several hours apart)


def _get_fixture_service(
    feature_svc: FeatureService = Depends(get_feature_service),
    stadium_map: dict = Depends(get_stadium_map),
) -> FixtureService:
    return FixtureService(feature_svc._df, stadium_map)


# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------

def _load_cache() -> list[dict] | None:
    try:
        if not _CACHE_PATH.exists():
            return None
        data = json.loads(_CACHE_PATH.read_text(encoding="utf-8"))
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(data["cached_at"])).total_seconds()
        if age > _CACHE_TTL_SECONDS:
            return None
        return data["standings"]
    except Exception:
        return None


def _save_cache(rows: list[dict]) -> None:
    try:
        _CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        _CACHE_PATH.write_text(
            json.dumps({"cached_at": datetime.now(timezone.utc).isoformat(), "standings": rows}),
            encoding="utf-8",
        )
    except Exception as exc:
        logger.warning("Could not write standings cache: %s", exc)


# ---------------------------------------------------------------------------
# Sportradar standings fetch
# ---------------------------------------------------------------------------

async def _fetch_sr_standings() -> list[dict] | None:
    if not settings.sportradar_api_key:
        return None
    client = SportradarClient()
    data = await client.season_standings(SUPERLIGA_SEASON_ID)
    if not data:
        return None

    groups_by_name: dict[str, list] = {}
    for standing in data.get("standings", []):
        if standing.get("type") != "total":
            continue
        for group in standing.get("groups", []):
            groups_by_name[group.get("name", "")] = group.get("standings", [])

    def _parse_group(raw_rows: list) -> list[dict]:
        rows = []
        for row in raw_rows:
            competitor = row.get("competitor", {})
            gf = row.get("goals_for") or 0
            ga = row.get("goals_against") or 0
            rows.append({
                "position": row.get("rank"),
                "team": competitor.get("name", ""),
                "played": row.get("played"),
                "wins": row.get("win"),
                "draws": row.get("draw"),
                "losses": row.get("loss"),
                "goals_for": gf,
                "goals_against": ga,
                "goal_difference": (row.get("goal_diff") if row.get("goal_diff") is not None else gf - ga),
                "points": row.get("points"),
            })
        rows.sort(key=lambda r: r["position"] or 99)
        return rows

    return {
        "regular": _parse_group(groups_by_name.get(SUPERLIGA_GROUP_REGULAR, [])),
        "championship": _parse_group(groups_by_name.get(SUPERLIGA_GROUP_CHAMPIONSHIP, [])),
        "relegation": _parse_group(groups_by_name.get(SUPERLIGA_GROUP_RELEGATION, [])),
    }


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------

@router.get("/standings")
async def standings(
    request: Request,
    season: str | None = Query(None),
    _user=Depends(get_current_user),
    svc: FixtureService = Depends(_get_fixture_service),
):
    # 1. Try fresh cache
    cached = _load_cache()
    if cached is not None:
        return cached

    # 2. Fetch from Sportradar (cap at 5 s)
    if settings.sportradar_api_key:
        try:
            sr_data = await asyncio.wait_for(_fetch_sr_standings(), timeout=25.0)
            if sr_data:
                _save_cache(sr_data)
                return sr_data
        except Exception:
            logger.warning("Sportradar standings fetch failed; falling back to CSV")

    # 3. Instant CSV fallback — wrap in the same grouped format
    csv_rows = svc.standings(season=season)
    return {"regular": csv_rows, "championship": [], "relegation": []}
