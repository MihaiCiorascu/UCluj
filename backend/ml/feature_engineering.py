"""
Feature Engineering for Football Starting XI Predictor
Transforms raw player stats + player profile data into ML-ready features.
"""

import json
import numpy as np
import pandas as pd
from pathlib import Path
from typing import List, Dict, Optional


# ─── Stat weights by position group ───────────────────────────────────────────
POSITION_STAT_WEIGHTS = {
    "GK": {
        "gkSaves": 3.0, "gkCleanSheets": 3.0, "gkShotsAgainst": -1.0,
        "gkSuccessfulExits": 2.0, "gkAerialDuelsWon": 2.0,
        "successfulPasses": 1.0, "losses": -1.0,
    },
    "DEF": {
        "interceptions": 2.5, "defensiveDuelsWon": 2.5, "aerialDuelsWon": 2.0,
        "clearances": 2.0, "successfulDefensiveAction": 2.0,
        "successfulPasses": 1.5, "losses": -1.5, "fouls": -1.0,
        "yellowCards": -2.0, "redCards": -5.0,
        "recoveries": 1.5, "shotsBlocked": 1.5,
    },
    "MID": {
        "successfulPasses": 2.0, "keyPasses": 3.0, "assists": 3.0,
        "goals": 3.0, "successfulDribbles": 2.0, "interceptions": 1.5,
        "progressivePasses": 2.0, "recoveries": 1.5,
        "losses": -1.5, "fouls": -0.5, "yellowCards": -2.0,
        "passesToFinalThird": 2.0, "xgAssist": 2.5,
    },
    "FWD": {
        "goals": 4.0, "shots": 1.5, "shotsOnTarget": 2.5, "xgShot": 3.0,
        "assists": 2.5, "successfulDribbles": 2.0, "keyPasses": 2.0,
        "touchInBox": 2.0, "offsides": -0.5, "losses": -1.0,
    },
}

ROLE_TO_GROUP = {
    "Goalkeeper": "GK", "GK": "GK",
    "Defender": "DEF", "Centre Back": "DEF", "Left Back": "DEF",
    "Right Back": "DEF", "Wing Back": "DEF",
    "Midfielder": "MID", "Central Midfielder": "MID", "Defensive Midfielder": "MID",
    "Attacking Midfielder": "MID", "Wide Midfielder": "MID",
    "Forward": "FWD", "Striker": "FWD", "Left Winger": "FWD", "Right Winger": "FWD",
}


# ─── Fine-grained position taxonomy (Wyscout sub-positions) ──────────────────
# The Wyscout JSON `positions[*].position.code` field carries one of 28
# distinct codes; this map projects them into ten football-conventional fine
# groups. The coarse map then projects the fine groups back to the four
# formation-relevant groups so the existing slot-filling logic continues to
# work for 4-3-3 / 4-4-2 / 3-5-2 etc.
POSITION_CODE_TO_FINE_GROUP: Dict[str, str] = {
    # Goalkeeper
    "gk": "GK",
    # Centre-Backs (incl. 3-back variants)
    "cb": "CB", "lcb": "CB", "rcb": "CB",
    "cb3": "CB", "lcb3": "CB", "rcb3": "CB",
    # Full-Backs (incl. 5-back variants)
    "lb": "FB", "rb": "FB", "lb5": "FB", "rb5": "FB",
    # Wing-Backs
    "lwb": "WB", "rwb": "WB",
    # Defensive Midfielders
    "dmf": "DM", "ldmf": "DM", "rdmf": "DM",
    # Centre Midfielders (left / right / central, incl. 3-mid variants)
    "lcmf": "CM", "rcmf": "CM", "cmf": "CM",
    "lcmf3": "CM", "rcmf3": "CM",
    # Attacking Midfielders
    "amf": "AM", "lamf": "AM", "ramf": "AM",
    # Wingers
    "lw": "W", "rw": "W",
    # Wing Forwards
    "lwf": "WF", "rwf": "WF",
    # Centre Forward / Striker / Second Striker
    "cf": "ST", "ss": "ST",
}

FINE_GROUP_TO_COARSE: Dict[str, str] = {
    "GK": "GK",
    "CB": "DEF", "FB": "DEF", "WB": "DEF",
    "DM": "MID", "CM": "MID", "AM": "MID",
    "W":  "FWD", "WF": "FWD", "ST": "FWD",
}

