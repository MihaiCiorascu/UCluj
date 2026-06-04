from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from fastapi import APIRouter, Depends, Query

from clients.sportradar_client import SportradarClient
from core.security import get_current_user
from ml.xi_predictor import FORMATIONS, StartingXIPredictor
from services.player_photo_service import PlayerPhotoService

logger = logging.getLogger(__name__)

router = APIRouter()

_CACHE_DIR = Path(__file__).parent / "_sr_match_cache"
_CACHE_TTL = 24 * 3600  # completed matches don't change

# ── Official-position assignment for the actual (Sportradar) lineup ──────────
# The recommended-XI pitch shows official positions; the post-match pitch should
# read the same way. Sportradar gives a position string per player (sometimes
# granular like "left back", sometimes only "defender") plus the team shape, so
# we map the string to the thesis fine taxonomy and reuse the same Hungarian
# slot assignment as the predictor (FORMATION_SLOTS) to place the eleven
# starters into official slots.

# Keyword -> fine group. Order matters: the more specific phrases are tested
# first (for example "wing back" before "back", "wing forward" before "winger").
_SR_POSITION_FINE_KEYWORDS: list[tuple[str, str]] = [
    ("goalkeeper", "GK"),
    ("wing back", "WB"), ("wingback", "WB"), ("wing-back", "WB"),
    ("centre back", "CB"), ("center back", "CB"), ("central defender", "CB"),
    ("left back", "FB"), ("right back", "FB"), ("full back", "FB"), ("fullback", "FB"),
    ("defensive midfield", "DM"), ("holding", "DM"),
    ("attacking midfield", "AM"),
    ("central midfield", "CM"), ("centre midfield", "CM"), ("center midfield", "CM"),
    ("wing forward", "WF"),
    ("second striker", "ST"), ("centre forward", "ST"), ("center forward", "ST"),
    ("striker", "ST"),
    ("winger", "W"), ("wide midfield", "W"),
    ("midfield", "CM"),
    ("back", "FB"), ("defender", "CB"),
    ("forward", "ST"), ("attacker", "ST"),
]

# Coarse (D/M/F) outfield count tuple -> a canonical formation key with the same
# coarse breakdown, used when Sportradar does not give an explicit formation.
_COUNTS_TO_FORMATION: dict[tuple[int, int, int], str] = {
    (4, 4, 2): "4-4-2",
    (4, 3, 3): "4-3-3",
    (4, 5, 1): "4-2-3-1",
    (3, 5, 2): "3-5-2",
    (3, 4, 3): "3-4-3",
    (5, 3, 2): "5-3-2",
    (5, 4, 1): "5-4-1",
    (3, 6, 1): "3-6-1",
}

_COARSE_FROM_SHORT = {"G": "GK", "D": "DEF", "M": "MID", "F": "FWD"}

# A single unfitted assigner instance; _assign_xi needs no fitted state.
_XI_ASSIGNER = StartingXIPredictor()

# Player headshots, resolved by display name (Sportradar gives no Wyscout id).
# Reads the same committed mapping the recommended-XI flow uses; missing/empty
# means every lookup returns None and the client renders initials.
_PHOTOS = PlayerPhotoService(
    str(Path(__file__).resolve().parents[3] / "ml" / "data" / "wyscout_to_sofascore.json")
)


def _attach_photos(details: dict) -> None:
    """Fill ``photo_url`` for every lineup player (idempotent).

    Runs on freshly built details and on cache hits, so a pre-photo cache
    backfills photos without a refetch. Name-based lookup; misses stay empty
    and the client renders initials.
    """
    for side in ("home_lineup", "away_lineup"):
        for p in details.get(side) or []:
            if not p.get("photo_url"):
                p["photo_url"] = _PHOTOS.url_for_name(p.get("name", "")) or ""


def _fine_from_sr_position(pos_raw: str) -> str:
    """Map a Sportradar position string to a fine group, or '' when unknown."""
    p = (pos_raw or "").lower()
    for keyword, fine in _SR_POSITION_FINE_KEYWORDS:
        if keyword in p:
            return fine
    return ""


