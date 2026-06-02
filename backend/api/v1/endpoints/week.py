from __future__ import annotations

import asyncio
import json
import logging
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, Query, Request

from app.config import effective_now, effective_season_id, settings
from clients.sportradar_client import SportradarClient
from core.dependencies import get_feature_service
from core.security import get_current_user
from services.explanation_service import ExplanationService
from services.feature_service import FeatureService
from services.fixture_service import FixtureService
from services.model_service import ModelService
from services.prescription_service import PrescriptionService

logger = logging.getLogger(__name__)

router = APIRouter()

TRACKED_TEAM_ID = "sr:competitor:7734"
SUPERLIGA_COMPETITION_ID = "sr:competition:152"
TRACKED_TEAM_NAME = "Universitatea Cluj"

# Cache file next to this module; TTL of 6 h (matches happen every few days)
_CACHE_PATH = Path(__file__).parent / "_sr_fixtures_cache.json"
_CACHE_TTL_SECONDS = 6 * 3600


def _ucluj_is_home(home_team: str, away_team: str) -> bool:
    home = str(home_team or "").strip().lower()
    return ("u cluj" in home) or ("universitatea cluj" in home)


def _to_ucluj_win_prob(home_win_prob: float, home_team: str, away_team: str) -> float:
    """Convert P(Home Win) → P(U Cluj Win) for this fixture."""
    if _ucluj_is_home(home_team, away_team):
        return home_win_prob
    return 1.0 - home_win_prob


def _dampen_probability(prob: float, weight: float = 0.55) -> float:
    """Reduce overconfident extremes toward 50% for UI trust/readability."""
    p = max(0.0, min(1.0, float(prob)))
    damped = 0.5 + (p - 0.5) * weight
    return max(0.10, min(0.90, damped))


def _fixture_service(request: Request) -> FixtureService:
    return FixtureService(request.app.state.df, request.app.state.stadium_map)


# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------

def _load_cache() -> list[dict] | None:
    """Return cached fixtures if cache exists and is fresh, else None."""
    try:
        if not _CACHE_PATH.exists():
            return None
        data = json.loads(_CACHE_PATH.read_text(encoding="utf-8"))
        cached_at = datetime.fromisoformat(data["cached_at"])
        age = (datetime.now(timezone.utc) - cached_at).total_seconds()
        if age > _CACHE_TTL_SECONDS:
            return None
        return data["fixtures"]
    except Exception:
        return None


def _save_cache(fixtures: list[dict]) -> None:
    try:
        _CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "cached_at": datetime.now(timezone.utc).isoformat(),
            "fixtures": fixtures,
        }
        _CACHE_PATH.write_text(json.dumps(payload, default=str), encoding="utf-8")
    except Exception as exc:
        logger.warning("Could not write fixture cache: %s", exc)


# ---------------------------------------------------------------------------
# Main endpoint
# ---------------------------------------------------------------------------