# Fine-group KPI weight tables. Each weight applies to the per-90, raw KPI
# from the Wyscout `total` block; weights are calibrated against football
# convention (e.g. a wing-back is rewarded for crosses and forward runs, a
# defensive midfielder for interceptions and recoveries). Weight magnitudes
# remain in the [-5, +5] range used by the original four-group `POSITION_STAT_WEIGHTS`
# to keep performance-score values comparable.
FINE_POSITION_STAT_WEIGHTS: Dict[str, Dict[str, float]] = {
    "GK": {
        "gkSaves": 3.0, "gkCleanSheets": 3.0, "gkSuccessfulExits": 2.0,
        "gkAerialDuelsWon": 2.0, "gkShotsAgainst": -1.0,
        "successfulPasses": 1.0, "losses": -1.0,
    },
    "CB": {
        "defensiveDuelsWon": 3.0, "aerialDuelsWon": 3.0, "clearances": 2.0,
        "interceptions": 2.0, "successfulPasses": 1.5, "shotsBlocked": 1.5,
        "recoveries": 1.0, "losses": -1.5, "fouls": -1.0,
        "yellowCards": -2.0, "redCards": -5.0,
    },
    "FB": {
        "defensiveDuelsWon": 2.0, "successfulCrosses": 2.0,
        "successfulPasses": 1.5, "aerialDuelsWon": 1.5, "recoveries": 1.5,
        "progressivePasses": 1.0, "interceptions": 1.5, "keyPasses": 1.0,
        "losses": -1.5, "yellowCards": -2.0,
    },
    "WB": {
        "successfulCrosses": 2.5, "keyPasses": 2.0, "defensiveDuelsWon": 2.0,
        "progressivePasses": 1.5, "assists": 1.5, "successfulPasses": 1.0,
        "passesToFinalThird": 1.0, "losses": -1.5,
    },
    "DM": {
        "interceptions": 2.5, "recoveries": 2.0, "defensiveDuelsWon": 2.0,
        "successfulPasses": 2.0, "aerialDuelsWon": 1.0, "progressivePasses": 1.5,
        "losses": -1.5, "fouls": -1.0, "yellowCards": -2.0,
    },
    "CM": {
        "successfulPasses": 2.5, "keyPasses": 2.0, "progressivePasses": 2.0,
        "recoveries": 1.5, "passesToFinalThird": 1.5, "assists": 1.5,
        "interceptions": 1.0, "losses": -1.5,
    },
    "AM": {
        "keyPasses": 3.0, "assists": 2.5, "goals": 2.0, "xgAssist": 2.0,
        "progressivePasses": 1.5, "successfulDribbles": 1.5,
        "successfulPasses": 1.0, "losses": -1.0,
    },
    "W": {
        "successfulDribbles": 2.5, "successfulCrosses": 2.0, "keyPasses": 2.0,
        "goals": 1.5, "assists": 1.5, "shots": 1.0, "xgAssist": 1.5,
        "losses": -1.0, "offsides": -0.5,
    },
    "WF": {
        "goals": 3.0, "successfulDribbles": 2.5, "shots": 2.0,
        "assists": 2.0, "touchInBox": 1.5, "xgShot": 2.0,
        "shotsOnTarget": 1.5, "offsides": -0.5,
    },
    "ST": {
        "goals": 4.0, "shotsOnTarget": 2.5, "xgShot": 3.0,
        "touchInBox": 2.0, "headShots": 1.0, "shots": 1.5,
        "assists": 1.5, "offsides": -0.5,
    },
}


def derive_primary_fine_position(match_stats_list: List[Dict]) -> str:
    """Return the player's primary fine-position label.

    The label is the fine group whose accumulated weight is largest across
    all matches, where the weight contributed by each match is
    ``minutes_in_match * percent_share`` (the `percent` field on the
    Wyscout `positions[i]` entry). Falls back to ``MID`` when no parseable
    position codes are present.
    """
    from collections import Counter
    weights: Counter = Counter()
    for match in match_stats_list:
        minutes = (match.get("total", match) or {}).get("minutesOnField", 0) or 0
        if minutes <= 0:
            continue
        for entry in match.get("positions", []) or []:
            pos = (entry.get("position", {}) or {})
            code = (pos.get("code") or "").strip().lower()
            percent = float(entry.get("percent", 100) or 100)
            fine = POSITION_CODE_TO_FINE_GROUP.get(code)
            if fine:
                weights[fine] += minutes * (percent / 100.0)
    if not weights:
        return "MID"  # safe fallback when no position codes survive
    return weights.most_common(1)[0][0]


def _code_to_side(code: str) -> str:
    """Map a Wyscout position code to its pitch side: ``"L"``, ``"R"`` or ``"C"``.

    Every flank code in :data:`POSITION_CODE_TO_FINE_GROUP` is prefixed ``l``
    (lcb, lb, lwb, lw, ldmf, lcmf, lamf, lwf and their 3-/5-back variants) or
    ``r`` (the right mirrors); the rest are central (gk, cb, cb3, dmf, cmf, amf,
    cf, ss).
    """
    c = (code or "").strip().lower()
    if c.startswith("l"):
        return "L"
    if c.startswith("r"):
        return "R"
    return "C"


