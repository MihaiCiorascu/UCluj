"""Offline match-details builder backed by the committed Wyscout drive_cache.

The dashboard's concluded-match sheet originally pulled official lineups and
team statistics from Sportradar's ``sport_event_summary`` / ``lineups`` endpoints
keyed by a Sportradar ``sr:`` event id. The 2025-26 demo, however, drives the UI
from the *baked* fixtures (``services/baked_fixtures.py`` /
``ml/data/superliga_2025_26_fixtures.json``), whose ``match_id`` is the WYSCOUT
numeric match id, and the Sportradar trial quota is exhausted (every call returns
401). This module rebuilds the SAME ``/match-details`` response shape entirely
from local files, so a concluded match renders without any network call.

Data sources (all committed under ``backend/ml/data``):

* ``drive_cache/*_players_stats.json``, per-match Wyscout player stat blocks.
  Each file's ``players[0].matchId`` is the Wyscout match id; that builds the
  ``{matchId(str) -> filepath}`` index (:func:`build_drive_cache_index`).
* ``superliga_2025_26_fixtures.json`` (via :mod:`services.baked_fixtures`), the
  fixture's ``home_team`` / ``away_team`` registry shorts and date.
* ``matchid_to_date.json`` (via :mod:`ml.match_dates`), the match calendar date.
* ``drive_cache/players (1).json``, Wyscout player profiles (name, role).
* ``wyscout_to_sofascore.json``, photo URLs + the grade name index.

Home/away split. Each player in the match file is assigned to a club AS OF THE
MATCH DATE with the date-aware resolver
(:func:`ml.feature_engineering.primary_club_as_of`), so a mid-season transfer is
followed rather than averaged. The resolver omits a player with no in-window
dated appearance (e.g. round-1 fixtures have no prior matches); those fall back
to the legacy all-time squad membership
(:func:`ml.feature_engineering.get_team_squad_from_matches`). Only players whose
resolved club is the fixture's home or away short are kept.

Team statistics are AGGREGATED from the players' ``total`` blocks (an
approximation of Sportradar's official team totals, flagged inline at the
aggregation site). Per-player grade reuses the thesis composite via
``GradeService._grade_file`` (the same 0-10 mapping the Sportradar path uses),
and official slot/position labels reuse ``match_details._assign_official_positions``.
"""

from __future__ import annotations

import glob
import json
import logging
import os
import re
import unicodedata
from pathlib import Path
from typing import Optional

from ml.feature_engineering import (
    derive_primary_side,
    get_team_squad_from_matches,
    primary_club_as_of,
)
from ml.match_dates import date_for
from ml.pipeline import load_player_profiles
from sportradar.team_registry import TeamRef, team_by_alias

logger = logging.getLogger(__name__)

_DATA_DIR = Path(__file__).resolve().parents[3] / "ml" / "data"
_DRIVE_CACHE_DIR = _DATA_DIR / "drive_cache"
_PROFILES_PATH = _DRIVE_CACHE_DIR / "players (1).json"

# Real substitution clock minutes, baked once from the Sportradar timeline
# (scripts/bake_sub_minutes.py) and keyed by Wyscout match id. Absent when a match
# was not baked, in which case the lineup simply carries no minute and the client
# falls back to the duration / bare arrow.
_SUB_MIN_PATH = _DATA_DIR / "match_sub_minutes.json"
_SUB_MIN_CACHE: Optional[dict] = None


def _sub_minutes() -> dict:
    global _SUB_MIN_CACHE
    if _SUB_MIN_CACHE is None:
        try:
            _SUB_MIN_CACHE = json.loads(_SUB_MIN_PATH.read_text(encoding="utf-8"))
        except Exception:
            _SUB_MIN_CACHE = {}
    return _SUB_MIN_CACHE


def _name_tokens(name: str) -> set[str]:
    s = "".join(c for c in unicodedata.normalize("NFKD", name or "") if not unicodedata.combining(c))
    return {t for t in re.split(r"[^a-z]+", s.lower()) if len(t) >= 3}


def _sr_surname_tokens(sr_name: str) -> set[str]:
    """Tokens of the Sportradar surname (the part before the comma in 'Surname, First')."""
    return _name_tokens((sr_name or "").split(",")[0])