def _assign_official_positions(players: list[dict], sr_formation: str | None) -> str | None:
    """Attach ``official_position`` and ``slot_index`` to the eleven starters.

    Reuses the predictor's Hungarian slot assignment so the post-match pitch
    lays out the same way as the recommended XI. Players keep a temporary
    ``_pos_raw`` field that the caller removes afterwards. Mutates ``players``
    in place and returns the formation key used (so the client can mirror the
    slot order), or ``None`` when there is no full eleven to assign.
    """
    starters = [p for p in players if p.get("type") == "starter"]
    if len(starters) != 11:
        return None

    n_def = sum(1 for p in starters if p.get("position") == "D")
    n_mid = sum(1 for p in starters if p.get("position") == "M")
    n_fwd = sum(1 for p in starters if p.get("position") == "F")

    formation_key: str | None = None
    if sr_formation and str(sr_formation).strip() in FORMATIONS:
        formation_key = str(sr_formation).strip()
    if formation_key is None:
        formation_key = _COUNTS_TO_FORMATION.get((n_def, n_mid, n_fwd))
    if formation_key is None:
        # Generic dash string so the predictor can still build coarse slots.
        formation_key = f"{n_def}-{n_mid}-{n_fwd}"

    rows = []
    for idx, p in enumerate(starters):
        coarse = _COARSE_FROM_SHORT.get(p.get("position", ""), "MID")
        rows.append({
            "_i": idx,
            "role_group": coarse,
            "position_group_fine": _fine_from_sr_position(p.get("_pos_raw", "")),
            # No real scores for an actual lineup; a stable descending value
            # keeps the assignment deterministic.
            "predicted_score": 1.0 - idx * 0.001,
        })

    try:
        assigned = _XI_ASSIGNER._assign_xi(pd.DataFrame(rows), formation_key)
    except Exception:
        logger.warning("Official-position assignment failed for the actual lineup", exc_info=True)
        return None

    if assigned is None or assigned.empty:
        return None
    for _, r in assigned.iterrows():
        i = int(r["_i"])
        starters[i]["official_position"] = str(r.get("official_position", "") or "")
        starters[i]["slot_index"] = int(r.get("slot_index", -1))
    return formation_key


def _cache_path(match_id: str) -> Path:
    safe = match_id.replace(":", "_").replace("/", "_")
    return _CACHE_DIR / f"{safe}.json"


def _load_cache(match_id: str) -> dict | None:
    try:
        p = _cache_path(match_id)
        if not p.exists():
            return None
        data = json.loads(p.read_text(encoding="utf-8"))
        cached_at = datetime.fromisoformat(data["cached_at"])
        age = (datetime.now(timezone.utc) - cached_at).total_seconds()
        if age > _CACHE_TTL:
            return None
        return data["details"]
    except Exception:
        return None


def _save_cache(match_id: str, details: dict) -> None:
    try:
        _CACHE_DIR.mkdir(parents=True, exist_ok=True)
        payload = {
            "cached_at": datetime.now(timezone.utc).isoformat(),
            "details": details,
        }
        _cache_path(match_id).write_text(
            json.dumps(payload, default=str), encoding="utf-8"
        )
    except Exception as exc:
        logger.warning("Could not write match details cache: %s", exc)


@router.get("/match-details")
async def match_details(
    match_id: str = Query(..., description="Sportradar sport_event ID"),
    _user=Depends(get_current_user),
):
    """Return official lineups + team statistics for a completed match."""
    cached = _load_cache(match_id)
    if cached:
        _attach_photos(cached)
        return cached

    client = SportradarClient()
    try:
        summary, lineups = await asyncio.gather(
            client.sport_event_summary(match_id),
            client.sport_event_lineups(match_id),
            return_exceptions=True,
        )
    except Exception as exc:
        logger.warning("match-details fetch failed for %s: %s", match_id, exc)
        summary, lineups = None, None

    if isinstance(summary, Exception):
        summary = None
    if isinstance(lineups, Exception):
        lineups = None

    result = _build_details(match_id, summary, lineups)
    _attach_photos(result)

    if result.get("home_stats") or result.get("home_lineup"):
        _save_cache(match_id, result)

    return result


# ---------------------------------------------------------------------------