def derive_primary_side(match_stats_list: List[Dict]) -> str:
    """Return the player's preferred pitch side: ``"L"``, ``"R"`` or ``"C"``.

    Mirrors :func:`derive_primary_fine_position`: each match contributes
    ``minutes * percent/100`` to the side of every position code it carries. A
    player is called left- or right-sided when one flank clearly dominates;
    when there is no flank play, or the two flanks are within roughly even
    shares (the dominant flank holds less than 60% of the L+R total, i.e. the
    player is genuinely two-footed or used on both sides), the player is
    treated as central / flexible (``"C"``) so the slot assignment applies no
    side penalty either way.
    """
    weights = {"L": 0.0, "R": 0.0, "C": 0.0}
    for match in match_stats_list:
        minutes = (match.get("total", match) or {}).get("minutesOnField", 0) or 0
        if minutes <= 0:
            continue
        for entry in match.get("positions", []) or []:
            pos = (entry.get("position", {}) or {})
            code = (pos.get("code") or "").strip().lower()
            if code not in POSITION_CODE_TO_FINE_GROUP:
                continue
            percent = float(entry.get("percent", 100) or 100)
            weights[_code_to_side(code)] += minutes * (percent / 100.0)
    sided = weights["L"] + weights["R"]
    if sided <= 0:
        return "C"
    dominant = "L" if weights["L"] >= weights["R"] else "R"
    if weights[dominant] < 0.60 * sided:
        return "C"  # roughly two-footed / used on both flanks
    return dominant


def role_to_group(role_name: str) -> str:
    for key, group in ROLE_TO_GROUP.items():
        if key.lower() in role_name.lower():
            return group
    return "MID"  # default fallback


# ─── Team chronology + availability helpers (Iteration J) ─────────────────────
#
# The composite-score path of the StartingXIPredictor previously ignored the
# *availability* dimension of player evaluation: a player who had not appeared
# in the last few team fixtures (injury, suspension, loss of coach favour, or
# a tactical shift away from their role) was ranked indistinguishably from a
# regular starter, as long as their per-90 KPI rates were similar. Empirical
# validation against actual U Cluj starting elevens (Iteration I) showed this
# was the dominant source of disagreement with the coach's selections:
# top-by-minutes reached Jaccard $\approx 0.634$, while the fine-position
# composite reached only $0.466$.
#
# The availability features below restore that signal. They are computed
# *relative to the team's chronological fixture list*, not the player's own
# appearance list, so a player who simply did not feature in the squad is
# correctly penalised. The implementation respects the methodological
# recommendation of Drew & Finch (2016, Sports Medicine), who argue that
# training-load and availability signals are primary indicators of player
# readiness and should not be discarded by per-90 normalisation.

def get_team_squad_from_matches(
    match_stat_files: List[str],
    team_name_substring: str,
    recent_n: Optional[int] = None,
    min_appearances: int = 5,
) -> set:
    """Identify a team's squad from appearance frequency in their match files.

    The Wyscout drive cache stores `currentTeamId` per player as the
    *snapshot* team registration at the time the profile file was
    exported, not the team a player was registered to at the time of
    each match. For FC Universitatea Cluj specifically, the snapshot
    spreads players across two team IDs (11571 and 60374) depending on
    when each profile was last updated, so a single `currentTeamId ==
    11571` filter misses the bulk of the actual first-team squad.

    This helper sidesteps the issue by identifying the squad
    empirically: a player is considered part of the team if they
    appeared with non-zero minutes in at least ``min_appearances`` of
    the team's most recent ``recent_n`` matches. Opponent players
    typically appear in 1–2 team matches (head-to-head fixtures only),
    so a threshold of ``min_appearances = 2`` strikes the right balance
    between recall (capturing fringe / rotation players) and precision
    (excluding opponent regulars).

    Parameters
    ----------
    match_stat_files
        List of paths to per-match player-stats JSON files.
    team_name_substring
        Case-insensitive substring used to find the team's match files
        in ``match_stat_files`` (each filename carries the home and
        away team names).
    recent_n
        If provided, restrict the appearance count to the team's most
        recent ``recent_n`` matches. When ``None`` (the default), the
        full match history is used — appropriate when the dataset
        already represents a single recent season.
    min_appearances
        Minimum non-zero-minute appearances required for inclusion.
        Default ``5`` reflects the empirical appearance distribution
        for FC Universitatea Cluj's 2024–25 season: opponents appear in
        at most three U Cluj fixtures (twice in the regular season plus
        one playoff meeting for top-six teams), while every U Cluj
        squad member appears in seven or more. A threshold of five
        therefore separates the two populations cleanly while still
        capturing fringe / late-arriving squad players.

    Returns
    -------
    set[int]
        The squad's Wyscout player IDs.
    """
    from collections import Counter
    # Iteration L: use diacritic-insensitive matching so Romanian club
    # names like "Botoşani", "Oţelul", or "Argeș" line up regardless of
    # whether the filesystem stores ş/ţ as cedilla (U+015F/0163) or
    # comma-below (U+0219/021B).
    from sportradar.team_registry import normalise as _norm  # type: ignore

    chronology = get_team_match_chronology(match_stat_files, team_name_substring)
    if recent_n is not None and chronology:
        recent_ids: Optional[set] = set(chronology[-recent_n:])
    else:
        recent_ids = None

    needle = _norm(team_name_substring)
    team_files = [fp for fp in match_stat_files if needle in _norm(fp)]

    appearances: Counter = Counter()
    for fp in team_files:
        try:
            with open(fp, encoding="utf-8") as f:
                data = json.load(f)
            players = data.get("players", [])
            if not players:
                continue
            mid = players[0].get("matchId")
            if recent_ids is not None and mid is not None and int(mid) not in recent_ids:
                continue
            for entry in players:
                pid = entry.get("playerId")
                if pid is None:
                    continue
                mins = (entry.get("total", {}) or {}).get("minutesOnField", 0) or 0
                if mins > 0:
                    appearances[pid] += 1
        except Exception:
            continue

    return {pid for pid, count in appearances.items() if count >= min_appearances}