def _best_sub(pt: set[str], subs: list[dict], key: str, token_fn) -> Optional[dict]:
    best, best_score = None, 0
    for s in subs:
        score = len(pt & token_fn(s.get(key) or ""))
        if score > best_score:
            best, best_score = s, score
    return best if best_score >= 1 else None


def _name_initial(name: str) -> str:
    """First alphabetic character (accent-stripped, lower-cased) of a name; the
    given-name initial for both "M. Popescu" and "Mihai Popescu" forms."""
    s = "".join(c for c in unicodedata.normalize("NFKD", name or "") if not unicodedata.combining(c))
    for ch in s:
        if ch.isalpha():
            return ch.lower()
    return ""


def _sr_given_initial(sr_name: str) -> str:
    """Initial of the Sportradar given name (the part after the comma)."""
    parts = (sr_name or "").split(",", 1)
    return _name_initial(parts[1]) if len(parts) > 1 else ""


def _match_sub_minute(player_name: str, same_side: list[dict], all_subs: list[dict],
                      key: str) -> Optional[tuple[int, int]]:
    """(minute, stoppage) of the substitution for ``player_name``. Matches on the
    Sportradar SURNAME first (same side, then either side), which avoids given- and
    middle-name collisions (e.g. a player "Mihai" binding to another player's middle
    name "Mihai"). When two same-surname players collide (e.g. M. Popescu / O. Popescu),
    the given-name initial disambiguates. Falls back to the full name only when no
    surname candidate exists, for players listed by their given name (e.g. some
    Brazilians). Returns None when nothing matches."""
    pt = _name_tokens(player_name)
    if not pt:
        return None
    pinit = _name_initial(player_name)
    for pool in (same_side, all_subs):
        cands = [s for s in pool if pt & _sr_surname_tokens(s.get(key) or "")]
        if not cands:
            continue
        if len(cands) > 1 and pinit:
            by_init = [s for s in cands if _sr_given_initial(s.get(key) or "") == pinit]
            if by_init:
                cands = by_init
        s = cands[0]
        return int(s.get("minute") or 0), int(s.get("stoppage") or 0)
    # No surname candidate: full-name fallback (player listed by given name).
    hit = _best_sub(pt, same_side, key, _name_tokens) or _best_sub(pt, all_subs, key, _name_tokens)
    if hit is None:
        return None
    return int(hit.get("minute") or 0), int(hit.get("stoppage") or 0)


def _attach_sub_minutes(match_id, home_players: list[dict], away_players: list[dict]) -> None:
    """Attach real substitution clock minutes (``came_off_minute`` / ``came_on_minute``
    plus ``*_stoppage``) to lineup players, matched by side + surname against the baked
    Sportradar timeline. No-op when the match was not baked or a player has no match."""
    subs = _sub_minutes().get(str(match_id))
    if not subs:
        return
    for side, players in (("home", home_players), ("away", away_players)):
        same = [s for s in subs if s.get("side") == side]
        for p in players:
            key = "out" if p.get("came_off") else ("in" if p.get("came_on") else None)
            if key is None:
                continue
            hit = _match_sub_minute(p.get("name", ""), same, subs, key)
            if not hit:
                continue
            if key == "out":
                p["came_off_minute"], p["came_off_stoppage"] = hit
            else:
                p["came_on_minute"], p["came_on_stoppage"] = hit


# drive_cache match-id index
_INDEX_CACHE: Optional[dict[str, str]] = None
_PROFILES_CACHE: Optional[dict[int, dict]] = None
_SQUAD_CACHE: dict[str, set] = {}


def _drive_cache_files() -> list[str]:
    """All drive_cache per-match stat files, sorted (stable resolver input)."""
    return sorted(glob.glob(str(_DRIVE_CACHE_DIR / "*_players_stats.json")))