def _build_details(match_id: str, summary: dict | None, lineups: dict | None) -> dict:
    home_stats: dict = {}
    away_stats: dict = {}
    home_lineup: list[dict] = []
    away_lineup: list[dict] = []
    home_formation: str = ""
    away_formation: str = ""

    # Player stats by id from summary, keyed by side
    home_player_stats: dict[str, dict] = {}
    away_player_stats: dict[str, dict] = {}

    if summary:
        totals = (summary.get("statistics") or {}).get("totals", {})
        for comp in totals.get("competitors") or []:
            s = comp.get("statistics", {})
            qual = comp.get("qualifier", "")
            parsed = {
                "ball_possession": s.get("ball_possession"),
                "shots_on_target": s.get("shots_on_target"),
                "shots_off_target": s.get("shots_off_target"),
                "shots_total": s.get("shots_total"),
                "corner_kicks": s.get("corner_kicks"),
                "yellow_cards": s.get("yellow_cards"),
                "red_cards": s.get("red_cards"),
                "offsides": s.get("offsides"),
                "fouls": s.get("fouls"),
                "goalkeeper_saves": s.get("shots_saved"),  # Sportradar uses shots_saved
            }
            # Build per-player stats lookup
            player_stats_map: dict[str, dict] = {}
            for p in comp.get("players") or []:
                pid = p.get("id", "")
                stat = p.get("statistics") or {}
                player_stats_map[pid] = {
                    "starter": p.get("starter", False),
                    "goals_scored": stat.get("goals_scored", 0),
                    "assists": stat.get("assists", 0),
                    "yellow_cards": stat.get("yellow_cards", 0),
                    "red_cards": stat.get("red_cards", 0),
                    "shots_on_target": stat.get("shots_on_target", 0),
                }
            if qual == "home":
                home_stats = parsed
                home_player_stats = player_stats_map
            elif qual == "away":
                away_stats = parsed
                away_player_stats = player_stats_map

    if lineups:
        lineup_block = lineups.get("lineups", {})
        for comp in lineup_block.get("competitors") or []:
            qual = comp.get("qualifier", "")
            player_stats_map = home_player_stats if qual == "home" else away_player_stats
            players = []
            for p in comp.get("players") or []:
                pid = p.get("id", "")
                pstat = player_stats_map.get(pid, {})
                # Position: map verbose names to short codes
                pos_raw = p.get("position", p.get("type", ""))
                pos = _short_position(pos_raw)
                is_starter = p.get("starter", False) or pstat.get("starter", False)
                players.append({
                    "name": p.get("name", ""),
                    "jersey_number": p.get("jersey_number"),
                    "type": "starter" if is_starter else "substitute",
                    "position": pos,
                    "official_position": "",
                    "slot_index": -1,
                    "goals_scored": pstat.get("goals_scored", 0),
                    "assists": pstat.get("assists", 0),
                    "yellow_cards": pstat.get("yellow_cards", 0),
                    "red_cards": pstat.get("red_cards", 0),
                    "shots_on_target": pstat.get("shots_on_target", 0),
                    "minutes_played": None,
                    "_pos_raw": pos_raw,
                })
            # Sort: starters first
            players.sort(key=lambda x: (0 if x["type"] == "starter" else 1))
            # Assign official positions to the starters using the team shape
            # (Sportradar formation when present, else inferred from the D/M/F
            # counts), then drop the temporary raw-position field. The chosen
            # formation key is returned so the client lays the pitch out with
            # the same slot ordering the assignment used.
            formation_key = _assign_official_positions(players, comp.get("formation"))
            for p in players:
                p.pop("_pos_raw", None)
            if qual == "home":
                home_lineup = players
                home_formation = formation_key or ""
            elif qual == "away":
                away_lineup = players
                away_formation = formation_key or ""

    return {
        "match_id": match_id,
        "home_stats": home_stats,
        "away_stats": away_stats,
        "home_lineup": home_lineup,
        "away_lineup": away_lineup,
        "home_formation": home_formation,
        "away_formation": away_formation,
    }


def _short_position(pos: str) -> str:
    p = pos.lower()
    if "goalkeeper" in p or p == "g":
        return "G"
    if "back" in p or "defender" in p or p == "d":
        return "D"
    if "midfield" in p or "midfielder" in p or p == "m":
        return "M"
    if "forward" in p or "winger" in p or "striker" in p or "attack" in p or p == "f":
        return "F"
    return pos[:1].upper() if pos else "?"