def get_team_match_chronology(
    match_stat_files: List[str],
    team_name_substring: str,
) -> List[int]:
    """Return the team's match IDs in chronological order.

    Chronology is inferred from each match-stats JSON via the
    ``(seasonId, roundId)`` pair on the first player entry. The match
    files are filtered by checking that ``team_name_substring`` (case
    insensitive) appears in the filename — this is robust because the
    drive-cache files are named ``"{home} - {away}, {score}_players_stats.json"``.

    The returned list is ordered so that the *most recent* match is the
    last element. When a season-round pair is unparseable, the file is
    silently skipped.
    """
    # Iteration L: diacritic-insensitive substring match — required for
    # Romanian club names like "Botoşani" / "Oţelul" / "Argeș" which can
    # be stored with either cedilla or comma-below diacritics depending
    # on the source.
    from sportradar.team_registry import normalise as _norm  # type: ignore

    candidates: List = []
    needle = _norm(team_name_substring)
    for fp in match_stat_files:
        if needle not in _norm(fp):
            continue
        try:
            with open(fp, encoding="utf-8") as f:
                data = json.load(f)
            players = data.get("players", [])
            if not players:
                continue
            first = players[0]
            match_id = first.get("matchId")
            season_id = first.get("seasonId", 0) or 0
            round_id = first.get("roundId", 0) or 0
            if match_id is None:
                continue
            candidates.append((int(season_id), int(round_id), int(match_id)))
        except Exception:
            continue
    # Deduplicate (some files may share matchId if both halves cached separately).
    seen: set = set()
    unique: List = []
    for sid, rid, mid in candidates:
        if mid in seen:
            continue
        seen.add(mid)
        unique.append((sid, rid, mid))
    unique.sort(key=lambda t: (t[0], t[1], t[2]))
    return [t[2] for t in unique]


def compute_availability_features(
    player_match_blocks: List[Dict],
    team_chronology: Optional[List[int]],
    last_n: int = 5,
    long_gap_threshold: int = 3,
    alpha: float = 0.6,
    beta: float = 0.4,
    gamma: float = 0.3,
) -> Dict[str, float]:
    """Compute availability features for one player.

    Parameters
    ----------
    player_match_blocks
        The list of per-match stat blocks for the player (each entry
        carries ``matchId`` and the ``total`` block with ``minutesOnField``
        and ``matchesInStart``). When ``build_dataset_from_files`` builds
        the input, ``total`` is flattened into the entry's top level, so
        the helper reads from either location transparently.
    team_chronology
        Team's match IDs in chronological order (oldest first, most
        recent last). If ``None`` or empty, availability features default
        to neutral values (0.0) so legacy callers continue to work.
    last_n
        Window size for ``availability_last_5``. Default 5 matches.
    long_gap_threshold
        Number of team matches missed before the long-gap penalty fires
        in ``availability_score``. Default 3 (≈ two-week gap in the
        Romanian Superliga calendar).
    alpha, beta, gamma
        Coefficients of the ``availability_score`` aggregate:
        $\\alpha \\cdot \\text{availability\\_last\\_n}
        + \\beta \\cdot \\mathbb{1}[\\text{started\\_last\\_match}]
        - \\gamma \\cdot \\mathbb{1}[\\text{match\\_gap} > \\text{long\\_gap\\_threshold}]$.

    Returns
    -------
    dict
        Keys: ``availability_last_5``, ``started_last_match``,
        ``match_gap_since_last_appearance``, ``availability_score``.
    """
    default = {
        "availability_last_5": 0.0,
        "started_last_match": 0.0,
        "match_gap_since_last_appearance": 99.0,
        "availability_score": 0.0,
    }
    if not team_chronology:
        return default

    # Build a lookup matchId -> (minutes, started).
    by_match: Dict[int, tuple] = {}
    for blk in player_match_blocks or []:
        mid = blk.get("matchId")
        if mid is None:
            continue
        total = blk.get("total", blk) or {}
        mins = float(total.get("minutesOnField", 0) or 0)
        started = float(total.get("matchesInStart", 0) or 0)
        try:
            by_match[int(mid)] = (mins, started)
        except (TypeError, ValueError):
            continue

    # Last N team matches; sum minutes, divide by maximum (N * 90).
    last_n_ids = team_chronology[-last_n:]
    minutes_in_last_n = sum(by_match.get(int(mid), (0.0, 0.0))[0] for mid in last_n_ids)
    availability_last_n = minutes_in_last_n / float(last_n * 90.0)

    # Did the player start the most recent team match?
    last_mid = int(team_chronology[-1])
    _, started_last = by_match.get(last_mid, (0.0, 0.0))
    started_last_match = 1.0 if started_last > 0 else 0.0

    # Gap: how many team matches ago was the player's last *appearance*?
    gap = 99
    for offset, mid in enumerate(reversed(team_chronology)):
        mins, _ = by_match.get(int(mid), (0.0, 0.0))
        if mins > 0:
            gap = offset
            break

    long_gap_flag = 1.0 if gap > long_gap_threshold else 0.0
    availability_score = (
        alpha * availability_last_n
        + beta * started_last_match
        - gamma * long_gap_flag
    )

    return {
        "availability_last_5": round(availability_last_n, 4),
        "started_last_match": float(started_last_match),
        "match_gap_since_last_appearance": float(gap),
        "availability_score": round(availability_score, 4),
    }


