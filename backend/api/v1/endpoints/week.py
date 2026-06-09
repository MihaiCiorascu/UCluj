from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import math
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, Query, Request

from app.config import effective_now, effective_season, effective_season_id, settings
from clients.sportradar_client import SportradarClient
from core.dependencies import get_feature_service
from core.security import get_current_user
from services import baked_fixtures
from services.explanation_service import ExplanationService
from services.feature_service import FeatureService
from services.fixture_service import FixtureService
from services.model_service import ModelService
from services.prescription_service import PrescriptionService
from sportradar.team_registry import TeamRef, team_by_alias

logger = logging.getLogger(__name__)

router = APIRouter()

TRACKED_TEAM_ID = "sr:competitor:7734"
SUPERLIGA_COMPETITION_ID = "sr:competition:152"
TRACKED_TEAM_NAME = "Universitatea Cluj"

# Cache file next to this module; TTL of 6 h (matches happen every few days)
_CACHE_PATH = Path(__file__).parent / "_sr_fixtures_cache.json"
_CACHE_TTL_SECONDS = 6 * 3600

# In-process cache for the computed week predictions. The heavy cost in
# /week-fixtures is the per-fixture Monte Carlo prescription, which is
# deterministic given the fixtures plus the (static) model and feature data.
# The cache is keyed on the post-horizon fixture state (teams + scores), so a
# score update or a different week busts it automatically; the TTL is only a
# backstop. The startup pre-warm populates the current week, so even the first
# dashboard load is instant.
_PRED_CACHE: dict[str, tuple[float, list[dict]]] = {}
_PRED_CACHE_TTL_SECONDS = 6 * 3600


def _resolve_subject(user) -> TeamRef | None:
    """The analytical subject: the authenticated user's club, falling back to
    Universitatea Cluj when the user has no (or an unrecognised) club set."""
    name = (getattr(user, "team_name", None) or "").strip()
    return team_by_alias(name) or team_by_alias(TRACKED_TEAM_NAME)


def _is_subject(team_str: str, subject: TeamRef | None) -> bool:
    """True when a fixture team name resolves to the subject club."""
    if subject is None:
        return False
    ref = team_by_alias(team_str)
    return ref is not None and ref.short == subject.short


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