def build_drive_cache_index() -> dict[str, str]:
    """Return ``{wyscout_matchId(str) -> drive_cache filepath}`` (cached once).

    The key is ``players[0].matchId`` from each file. The 2025-26 corpus maps
    1:1 (one file per match id); if two files ever shared an id the first by
    sorted filename wins, which keeps the choice deterministic.
    """
    global _INDEX_CACHE
    if _INDEX_CACHE is not None:
        return _INDEX_CACHE
    index: dict[str, str] = {}
    for fp in _drive_cache_files():
        try:
            with open(fp, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        players = data.get("players") or []
        if not players:
            continue
        mid = players[0].get("matchId")
        if mid is None:
            continue
        index.setdefault(str(mid), fp)
    _INDEX_CACHE = index
    logger.info("Drive-cache match index built: %d matches", len(index))
    return _INDEX_CACHE


def has_drive_cache_match(match_id: str) -> bool:
    """True when ``match_id`` (a Wyscout numeric id) is in the drive_cache."""
    return str(match_id) in build_drive_cache_index()


def _load_profiles() -> dict[int, dict]:
    global _PROFILES_CACHE
    if _PROFILES_CACHE is None:
        try:
            _PROFILES_CACHE = load_player_profiles(str(_PROFILES_PATH))
        except Exception:
            logger.warning("Could not load player profiles from %s", _PROFILES_PATH, exc_info=True)
            _PROFILES_CACHE = {}
    return _PROFILES_CACHE


def _all_time_squad(team: TeamRef) -> set:
    """All-time (date-unaware) squad id set for a team, cached by short."""
    if team.short not in _SQUAD_CACHE:
        try:
            _SQUAD_CACHE[team.short] = get_team_squad_from_matches(
                _drive_cache_files(), team.wy_substr
            )
        except Exception:
            logger.warning("All-time squad resolution failed for %s", team.short, exc_info=True)
            _SQUAD_CACHE[team.short] = set()
    return _SQUAD_CACHE[team.short]


# Wyscout fine-position name (for official-slot assignment)
# Most-played Wyscout position NAME per player, so ``match_details``'s
# ``_assign_official_positions`` -> ``_fine_from_sr_position`` keyword mapping
# resolves the fine slot (it already understands "Centre Back", "Defensive
# Midfielder", "Left Wingback", etc., which are exactly Wyscout's names).
def _primary_position_name(entry: dict) -> tuple[str, str]:
    """Return ``(coarse, name)`` for a player's most-played position in a match.

    ``coarse`` is one of ``G/D/M/F`` (the short codes the existing pitch logic
    expects); ``name`` is the Wyscout position display name (e.g. "Centre Back")
    used as ``_pos_raw`` for fine-slot assignment. Falls back to ``("M", "")``
    when the match block carries no position codes.
    """
    positions = entry.get("positions") or []
    best_name = ""
    best_pct = -1.0
    for e in positions:
        pos = e.get("position", {}) or {}
        pct = float(e.get("percent", 0) or 0)
        if pct >= best_pct and pos.get("name"):
            best_pct = pct
            best_name = pos.get("name", "")
    coarse = _coarse_from_name(best_name)
    return coarse, best_name


def _coarse_from_name(name: str) -> str:
    """Map a Wyscout position name to the G/D/M/F short code."""
    p = (name or "").lower()
    if "goalkeeper" in p:
        return "G"
    if "back" in p or "defender" in p or "wingback" in p:
        return "D"
    if "midfield" in p:
        return "M"
    if "winger" in p or "wing forward" in p or "striker" in p or "forward" in p or "attack" in p:
        return "F"
    return "M"


# Team-stat aggregation
def _aggregate_team_stats(player_totals: list[dict]) -> dict:
    """Aggregate one side's per-player ``total`` blocks into team statistics.

    APPROXIMATION: Wyscout ships per-player counters, not the official
    Sportradar team totals, so these sums stand in for them. Shots / shots on
    target / fouls / cards / corners / offsides / goalkeeper saves sum directly;
    ball possession is approximated by this side's PASS SHARE (filled in by the
    caller, which knows both sides' pass volume); pass accuracy and duel win
    rate are aggregate ratios. Fields Sportradar would carry but that do not
    aggregate meaningfully from per-player data are emitted as ``None``.
    """
    agg: dict[str, float] = {}
    keys = (
        "shots", "shotsOnTarget", "fouls", "yellowCards", "redCards",
        "directRedCards", "passes", "successfulPasses", "duels", "duelsWon",
        "corners", "offsides", "gkSaves",
    )
    for k in keys:
        agg[k] = 0
    for t in player_totals:
        for k in keys:
            agg[k] += t.get(k, 0) or 0

    shots = int(agg["shots"])
    shots_on = int(agg["shotsOnTarget"])
    shots_off = max(shots - shots_on, 0)
    red = int(agg["redCards"]) + int(agg["directRedCards"])

    passes = agg["passes"]
    succ_passes = agg["successfulPasses"]
    pass_accuracy = round(succ_passes / passes * 100, 1) if passes else None
    duels = agg["duels"]
    duels_won = agg["duelsWon"]
    duel_win_rate = round(duels_won / duels * 100, 1) if duels else None

    return {
        # Sportradar-shaped MatchTeamStats fields the Flutter model parses.
        "ball_possession": None,  # filled by caller from both sides' pass share
        "shots_on_target": shots_on,
        "shots_off_target": shots_off,
        "shots_total": shots,
        "corner_kicks": int(agg["corners"]),
        "yellow_cards": int(agg["yellowCards"]),
        "red_cards": red,
        "offsides": int(agg["offsides"]),
        "fouls": int(agg["fouls"]),
        "goalkeeper_saves": int(agg["gkSaves"]),
        # Extra approximate aggregates (harmless to the parser, useful context).
        "pass_accuracy": pass_accuracy,
        "duel_win_rate": duel_win_rate,
        # Internal: pass volume, used by the caller to split possession.
        "_passes": passes,
    }


# Official team stats (baked from Sportradar summaries)
_BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_TEAM_STATS_PATH = os.path.join(_BACKEND_ROOT, "ml", "data", "matchid_to_team_stats.json")
_TEAM_STATS_CACHE: Optional[dict] = None


def _official_team_stats(match_id: str) -> Optional[dict]:
    """Return the baked official Sportradar team stats for a match, or ``None``.

    Built once by ``scripts/build_team_stats_from_sportradar.py`` and committed as
    ``ml/data/matchid_to_team_stats.json``; loaded lazily and cached. Each value
    is ``{"home_stats": {...}, "away_stats": {...}}`` in the same field shape as
    ``_aggregate_team_stats``. Matches we have no official stats for fall back to
    the per-player aggregation.
    """
    global _TEAM_STATS_CACHE
    if _TEAM_STATS_CACHE is None:
        try:
            with open(_TEAM_STATS_PATH, encoding="utf-8") as fh:
                _TEAM_STATS_CACHE = json.load(fh)
        except Exception:
            logger.warning("Could not load %s; using Wyscout-aggregated team stats",
                           _TEAM_STATS_PATH, exc_info=True)
            _TEAM_STATS_CACHE = {}
    return _TEAM_STATS_CACHE.get(str(match_id))


# Public entry point
def build_offline_match_details(match_id: str, grade_service, photo_service) -> Optional[dict]:
    """Build the ``/match-details`` payload for a Wyscout match id, or ``None``.

    Returns ``None`` when ``match_id`` is not in the drive_cache (the caller then
    keeps the Sportradar path). ``grade_service`` and ``photo_service`` are the
    already-instantiated ``GradeService`` / ``PlayerPhotoService`` singletons
    from ``match_details`` (the grade file is loaded directly by path, and photos
    are resolved by the players' Wyscout ids).
    """
    index = build_drive_cache_index()
    filepath = index.get(str(match_id))
    if filepath is None:
        return None

    # Fixture metadata (home/away registry shorts) from the baked dataset.
    from services.baked_fixtures import load_baked_fixtures

    fixture = None
    for f in load_baked_fixtures():
        if str(f.get("match_id", "")) == str(match_id):
            fixture = f
            break
    home_ref = team_by_alias(fixture.get("home_team", "")) if fixture else None
    away_ref = team_by_alias(fixture.get("away_team", "")) if fixture else None

    try:
        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        logger.warning("Could not read drive-cache file %s", filepath, exc_info=True)
        return None
    match_players = [p for p in (data.get("players") or [])
                     if (p.get("total", {}) or {}).get("minutesOnField", 0)]

    if home_ref is None or away_ref is None:
        # Without the two clubs we cannot split the players; return an empty
        # but well-shaped payload so the sheet renders "no data" rather than 500.
        logger.warning("Offline match-details: fixture/teams missing for match %s", match_id)
        return _empty_payload(match_id)

    match_date = date_for(match_id)  # ISO 'YYYY-MM-DD' or None

    # Date-aware primary club per player, with an all-time-squad fallback for
    # players the resolver omits (e.g. round-1 fixtures have no prior matches).
    resolver = {}
    try:
        if match_date:
            resolver = primary_club_as_of(_drive_cache_files(), match_date)
    except Exception:
        logger.warning("primary_club_as_of failed for match %s", match_id, exc_info=True)
        resolver = {}
    home_squad = _all_time_squad(home_ref)
    away_squad = _all_time_squad(away_ref)

    profiles = _load_profiles()

    # Per-player grades for this exact file (reuses the thesis composite).
    try:
        grades_by_wy = grade_service._grade_file(Path(filepath))
    except Exception:
        logger.warning("Grade computation failed for match %s", match_id, exc_info=True)
        grades_by_wy = {}

    home_players: list[dict] = []
    away_players: list[dict] = []
    home_totals: list[dict] = []
    away_totals: list[dict] = []

    for entry in match_players:
        pid = entry.get("playerId")
        if pid is None:
            continue
        side = _resolve_side(int(pid), resolver, home_ref, away_ref, home_squad, away_squad)
        if side is None:
            continue  # unknown club -> omit (cannot place on either pitch)
        total = entry.get("total", {}) or {}
        player_dict = _build_player(entry, total, profiles, grades_by_wy, photo_service)
        if side == "home":
            home_players.append(player_dict)
            home_totals.append(total)
        else:
            away_players.append(player_dict)
            away_totals.append(total)

    _attach_sub_minutes(match_id, home_players, away_players)

    home_lineup, home_formation = _finalise_side(home_players)
    away_lineup, away_formation = _finalise_side(away_players)

    home_stats = _aggregate_team_stats(home_totals)
    away_stats = _aggregate_team_stats(away_totals)

    # Ball possession ~= each side's pass share of both sides' passes.
    hp = home_stats.pop("_passes", 0)
    ap = away_stats.pop("_passes", 0)
    total_passes = hp + ap
    if total_passes:
        home_stats["ball_possession"] = round(hp / total_passes * 100, 1)
        away_stats["ball_possession"] = round(ap / total_passes * 100, 1)

    # Prefer the official Sportradar team totals when we have baked them for this
    # match; otherwise keep the per-player Wyscout aggregation above and flag the
    # stats as estimated so the sheet can caption them honestly.
    stats_estimated = True
    official = _official_team_stats(match_id)
    if official:
        oh, oa = official.get("home_stats"), official.get("away_stats")
        if oh or oa:
            home_stats = oh or home_stats
            away_stats = oa or away_stats
            stats_estimated = False

    return {
        "match_id": str(match_id),
        "home_stats": home_stats,
        "away_stats": away_stats,
        "home_lineup": home_lineup,
        "away_lineup": away_lineup,
        "home_formation": home_formation,
        "away_formation": away_formation,
        "stats_estimated": stats_estimated,
    }


def _resolve_side(
    pid: int,
    resolver: dict[int, str],
    home_ref: TeamRef,
    away_ref: TeamRef,
    home_squad: set,
    away_squad: set,
) -> Optional[str]:
    """Return ``"home"`` / ``"away"`` / ``None`` for a player in this fixture.

    Primary signal: the date-aware resolver's short label. When the resolver
    omits the player (no in-window dated appearance), fall back to all-time
    squad membership, which is unambiguous for a single fixture because a
    player belongs to at most one of the two clubs' all-time squads.
    """
    club = resolver.get(pid)
    if club == home_ref.short:
        return "home"
    if club == away_ref.short:
        return "away"
    if club is None:
        in_home = pid in home_squad
        in_away = pid in away_squad
        if in_home and not in_away:
            return "home"
        if in_away and not in_home:
            return "away"
    return None


def _player_stats(total: dict) -> dict:
    """Curated per-player match stats from the Wyscout ``total`` block: raw counts
    plus pass-accuracy, duel-win-rate percentages, and goalkeeper figures. The
    client renders a position-aware subset of these on the player-detail sheet."""
    def g(k: str) -> float:
        return total.get(k, 0) or 0

    passes = g("passes")
    duels = g("duels")
    return {
        "minutes": int(g("minutesOnField")),
        "goals": int(g("goals")),
        "assists": int(g("assists")),
        "shots": int(g("shots")),
        "shotsOnTarget": int(g("shotsOnTarget")),
        "keyPasses": int(g("keyPasses")),
        "passes": int(passes),
        "passAccuracy": round(g("successfulPasses") / passes * 100) if passes else 0,
        "duels": int(duels),
        "duelsWon": int(g("duelsWon")),
        "duelWinRate": round(g("duelsWon") / duels * 100) if duels else 0,
        "dribbles": int(g("dribbles")),
        "dribblesWon": int(g("successfulDribbles")),
        "interceptions": int(g("interceptions")),
        "recoveries": int(g("recoveries")),
        "clearances": int(g("clearances")),
        "crosses": int(g("crosses")),
        "successfulCrosses": int(g("successfulCrosses")),
        "fouls": int(g("fouls")),
        "gkSaves": int(g("gkSaves")),
        "gkConceded": int(g("gkConcededGoals")),
        "gkCleanSheet": 1 if g("gkCleanSheets") else 0,
    }


def _build_player(
    entry: dict,
    total: dict,
    profiles: dict[int, dict],
    grades_by_wy: dict[int, float],
    photo_service,
) -> dict:
    """Build one MatchPlayer-shaped dict from a Wyscout per-match block."""
    pid = int(entry.get("playerId"))
    profile = profiles.get(pid, {})
    name = profile.get("shortName") or _name_from_profile(profile) or str(pid)
    coarse, pos_name = _primary_position_name(entry)
    pos_side = derive_primary_side([entry])
    minutes = int(total.get("minutesOnField", 0) or 0)
    started = (total.get("matchesInStart", 0) or 0) > 0
    grade = grades_by_wy.get(pid)
    photo_url = photo_service.url_for(pid) or ""

    return {
        "name": name,
        "jersey_number": None,  # Wyscout profiles/match blocks carry no shirt number
        "type": "starter" if started else "substitute",
        "position": coarse,
        "official_position": "",
        "slot_index": -1,
        "goals_scored": int(total.get("goals", 0) or 0),
        "assists": int(total.get("assists", 0) or 0),
        "yellow_cards": int(total.get("yellowCards", 0) or 0),
        "red_cards": int(total.get("redCards", 0) or 0) + int(total.get("directRedCards", 0) or 0),
        "shots_on_target": int(total.get("shotsOnTarget", 0) or 0),
        "minutes_played": minutes,
        # Ground-truth substitution flags from the Wyscout total block: a
        # matchesSubstituted starter was subbed OFF, a matchesComingOff player
        # came ON as a sub. Verified corpus-wide with zero anomalies (2,511 off /
        # 2,521 on / 3,605 full across the 278 files; full-match starters carry
        # neither flag), which is why the earlier minutes heuristic was removed.
        "came_off": (total.get("matchesSubstituted", 0) or 0) > 0,
        "came_on": (total.get("matchesComingOff", 0) or 0) > 0,
        "grade": grade,
        "stats": _player_stats(total),
        "photo_url": photo_url,
        "_pos_raw": pos_name,
        "_pos_side": pos_side,  # L/R/C, consumed by _assign_official_positions
        "_minutes": minutes,  # internal sort/fallback key, removed in _finalise_side
    }


def _name_from_profile(profile: dict) -> str:
    first = (profile.get("firstName") or "").strip()
    last = (profile.get("lastName") or "").strip()
    if last and first:
        return f"{last}, {first}"
    return last or first or ""


def _finalise_side(players: list[dict]) -> tuple[list[dict], str]:
    """Order, fix the starter count to eleven, assign official slots.

    Starters are flagged by the Wyscout ``matchesInStart`` flag; when that does
    not yield exactly eleven (rotation flags, resolver dropping a starter to the
    other club, etc.) and there are at least eleven players, the top eleven by
    minutes are taken as starters so the official-slot assignment (which needs a
    full eleven) still fires. Returns ``(ordered_players, formation_key)``.
    """
    from api.v1.endpoints.match_details import _assign_official_positions

    starters = [p for p in players if p["type"] == "starter"]
    if len(starters) != 11 and len(players) >= 11:
        ordered_by_min = sorted(players, key=lambda p: p["_minutes"], reverse=True)
        top11 = set(id(p) for p in ordered_by_min[:11])
        for p in players:
            p["type"] = "starter" if id(p) in top11 else "substitute"

    players.sort(key=lambda x: (0 if x["type"] == "starter" else 1, -x["_minutes"]))

    formation_key = _assign_official_positions(players, None)

    for p in players:
        p.pop("_pos_raw", None)
        p.pop("_pos_side", None)
        p.pop("_minutes", None)
    return players, formation_key or ""


def _empty_payload(match_id: str) -> dict:
    return {
        "match_id": str(match_id),
        "home_stats": {},
        "away_stats": {},
        "home_lineup": [],
        "away_lineup": [],
        "home_formation": "",
        "away_formation": "",
        "stats_estimated": False,
    }