def compute_load_features(
    blocks: List[Dict],
    chrono_before_ids: set,
    fixture_date=None,
    birth_date: Optional[str] = None,
) -> Dict:
    """Point-in-time load / fatigue / age / role features for one player.

    Measured strictly from the player's appearances in team matches BEFORE the
    fixture (``chrono_before_ids``), as of ``fixture_date``. Calendar windows
    (rest days, 7/14/28-day load, the acute:chronic workload ratio) read each
    match's date from the date bridge (``block['match_date']``); when a date is
    missing they fall back to neutral values so the pipeline never breaks. The
    acute:chronic workload ratio follows the sports-science load-monitoring
    literature (Gabbett 2016): an acute load far above the chronic baseline
    flags elevated fatigue / injury risk.

    Keys returned: age_at_fixture, season_start_rate, rest_days,
    minutes_last_14d, matches_last_10d, acute_load, chronic_load, acwr,
    minutes_trend, cumulative_minutes_before_fixture, cumulative_appearances.
    """
    from datetime import date as _date, datetime as _dt

    def _pd(x):
        if isinstance(x, _date):
            return x
        if not x:
            return None
        try:
            return _dt.strptime(str(x)[:10], "%Y-%m-%d").date()
        except Exception:
            return None

    fx = _pd(fixture_date) or _date.today()
    ids = chrono_before_ids or set()

    cum_minutes = 0.0
    cum_apps = 0
    cum_starts = 0
    seq = []  # (date_or_None, minutes) per appearance, before the fixture
    for blk in blocks or []:
        try:
            if int(blk.get("matchId")) not in ids:
                continue
        except (TypeError, ValueError):
            continue
        tot = blk.get("total", blk) or {}
        mins = float(tot.get("minutesOnField", 0) or 0)
        if mins <= 0:
            continue
        cum_minutes += mins
        cum_apps += 1
        if float(tot.get("matchesInStart", 0) or 0) > 0:
            cum_starts += 1
        seq.append((_pd(blk.get("match_date")), mins))

    n_before = len(ids)
    season_start_rate = round(cum_starts / n_before, 4) if n_before > 0 else 0.0

    bd = _pd(birth_date)
    age_at_fixture = round((fx - bd).days / 365.25, 1) if bd else 0.0

    dated = sorted([(d, m) for d, m in seq if d is not None], key=lambda t: t[0])
    if dated:
        last_d = dated[-1][0]
        rest_days = float(max(0, (fx - last_d).days))
        min7 = sum(m for d, m in dated if 0 <= (fx - d).days <= 7)
        min14 = sum(m for d, m in dated if 0 <= (fx - d).days <= 14)
        min28 = sum(m for d, m in dated if 0 <= (fx - d).days <= 28)
        matches10 = float(sum(1 for d, m in dated if 0 <= (fx - d).days <= 10))
        acute = float(min7)
        chronic = round(min28 / 4.0, 1)  # average weekly minutes over four weeks
        acwr = round(acute / chronic, 3) if chronic > 0 else 0.0
    else:
        rest_days, min14, matches10, acute, chronic, acwr = 7.0, 0.0, 0.0, 0.0, 0.0, 0.0

    # Minutes trend: mean of the last three appearances minus the prior three
    # (chronological order; negative means the player is being eased out).
    ordered = [m for d, m in sorted(seq, key=lambda t: (t[0] is None, t[0]))]
    last3, prior3 = ordered[-3:], ordered[-6:-3]
    trend = (sum(last3) / len(last3) if last3 else 0.0) - (sum(prior3) / len(prior3) if prior3 else 0.0)

    return {
        "age_at_fixture": age_at_fixture,
        "season_start_rate": season_start_rate,
        "rest_days": rest_days,
        "minutes_last_14d": float(min14),
        "matches_last_10d": matches10,
        "acute_load": acute,
        "chronic_load": float(chronic),
        "acwr": float(acwr),
        "minutes_trend": round(trend, 1),
        "cumulative_minutes_before_fixture": float(cum_minutes),
        "cumulative_appearances": float(cum_apps),
    }


# ─── Methodological helpers ───────────────────────────────────────────────────

def exponential_time_decay_weight(days_ago: float, half_life_days: float = 30.0) -> float:
    """Exponential time-decay weight for recent-form aggregation.

    Returns ``exp(-ln(2) * days_ago / half_life_days)``. With the default
    half-life of 30 days, a match played one month ago contributes half as
    much to the recent-form score as a match played today. This is the
    standard exponential-smoothing formulation; the choice of half-life is
    informed by the typical Romanian Superliga match cadence (roughly one
    fixture per week, so a 30-day window covers the most recent four matches).
    """
    if days_ago <= 0:
        return 1.0
    lam = np.log(2.0) / max(half_life_days, 1e-6)
    return float(np.exp(-lam * days_ago))