@router.get("/week-fixtures")
async def week_fixtures(
    request: Request,
    _user=Depends(get_current_user),
    feature_svc: FeatureService = Depends(get_feature_service),
    week_offset: int = Query(default=0, ge=-52, le=52),
):
    """Return Liga 1 fixtures for the requested week with U Cluj-centric ML predictions.

    week_offset=0 → current week, week_offset=1 → next week, etc.
    home_win_probability in each response item is P(U Cluj Win), not P(Home Win).
    key_drivers and top_risks are from U Cluj's perspective regardless of home/away.
    """
    now = effective_now()
    this_monday = (now - timedelta(days=now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    monday = this_monday + timedelta(weeks=week_offset)
    sunday = monday + timedelta(days=7)

    # ── 1. Check local Sportradar cache (instant if fresh) ──────────────────
    # The cache is skipped in demo mode so a stale production response never
    # bleeds into a demo dashboard (and vice versa). The cache write below
    # is gated the same way.
    sr_all: list[dict] | None = None if settings.demo_mode else _load_cache()

    # ── 2. If cache stale/missing, try Sportradar (cap at 20 s total) ──────
    # Demo mode now hits Sportradar too, pinned to the 2024-25 season via
    # effective_season_id(); the cache write below is the only place demo
    # mode still diverges from production.
    if sr_all is None and settings.sportradar_api_key:
        try:
            fetched = await asyncio.wait_for(
                _fetch_all_sr_fixtures(),
                timeout=20.0,
            )
            if fetched:
                sr_all = fetched
                if not settings.demo_mode:
                    _save_cache(sr_all)  # persist for next 6 h
        except Exception as exc:
            logger.warning("Sportradar fetch failed/timed-out; using CSV fallback: %s", exc)

    # ── 3. Slice the cached/live Sportradar list to this week + nearest ─────
    if sr_all:
        fixtures = _slice_fixtures(sr_all, monday, sunday)
    else:
        # Fall back to in-memory CSV (no network, always instant)
        fix_svc = _fixture_service(request)
        fixtures = _csv_week_fixtures(fix_svc, monday, sunday)

    # ── 3b. Demo horizon ────────────────────────────────────────────────────
    # The 2024-2025 dataset is fully played, so every fixture carries a
    # final score. For the committee demo we want fixtures dated after the
    # pinned demo "now" to render as "not yet played" so the pre-match flow
    # (win probability + drivers + tactical blueprint) lights up. The
    # downstream is_completed check in _compute_predictions then routes
    # them through the prescription path automatically.
    if settings.demo_mode:
        fixtures = _apply_demo_horizon(fixtures, effective_now())

    # ── 4. ML predictions (offloaded to thread pool — CPU-bound) ────────────
    model_svc = ModelService(getattr(request.app.state, "bundle", None))
    expl_svc = ExplanationService(model_svc)
    presc_svc = PrescriptionService(model_svc)

    def _compute_predictions(fixtures_list: list[dict]) -> list[dict]:
        result = []
        for f in fixtures_list:
            item = dict(f)
            try:
                if model_svc.is_ready:
                    feat = feature_svc.build_feature_vector(
                        f["home_team"], f["away_team"], model_svc.feature_cols
                    )
                    raw_home_prob = float(model_svc.predict_proba(feat))
                    ucl_prob = _to_ucluj_win_prob(raw_home_prob, f["home_team"], f["away_team"])
                    ui_prob = _dampen_probability(ucl_prob)
                    ucl_is_home = _ucluj_is_home(f["home_team"], f["away_team"])

                    expl = expl_svc.explain(feat, ui_prob, ucl_is_home=ucl_is_home)

                    is_completed = f.get("home_score") is not None and f.get("away_score") is not None
                    if not is_completed:
                        presc = presc_svc.prescribe(feat, ucl_is_home=ucl_is_home)
                        narrative = presc["text"] if presc["text"] else expl["narrative"]
                        prescription = presc.get("structured")
                    else:
                        narrative = ""
                        prescription = None

                    item["home_win_probability"] = round(ui_prob, 4)
                    item["key_drivers"] = expl["top_drivers"][:3]
                    item["top_risks"] = expl["top_risks"][:2]
                    item["narrative"] = narrative
                    item["prescription"] = prescription
                else:
                    item["home_win_probability"] = None
                    item["key_drivers"] = []
                    item["top_risks"] = []
                    item["narrative"] = (
                        "Modelul predictiv este temporar indisponibil."
                    )
                    item["prescription"] = None
            except Exception:
                logger.warning(
                    "Prediction failed for %s vs %s",
                    f.get("home_team"),
                    f.get("away_team"),
                    exc_info=True,
                )
                item["home_win_probability"] = None
                item["key_drivers"] = []
                item["top_risks"] = []
                item["narrative"] = ""
                item["prescription"] = None
            result.append(item)
        return result

    result = await asyncio.to_thread(_compute_predictions, fixtures)
    # The prescriptive optimiser and the explanation service can produce NaN
    # or +/-Inf for edge-case feature vectors (e.g. a team with too few rolling
    # samples in the demo horizon). Strict JSON has no representation for
    # those, so Starlette's serialiser would 500 the whole response. Sanitise
    # them to None so the rest of the payload still reaches the client.
    return _sanitize_floats(result)


# ---------------------------------------------------------------------------
# Sportradar: fetch the whole-season schedule (cached for 6 h)
# ---------------------------------------------------------------------------

async def _fetch_all_sr_fixtures() -> list[dict]:
    """Fetch the full season schedule from Sportradar.

    Uses ``season_schedules(effective_season_id())`` so the demo mode lands
    on the 2024-25 season and production lands on the 25/26 season. Returns
    every Superliga fixture in the season (past + future) so the dashboard
    can render both the U-Cluj-this-week section and the "other Liga 1"
    section without an extra hop. Past matches with no score (postponed or
    cancelled) are filtered out.
    """
    client = SportradarClient()
    data = await client.season_schedules(effective_season_id())
    fixtures: list[dict] = []
    now = datetime.now(timezone.utc)

    for raw_evt in (data or {}).get("schedules", []):
        se = raw_evt.get("sport_event", {})
        status = raw_evt.get("sport_event_status", {})
        ctx = se.get("sport_event_context", {})
        comp = ctx.get("competition", {})
        if comp.get("id") != SUPERLIGA_COMPETITION_ID:
            continue

        competitors = se.get("competitors", [])
        home = _find_qualifier(competitors, "home")
        away = _find_qualifier(competitors, "away")
        if not home or not away:
            continue

        kickoff = _event_kickoff(se)
        home_score = status.get("home_score")
        away_score = status.get("away_score")

        # Skip past matches with no score — they were postponed/cancelled
        match_dt = _parse_dt(kickoff)
        if match_dt < now and home_score is None:
            continue

        fixtures.append({
            "match_id": se.get("id", ""),
            "season": (ctx.get("season", {}) or {}).get("id", ""),
            "match_date": kickoff,
            "home_team": home.get("name", ""),
            "away_team": away.get("name", ""),
            "home_score": home_score,
            "away_score": away_score,
            "venue": (se.get("venue", {}) or {}).get("name", ""),
        })

    fixtures.sort(key=lambda f: f.get("match_date", ""))
    return fixtures


def _slice_fixtures(all_fixtures: list[dict], monday: datetime, sunday: datetime) -> list[dict]:
    """Return this week's fixtures; fall back to nearest past + next upcoming."""
    week = [
        f for f in all_fixtures
        if monday <= _parse_dt(f.get("match_date", "")) < sunday
    ]
    if week:
        return week

    past = [f for f in all_fixtures if _parse_dt(f.get("match_date", "")) < monday]
    future = [f for f in all_fixtures if _parse_dt(f.get("match_date", "")) >= sunday]
    out: list[dict] = []
    if past:
        out.append(past[-1])
    if future:
        out.append(future[0])
    return out


# ---------------------------------------------------------------------------
# CSV-based fixture source (instant fallback, no network)
# ---------------------------------------------------------------------------

def _sanitize_floats(value: Any) -> Any:
    """Recursively replace NaN and +/-Inf floats with None.

    Strict JSON (RFC 8259) does not allow non-finite floats, and Starlette's
    response renderer trips on them with
    ``ValueError: Out of range float values are not JSON compliant``. The
    prescription pipeline can emit NaN when a feature vector lacks enough
    rolling samples to compute an uplift; this helper keeps the rest of the
    response intact instead of failing the whole request.
    """
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    if isinstance(value, dict):
        return {k: _sanitize_floats(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize_floats(v) for v in value]
    if isinstance(value, tuple):
        return tuple(_sanitize_floats(v) for v in value)
    return value


def _apply_demo_horizon(fixtures: list[dict], horizon: datetime) -> list[dict]:
    """Null out scores for fixtures dated strictly after ``horizon``.

    The 2024-25 dataset carries a final score for every fixture because the
    season is fully played. Demo mode wants the coach to walk through the
    pre-match flow (Match Intelligence, tactical blueprint, recommended XI)
    on fixtures the demo treats as "upcoming," which means stripping the
    scores from anything after the pinned demo date so
    ``_compute_predictions`` routes them through the ``not is_completed``
    branch and produces a prescription.

    Returns a NEW list of fixture dicts; the input list and any cached
    Sportradar payload underneath it stay unchanged.
    """
    result: list[dict] = []
    for f in fixtures:
        match_dt = _parse_dt(f.get("match_date", ""))
        if match_dt > horizon:
            f = dict(f)
            f["home_score"] = None
            f["away_score"] = None
        result.append(f)
    return result


def _csv_week_fixtures(fix_svc: FixtureService, monday: datetime, sunday: datetime) -> list[dict]:
    """Return every Liga 1 fixture inside [monday, sunday) from the in-memory CSV.

    Previously this only returned U Cluj fixtures, which made the dashboard's
    "Alte meciuri" section permanently empty whenever U Cluj had no match in
    the requested week. Now it widens to the whole league for the season that
    contains the window (derived from the monday parameter), so the dashboard
    populates even on a U Cluj rest week. If the week is genuinely empty we
    still fall back to the nearest U Cluj match either side.
    """
    season_str = str(monday.year if monday.month >= 7 else monday.year - 1)
    week = fix_svc.list_week_fixtures(monday, sunday, season=season_str)
    if week:
        return week

    # Nothing in the requested window. Fall back to the nearest U Cluj
    # fixture either side so the screen is not completely empty.
    all_ucluj = fix_svc.list_fixtures(team=TRACKED_TEAM_NAME, limit=500)
    past = [f for f in all_ucluj if _parse_dt(f.get("match_date", "")) < monday]
    future = [f for f in all_ucluj if _parse_dt(f.get("match_date", "")) >= sunday]
    out: list[dict] = []
    if past:
        out.append(past[-1])
    if future:
        out.append(future[0])
    return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_dt(val) -> datetime:
    if isinstance(val, datetime):
        return val if val.tzinfo else val.replace(tzinfo=timezone.utc)
    try:
        s = str(val)
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return datetime(1970, 1, 1, tzinfo=timezone.utc)


def _find_qualifier(competitors: list[dict], qualifier: str) -> dict | None:
    for c in competitors:
        if c.get("qualifier") == qualifier:
            return c
    return None


def _event_kickoff(sport_event: dict) -> str:
    return (
        sport_event.get("scheduled")
        or sport_event.get("start_time")
        or ""
    )