def _predictions_signature(week_offset: int, fixtures: list[dict], subject_short: str = "") -> str:
    """Stable cache key for a week's computed predictions.

    Encodes the subject club, the week, and each fixture's identity plus score, so
    the cache is reused only while those are unchanged and recomputes the moment a
    score lands, a different week is requested, or a different subject views it.
    """
    parts = [str(subject_short), str(week_offset)]
    for f in fixtures:
        parts.append("|".join((
            str(f.get("match_id", "")),
            str(f.get("home_team", "")),
            str(f.get("away_team", "")),
            str(f.get("home_score")),
            str(f.get("away_score")),
        )))
    return hashlib.md5("\n".join(parts).encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Main endpoint
# ---------------------------------------------------------------------------

@router.get("/week-fixtures")
async def week_fixtures(
    request: Request,
    _user=Depends(get_current_user),
    week_offset: int = Query(default=0, ge=-52, le=52),
):
    """Return Liga 1 fixtures with subject-team-centric ML predictions.

    The analytical subject is the authenticated user's club (``team_name``),
    defaulting to Universitatea Cluj when unset. For the baked 2025-26 season the
    ``week_offset`` is reinterpreted as a ROUND offset: 0 is the current round
    (resolved from the server's effective clock), -1 the previous round, +1 the
    next, clamped to [1, 33]. Every fixture of the resolved round is returned, each
    carrying ``round`` and ``phase``. For historical seasons the offset keeps its
    Mon-Sun week-window meaning against All_Data.csv. Sportradar is never called.

    home_win_probability in each item is P(Subject Team Win), not P(Home Win), and
    key_drivers / top_risks are from the subject team's perspective regardless of
    whether it plays home or away.
    """
    st = request.app.state
    subject = _resolve_subject(_user)
    return await _compute_week(
        st.df, st.stadium_map, getattr(st, "bundle", None), week_offset, subject
    )


async def _compute_week(
    df, stadium_map: dict, bundle, week_offset: int,
    subject: TeamRef | None = None,
) -> list[dict]:
    """Slice the requested week's fixtures, attach subject-team-centric ML
    predictions, and memoise the result.

    ``subject`` is the analytical subject club; when None (e.g. the startup
    pre-warm) it defaults to Universitatea Cluj. Extracted from the endpoint so the
    pre-warm can populate the same in-process cache (_PRED_CACHE). The expensive
    step is the per-fixture Monte Carlo prescription; it runs only on a cache miss
    (a new round, a changed score, or a different subject). Returns the sanitised,
    client-ready list.
    """
    if subject is None:
        subject = team_by_alias(TRACKED_TEAM_NAME)
    subject_short = subject.short if subject else TRACKED_TEAM_NAME
    now = effective_now()

    # 1. Fixture source. The 2025-26 season is served from the committed baked
    # dataset (no Sportradar, no CSV): the offset is reinterpreted as a ROUND
    # offset and ALL fixtures of the resolved round are returned, each carrying
    # round + phase. Historical seasons keep the Mon-Sun CSV window below.
    if baked_fixtures.is_baked_season(effective_season()):
        resolved_round = baked_fixtures.round_for_offset(now, week_offset)
        fixtures = baked_fixtures.fixtures_for_round(resolved_round)
    else:
        this_monday = (now - timedelta(days=now.weekday())).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        monday = this_monday + timedelta(weeks=week_offset)
        sunday = monday + timedelta(days=7)

        # Sportradar fixtures: served from the on-disk cache, fetched once
        # (capped at 20 s) when stale. Caching matters because the trial tier
        # answers a multi-week dashboard burst with 429s.
        sr_all: list[dict] | None = _load_cache()
        if sr_all is None and settings.sportradar_api_key:
            try:
                fetched = await asyncio.wait_for(_fetch_all_sr_fixtures(), timeout=20.0)
                if fetched:
                    sr_all = fetched
                    _save_cache(sr_all)
            except Exception as exc:
                logger.warning("Sportradar fetch failed/timed-out; using CSV fallback: %s", exc)

        # Slice to the week; fall back to the in-memory CSV when Sportradar is
        # unavailable (no network, always instant).
        if sr_all:
            fixtures = _slice_fixtures(sr_all, monday, sunday)
        else:
            fixtures = _csv_week_fixtures(FixtureService(df, stadium_map), monday, sunday, subject_short)

    # 3b. Demo horizon: treat fixtures dated after the pinned demo "now" as not
    # yet played, so the pre-match flow (win probability + drivers + blueprint)
    # lights up and the prescription branch below runs for them.
    if settings.demo_mode:
        fixtures = _apply_demo_horizon(fixtures, now)

    # 3c. Cache: the signature captures the post-horizon fixture state, so a
    # score change or a different week recomputes; otherwise this returns
    # instantly and skips the per-fixture Monte Carlo below.
    cache_key = _predictions_signature(week_offset, fixtures, subject_short)
    hit = _PRED_CACHE.get(cache_key)
    if hit is not None and (time.monotonic() - hit[0]) < _PRED_CACHE_TTL_SECONDS:
        return hit[1]

    # 4. ML predictions (offloaded to a thread; CPU-bound).
    feature_svc = FeatureService(df)
    model_svc = ModelService(bundle)
    expl_svc = ExplanationService(model_svc)
    presc_svc = PrescriptionService(model_svc)

    def _compute_predictions(fixtures_list: list[dict]) -> list[dict]:
        result = []
        for f in fixtures_list:
            item = dict(f)
            # Subject identity for the client, independent of prediction success:
            # True when the user's club is the home side, False when away, None
            # when the fixture does not involve the subject club. The frontend uses
            # this to decide which fixtures are "my team" and which side to feature.
            _sub_home = _is_subject(f.get("home_team", ""), subject)
            item["subject_is_home"] = _sub_home if (
                _sub_home or _is_subject(f.get("away_team", ""), subject)
            ) else None
            try:
                if model_svc.is_ready:
                    home_team = f["home_team"]
                    away_team = f["away_team"]
                    # The baked dataset stores registry shorts (e.g. "U Cluj",
                    # "Oţelul Galaţi"); the CatBoost feature lookup is keyed on
                    # the All_Data.csv canonical names. Normalise to the canonical
                    # names for every model/feature call, while the response and
                    # the U-Cluj detection keep the original shorts. For the
                    # Sportradar/CSV paths these names are already canonical, so
                    # the map is a no-op there.
                    home_lookup = baked_fixtures.canonical_team_name(home_team)
                    away_lookup = baked_fixtures.canonical_team_name(away_team)
                    involves_subject = _is_subject(home_team, subject) or _is_subject(
                        away_team, subject
                    )

                    if involves_subject:
                        # ── Subject fixture: subject-centric diagnostic + blueprint ──
                        subject_is_home = _is_subject(home_team, subject)
                        # P(subject win) computed DIRECTLY by placing the subject in
                        # the home slot of the feature vector, whether it actually
                        # plays home or away. This replaces the old
                        # `1 - P(home win)` complement, which for a subject-away
                        # fixture folded draws into the subject's win share (the
                        # binary model's complement is P(subject win OR draw)) and
                        # overstated them.
                        if subject_is_home:
                            subj_lookup, opp_lookup = home_lookup, away_lookup
                        else:
                            subj_lookup, opp_lookup = away_lookup, home_lookup
                        subject_prob = feature_svc.win_prob(model_svc, subj_lookup, opp_lookup)

                        # The diagnostic / blueprint is still built from the real
                        # home-vs-away vector so its directional drivers read
                        # correctly for the fixture as played.
                        feat = feature_svc.build_feature_vector(
                            home_lookup, away_lookup, model_svc.feature_cols
                        )

                        is_completed = (
                            f.get("home_score") is not None
                            and f.get("away_score") is not None
                        )
                        if not is_completed:
                            presc = presc_svc.prescribe(feat, subject_is_home=subject_is_home)
                            prescription = presc.get("structured")
                            # The headline win chance must equal the diagnostic
                            # baseline shown in the same card. The prescription
                            # computes that baseline from the identical model and
                            # feature vector, so reuse it verbatim; previously the
                            # headline was dampened toward 50% while the baseline
                            # stayed raw, so the two numbers disagreed.
                            if prescription and prescription.get("baseline_prob") is not None:
                                subject_prob = float(prescription["baseline_prob"])
                        else:
                            presc = None
                            prescription = None

                        expl = expl_svc.explain(feat, subject_prob, subject_is_home=subject_is_home)
                        narrative = ""
                        if not is_completed:
                            narrative = (
                                presc["text"] if presc and presc["text"] else expl["narrative"]
                            )

                        item["home_win_probability"] = round(subject_prob, 4)
                        item["key_drivers"] = expl["top_drivers"][:3]
                        item["top_risks"] = expl["top_risks"][:2]
                        item["narrative"] = narrative
                        item["prescription"] = prescription
                    else:
                        # ── Non-subject fixture: neutral 3-way odds, no diagnostic ──
                        # Two independent BINARY calls (each team placed in the
                        # home slot) give P(home win) and P(away win) directly;
                        # the draw is the documented residual mass. This is NOT a
                        # 3-way classifier — it is two binary predictions plus a
                        # leftover. We do NOT apply the U-Cluj complement here.
                        home_win = feature_svc.win_prob(model_svc, home_lookup, away_lookup)
                        away_win = feature_svc.win_prob(model_svc, away_lookup, home_lookup)
                        draw = max(0.0, 1.0 - home_win - away_win)

                        item["home_team_win_prob"] = round(home_win, 4)
                        item["away_team_win_prob"] = round(away_win, 4)
                        item["draw_prob"] = round(draw, 4)
                        # No subject-centric headline / prescription / drivers for
                        # other matches; the client hides that section here.
                        item["home_win_probability"] = None
                        item["key_drivers"] = []
                        item["top_risks"] = []
                        item["narrative"] = ""
                        item["prescription"] = None
                else:
                    item["home_win_probability"] = None
                    item["key_drivers"] = []
                    item["top_risks"] = []
                    item["narrative"] = (
                        "The predictive model is temporarily unavailable."
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
    # NaN and +/-Inf are not valid JSON and would 500 the whole response;
    # sanitise so one edge-case fixture cannot break the page.
    result = _sanitize_floats(result)
    _PRED_CACHE[cache_key] = (time.monotonic(), result)
    return result


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
            "round": (ctx.get("round", {}) or {}).get("number"),
            "phase": (ctx.get("stage", {}) or {}).get("phase"),
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

    The baked 2025-26 dataset carries a final score for every fixture because the
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


def _csv_week_fixtures(
    fix_svc: FixtureService, monday: datetime, sunday: datetime,
    subject_name: str = TRACKED_TEAM_NAME,
) -> list[dict]:
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

    # Nothing in the requested window. Fall back to the nearest subject-club
    # fixture either side so the screen is not completely empty.
    all_subject = fix_svc.list_fixtures(team=subject_name, limit=500)
    past = [f for f in all_subject if _parse_dt(f.get("match_date", "")) < monday]
    future = [f for f in all_subject if _parse_dt(f.get("match_date", "")) >= sunday]
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