def empirical_bayes_shrink(
    raw_value: float,
    n_matches: float,
    position_mean: float,
    pseudo_matches: float = 3.0,
) -> float:
    """Shrink ``raw_value`` toward ``position_mean`` for low-sample players.

    Implements the standard empirical-Bayes update
    ``(k * mu + n * x) / (k + n)`` where ``k`` is a pseudo-count chosen so
    that a player with no observations falls back entirely to the position
    mean while a player with ``n >> k`` observations is essentially
    unchanged. The football-specific application of this formula in player
    rating is treated by Brown (2008) in the context of in-season batting
    averages; the same identity (with the same intuition: shrink toward the
    group mean inversely with sample size) carries over directly.
    """
    n = max(float(n_matches or 0), 0.0)
    k = float(pseudo_matches)
    if (k + n) <= 0:
        return raw_value
    return (k * position_mean + n * raw_value) / (k + n)


def z_score_within_position(
    df: pd.DataFrame,
    columns: List[str],
    position_col: str = "role_group",
) -> pd.DataFrame:
    """Return a copy of ``df`` with the given columns z-scored within each
    positional group (``GK``, ``DEF``, ``MID``, ``FWD``).

    Per Pappalardo et al. (2019), comparing players across positions on raw
    KPIs is invalid because the empirical distribution of every KPI is
    role-conditional. Standardising within position before any aggregation
    is the recommended remedy.
    """
    out = df.copy()
    for group, group_df in out.groupby(position_col):
        for c in columns:
            if c not in group_df.columns:
                continue
            series = group_df[c].astype(float)
            mean = series.mean()
            std = series.std(ddof=0)
            if not std or pd.isna(std):
                std = 1.0
            out.loc[group_df.index, c] = (series - mean) / std
    return out


def compute_performance_score(stats: Dict, role_group: str, fine_group: Optional[str] = None) -> float:
    """Compute a weighted performance score for a player given their stats and role.

    If a fine-grained position group is provided (e.g. ``"CB"``, ``"DM"``),
    the corresponding :data:`FINE_POSITION_STAT_WEIGHTS` row is used. Otherwise
    the function falls back to the four-group :data:`POSITION_STAT_WEIGHTS`
    table for backward compatibility with callers that have not yet been
    updated.
    """
    if fine_group and fine_group in FINE_POSITION_STAT_WEIGHTS:
        weights = FINE_POSITION_STAT_WEIGHTS[fine_group]
    else:
        weights = POSITION_STAT_WEIGHTS.get(role_group, POSITION_STAT_WEIGHTS["MID"])
    total = stats.get("minutesOnField", 0)
    if total == 0:
        return 0.0
    per90 = 90.0 / total  # normalize to per-90 minutes
    score = 0.0
    for stat, w in weights.items():
        val = stats.get(stat, 0) or 0
        score += val * per90 * w
    return round(score, 4)


def compute_efficiency_metrics(stats: Dict) -> Dict:
    """Compute % metrics that capture efficiency regardless of volume."""
    def safe_pct(num, denom):
        return round(num / denom * 100, 2) if denom else 0.0

    return {
        "pass_accuracy": safe_pct(stats.get("successfulPasses", 0), stats.get("passes", 0)),
        "duel_win_rate": safe_pct(stats.get("duelsWon", 0), stats.get("duels", 0)),
        "dribble_success": safe_pct(stats.get("successfulDribbles", 0), stats.get("dribbles", 0)),
        "shot_accuracy": safe_pct(stats.get("shotsOnTarget", 0), stats.get("shots", 0)),
        "aerial_win_rate": safe_pct(stats.get("aerialDuelsWon", 0), stats.get("aerialDuels", 0)),
        "cross_accuracy": safe_pct(stats.get("successfulCrosses", 0), stats.get("crosses", 0)),
        "def_action_success": safe_pct(stats.get("successfulDefensiveAction", 0), stats.get("defensiveActions", 0)),
    }


def build_player_feature_vector(
    player_profile: Dict,
    match_stats_list: List[Dict],  # list of per-match stat blocks for this player
    opponent_team_id: Optional[int] = None,
    team_chronology: Optional[List[int]] = None,
    as_of_date=None,
) -> Optional[Dict]:
    """
    Merge player profile + aggregated match stats into a flat feature dict.

    Args:
        player_profile: The player JSON object (wyId, role, birthDate, etc.)
        match_stats_list: List of stat dicts (total block) from each match JSON
        opponent_team_id: If provided, can filter or weight recent form
        team_chronology: Optional list of the team's matchIds in chronological
            order (oldest first, most recent last). When provided, the
            availability features defined by
            :func:`compute_availability_features` (``availability_last_5``,
            ``started_last_match``, ``match_gap_since_last_appearance``,
            ``availability_score``) are added to the output dict. When
            omitted, those columns default to neutral zero values so legacy
            callers continue to receive a comparable schema.

    Returns:
        Feature dict ready to be put in a DataFrame row, or None if no valid stats.
    """
    valid_stats = [s for s in match_stats_list if s.get("minutesOnField", 0) > 0]
    if not valid_stats:
        return None

    # ── Positions played (encoded as set of codes) ───────────────────────────
    all_positions = set()
    position_names = []
    for s in match_stats_list:
        for pos in s.get("positions", []):
            code = pos.get("position", {}).get("code", "")
            name = pos.get("position", {}).get("name", "")
            if code:
                all_positions.add(code)
            if name:
                position_names.append(name)

    role_name = player_profile.get("role", {}).get("name", "Midfielder")
    if role_name == "Midfielder" and position_names:
        from collections import Counter
        role_name = Counter(position_names).most_common(1)[0][0]
    
    role_group = role_to_group(role_name)

    # Fine-grained primary position, derived from the Wyscout per-match
    # `positions` array (most-frequent code weighted by minutes played).
    # We pass match_stats_list verbatim because the entries already contain
    # `positions` and `minutesOnField` at the top level after `build_dataset_from_files`.
    position_group_fine = derive_primary_fine_position(match_stats_list)
    position_side = derive_primary_side(match_stats_list)

    # ── Aggregate stats across matches ──────────────────────────────────────
    agg = {}
    count = len(valid_stats)
    all_keys = valid_stats[0].keys()
    for k in all_keys:
        try:
            agg[k] = sum((s.get(k, 0) or 0) for s in valid_stats
                         if isinstance(s.get(k, 0), (int, float)))
        except TypeError:
            agg[k] = 0

    minutes_total = agg.get("minutesOnField", 1) or 1

    # Per-90 stats
    per90 = {k: round(v / minutes_total * 90, 4) for k, v in agg.items()
              if isinstance(v, (int, float))}

    # ── Performance score ────────────────────────────────────────────────────
    # Use the fine-grained position weights when the per-match position codes
    # are available; otherwise fall back to the coarse role-group weights.
    perf_score = compute_performance_score(agg, role_group, fine_group=position_group_fine)

    # ── Efficiency metrics ───────────────────────────────────────────────────
    efficiency = compute_efficiency_metrics(agg)

    # ── Recent form (exponentially decayed by recency) ───────────────────────
    # If per-match dates are available we apply an exponential time decay with
    # a 30-day half-life (see :func:`exponential_time_decay_weight`); otherwise
    # we fall back to a simple unweighted average of the last three matches.
    recent = valid_stats[-min(len(valid_stats), 10):]
    per_match_scores = [
        compute_performance_score(s, role_group, fine_group=position_group_fine)
        for s in recent
    ]
    today = None
    try:
        from datetime import date, datetime  # local import to avoid hard dep at module top
        today = date.today()
    except Exception:
        today = None

    weights: List[float] = []
    if today is not None:
        for s in recent:
            d = s.get("date") or s.get("matchDate")
            try:
                if isinstance(d, str):
                    match_date = datetime.strptime(d[:10], "%Y-%m-%d").date()
                elif isinstance(d, (int, float)):
                    match_date = datetime.fromtimestamp(float(d)).date()
                else:
                    match_date = None
                days_ago = (today - match_date).days if match_date else None
            except Exception:
                days_ago = None
            weights.append(exponential_time_decay_weight(days_ago, 30.0) if days_ago is not None else 1.0)

    if per_match_scores and any(w != 1.0 for w in weights):
        denom = float(np.sum(weights)) or 1.0
        recent_score = float(np.dot(per_match_scores, weights) / denom)
    elif per_match_scores:
        # Fall back to the previous "last three matches, uniform" behaviour
        recent_score = float(np.mean(per_match_scores[-3:]))
    else:
        recent_score = 0.0

    # ── Age ──────────────────────────────────────────────────────────────────
    birth = player_profile.get("birthDate", "")
    age = 0
    if birth:
        try:
            from datetime import date, datetime
            bd = datetime.strptime(birth, "%Y-%m-%d").date()
            age = (date.today() - bd).days / 365.25
        except Exception:
            pass


    # ── Availability features (Iteration J) ──────────────────────────────────
    # When the caller supplied a team-match chronology, derive availability
    # features that compare the player's appearances to the team's most-recent
    # fixture list. Without a chronology, neutral zeros are emitted so callers
    # that did not opt in still receive a consistent column schema.
    availability = compute_availability_features(match_stats_list, team_chronology)

    # Point-in-time load / fatigue / age / role features. At inference every
    # team match is "before" the upcoming fixture, so the whole chronology is
    # the pre-fixture window and ``as_of_date`` is the date we predict for (the
    # demo / current clock, passed by the caller; defaults to today).
    _chrono_ids = set()
    for _m in (team_chronology or []):
        try:
            _chrono_ids.add(int(_m))
        except (TypeError, ValueError):
            pass
    load = compute_load_features(
        match_stats_list, _chrono_ids, as_of_date, player_profile.get("birthDate", "")
    )
    # Do NOT surface cumulative_minutes_before_fixture / cumulative_appearances
    # at inference: the deployed model lists them in feature_cols but has always
    # been served zeros for them, so emitting them now would silently shift the
    # predicted XI. The load-aware retrain re-enables them and re-validates. The
    # rotation advisor uses the remaining load fields (acwr, rest_days, etc.).
    _load_emit = {
        k: v for k, v in load.items()
        if k not in ("cumulative_minutes_before_fixture", "cumulative_appearances")
    }

    feature = {
        "playerId": player_profile.get("wyId"),
        "shortName": player_profile.get("shortName", ""),
        "role": role_name,
        "role_group": role_group,
        "position_group_fine": position_group_fine,
        "position_side": position_side,
        "age": round(age, 1),
        "birth_date": player_profile.get("birthDate", ""),
        "matches_played": count,
        "total_minutes": minutes_total,
        "performance_score": perf_score,
        "recent_form_score": round(recent_score, 4),
        **{f"per90_{k}": v for k, v in per90.items()},
        **efficiency,
        **availability,
        **_load_emit,
        "positions_played": ",".join(sorted(all_positions)),
    }
    return feature


def load_match_stats_json(filepath: str) -> List[Dict]:
    """Load a match stats JSON file and return the players list."""
    with open(filepath) as f:
        data = json.load(f)
    return data.get("players", [])


def build_dataset_from_files(
    match_stat_files: List[str],
    player_profiles: Dict[int, Dict],  # playerId -> profile dict
    opponent_team_id: Optional[int] = None,
    availability_team_substring: Optional[str] = None,
    as_of_date=None,
) -> pd.DataFrame:
    """
    Given multiple match stat files and a player profile lookup,
    build a full feature DataFrame.

    Args:
        match_stat_files: List of paths to match JSON files
        player_profiles: Dict mapping wyId -> player profile dict
        opponent_team_id: Filter/weight for a specific opponent
        availability_team_substring: If provided (e.g.
            ``"Universitatea Cluj"``), the helper computes the
            chronological list of that team's match IDs and passes it
            into :func:`build_player_feature_vector` so the resulting
            DataFrame gains the four availability columns
            (``availability_last_5``, ``started_last_match``,
            ``match_gap_since_last_appearance``, ``availability_score``).
            For non-team players (opponents in a multi-team build), the
            availability columns remain neutral zeros.

    Returns:
        DataFrame with one row per player
    """
    # Collect all stats per player
    from ml.match_dates import date_for as _date_for  # committed matchId -> date bridge
    player_stats_map: Dict[int, List[Dict]] = {}

    for filepath in match_stat_files:
        match_players = load_match_stats_json(filepath)
        for entry in match_players:
            pid = entry.get("playerId")
            if pid is None:
                continue
            if pid not in player_stats_map:
                player_stats_map[pid] = []
            # Attach positions and total stats together for convenience
            combined = dict(entry.get("total", {}))
            combined["positions"] = entry.get("positions", [])
            combined["matchId"] = entry.get("matchId")
            combined["match_date"] = _date_for(entry.get("matchId"))
            # Preserve the season + round metadata in the flattened block so
            # callers downstream (e.g. the lineup classifier) can reconstruct
            # the per-match chronology without re-reading the JSON.
            combined["seasonId"] = entry.get("seasonId")
            combined["roundId"] = entry.get("roundId")
            # Keep the full `total` dict accessible so availability helpers
            # can read `minutesOnField` / `matchesInStart` from either path.
            combined["total"] = dict(entry.get("total", {}))
            player_stats_map[pid].append(combined)

    # Pre-compute team chronology if requested. The chronology is the team's
    # matchIds sorted by (seasonId, roundId, matchId) — see
    # :func:`get_team_match_chronology`.
    team_chronology: Optional[List[int]] = None
    if availability_team_substring:
        team_chronology = get_team_match_chronology(
            match_stat_files, availability_team_substring
        )

    # Identify the team's actual squad empirically (see
    # :func:`get_team_squad_from_matches` for the rationale — Wyscout's
    # ``currentTeamId`` field is unreliable for FC Universitatea Cluj, with
    # the squad spread across two team IDs because of profile-snapshot
    # timing). Availability features are computed only for the empirically
    # detected squad. Non-squad players (including U Cluj's opponents who
    # appear in U Cluj match files) receive neutral zero values, which is
    # the correct behaviour because their match-blocks for U Cluj fixtures
    # represent appearances *against* U Cluj, not for U Cluj.
    team_player_ids: set = set()
    if availability_team_substring and team_chronology:
        team_player_ids = get_team_squad_from_matches(
            match_stat_files, availability_team_substring,
        )

    rows = []
    for pid, stats_list in player_stats_map.items():
        profile = player_profiles.get(pid, {"wyId": pid, "role": {"name": "Midfielder"}})
        chrono_for_player = (
            team_chronology
            if (team_chronology is not None and pid in team_player_ids)
            else None
        )
        row = build_player_feature_vector(
            profile, stats_list, opponent_team_id,
            team_chronology=chrono_for_player,
            as_of_date=as_of_date,
        )
        if row:
            rows.append(row)

    return pd.DataFrame(rows)
