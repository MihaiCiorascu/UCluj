"""Baked 2025-26 Romanian Superliga fixtures, served by round.

The committee demo runs against the 2025-26 season, but the Sportradar trial
tier returns no usable schedule for it and ``data/All_Data.csv`` only carries
seasons 2020-2024 (so the live week-fixtures slice came back EMPTY for any
2026 date). This module makes a committed, fully-built dataset
(``ml/data/superliga_2025_26_fixtures.json``) the single source of truth for
the 2025-26 dashboard: it is loaded ONCE at import, exposes every fixture with
its ``round`` (1..33) and ``phase`` ("regular" | "playoff_window"), and resolves
which round is "current" relative to the server's effective clock so the
week-fixtures endpoint can reinterpret its ``week_offset`` as a ROUND offset.

No Sportradar call is ever made here; the dataset is the only input.

Dataset shape (verified at build time)::

    {
      "season": "2025",
      "round_count": 33,
      "fixtures": [
        {"match_id": str, "date": "YYYY-MM-DD", "round": int(1..33),
         "phase": "regular" | "playoff_window",
         "home_team": <registry short>, "away_team": <registry short>,
         "home_score": int | null, "away_score": int | null, "venue": null},
        ...
      ]
    }

The team names in the dataset are registry shorts (e.g. "U Cluj", "FCSB",
"U Craiova", "Oţelul Galaţi"). ``CANONICAL_TEAM_MAP`` maps each short onto the
canonical ``All_Data.csv`` name so the existing CatBoost feature lookup
(``FeatureService.win_prob``) resolves real rolling form; see
``canonical_team_name``.
"""
from __future__ import annotations

import json
import logging
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# The committed dataset lives under ml/data next to this package.
_DATASET_PATH = Path(__file__).parent.parent / "ml" / "data" / "superliga_2025_26_fixtures.json"

# The SuperLiga season label this dataset covers. Matches the ``season`` column
# convention in All_Data.csv (the 2025-26 campaign is tagged "2025").
BAKED_SEASON: str = "2025"


# Registry-short → All_Data.csv canonical team name. The baked dataset stores
# diacritic registry shorts; the CSV (which backs the CatBoost feature lookup)
# uses ASCII canonical names with different prefixes. Without this bridge the
# win-probability lookup would miss most teams and fall back to imputed medians,
# producing flat, meaningless probabilities. Names already identical in both
# sources (CFR Cluj, FCSB, U Cluj, UTA Arad, Unirea Slobozia) are mapped to
# themselves for clarity. "U Craiova" maps to "Univ. Craiova", the CSV variant
# with the deepest history (200+ rows) so the rolling form is well-populated.
CANONICAL_TEAM_MAP: dict[str, str] = {
    "U Cluj": "U Cluj",
    "CFR Cluj": "CFR Cluj",
    "FCSB": "FCSB",
    "UTA Arad": "UTA Arad",
    "Unirea Slobozia": "Unirea Slobozia",
    "Botoşani": "FC Botosani",
    "Csikszereda": "Csikszereda M. Ciuc",
    "Dinamo Bucureşti": "Dinamo Bucuresti",
    "FC Argeş": "FC Arges",
    "Farul Constanţa": "Farul Constanta",
    "Hermannstadt": "FC Hermannstadt",
    "Metaloglobus": "Metaloglobus Bucuresti",
    "Oţelul Galaţi": "Otelul Galati",
    "Petrolul Ploieşti": "Petrolul Ploiesti",
    "Rapid Bucureşti": "Rapid Bucuresti",
    "U Craiova": "Univ. Craiova",
}


def canonical_team_name(name: str) -> str:
    """Map a baked-dataset registry short to its All_Data.csv canonical name.

    Falls through to the input unchanged when the team is not in the map, so an
    already-canonical name (or an unexpected new team) is never lost.
    """
    return CANONICAL_TEAM_MAP.get((name or "").strip(), name)


# Module-level cache. The dataset is small (278 fixtures) and immutable, so it
# is parsed once at first access and reused for the process lifetime.
_FIXTURES_CACHE: list[dict] | None = None
_ROUNDS_CACHE: dict[int, dict] | None = None


def _parse_date(value: str) -> date:
    """Parse a 'YYYY-MM-DD' fixture date. Returns date.min on a bad value."""
    try:
        return date.fromisoformat(str(value)[:10])
    except (TypeError, ValueError):
        return date.min


def load_baked_fixtures() -> list[dict]:
    """Return every baked fixture as a list of dicts (cached, sorted by date).

    Each dict is the raw dataset record: ``match_id, date, round, phase,
    home_team, away_team, home_score, away_score, venue``. The list is parsed
    once and cached; callers must treat it as read-only.
    """
    global _FIXTURES_CACHE
    if _FIXTURES_CACHE is not None:
        return _FIXTURES_CACHE

    try:
        raw = json.loads(_DATASET_PATH.read_text(encoding="utf-8"))
        fixtures = list(raw.get("fixtures", []))
    except Exception as exc:  # noqa: BLE001 - never let a bad file break boot
        logger.warning("Could not load baked fixtures from %s: %s", _DATASET_PATH, exc)
        fixtures = []

    fixtures.sort(key=lambda f: (str(f.get("date", "")), int(f.get("round", 0) or 0)))
    _FIXTURES_CACHE = fixtures
    return _FIXTURES_CACHE


def _round_index() -> dict[int, dict]:
    """Return {round_number: {min_date, max_date, phase, fixtures: [...]}}.

    Built once from the baked fixtures. ``min_date``/``max_date`` are the date
    span of the round, used to bracket the effective date when resolving the
    current round.
    """
    global _ROUNDS_CACHE
    if _ROUNDS_CACHE is not None:
        return _ROUNDS_CACHE

    index: dict[int, dict] = {}
    for f in load_baked_fixtures():
        rnd = int(f.get("round", 0) or 0)
        if rnd <= 0:
            continue
        d = _parse_date(f.get("date", ""))
        entry = index.get(rnd)
        if entry is None:
            index[rnd] = {
                "round": rnd,
                "min_date": d,
                "max_date": d,
                "phase": f.get("phase", "regular"),
                "fixtures": [f],
            }
        else:
            entry["min_date"] = min(entry["min_date"], d)
            entry["max_date"] = max(entry["max_date"], d)
            entry["fixtures"].append(f)

    _ROUNDS_CACHE = index
    return _ROUNDS_CACHE


def round_bounds() -> tuple[int, int]:
    """Return (min_round, max_round) present in the dataset, e.g. (1, 33)."""
    idx = _round_index()
    if not idx:
        return (1, 1)
    rounds = sorted(idx.keys())
    return (rounds[0], rounds[-1])


def resolve_current_round(now: datetime) -> int:
    """Resolve the round whose date span is "current" for ``now``.

    Resolution order:
      1. The round whose [min_date, max_date] inclusive span BRACKETS ``now``.
         When several rounds overlap the date (rare catch-up scheduling), the
         one with the latest ``min_date`` wins, i.e. the most recently started.
      2. Otherwise the MOST RECENT round whose ``min_date`` is on or before
         ``now`` (the last round that has already kicked off).
      3. Otherwise (``now`` precedes the whole season) the first round.

    The result is always clamped to the dataset's [min_round, max_round].
    """
    idx = _round_index()
    if not idx:
        return 1

    today = now.astimezone(timezone.utc).date() if now.tzinfo else now.date()
    lo, hi = round_bounds()

    bracketing = [
        e for e in idx.values()
        if e["min_date"] <= today <= e["max_date"]
    ]
    if bracketing:
        chosen = max(bracketing, key=lambda e: e["min_date"])
        return min(max(chosen["round"], lo), hi)

    started = [e for e in idx.values() if e["min_date"] <= today]
    if started:
        chosen = max(started, key=lambda e: e["min_date"])
        return min(max(chosen["round"], lo), hi)

    return lo


def round_for_offset(now: datetime, offset: int) -> int:
    """Map a week_offset onto an absolute round number.

    ``offset`` is reinterpreted as a ROUND offset from the current round:
    0 = current round, -1 = previous, +1 = next. The result is clamped to the
    dataset's [min_round, max_round] so the dashboard's +/- navigation never
    walks off either end of the season.
    """
    lo, hi = round_bounds()
    target = resolve_current_round(now) + offset
    return min(max(target, lo), hi)


def fixtures_for_round(round_number: int) -> list[dict]:
    """Return the baked fixtures for ``round_number`` in WeekFixture shape.

    Each returned dict carries the field names the Flutter ``WeekFixture``
    parser expects (match_id, season, match_date, home_team, away_team,
    home_score, away_score, venue, round, phase). The team names stay as the
    registry shorts the dataset stores; ML enrichment normalises them via
    ``canonical_team_name`` for the CatBoost lookup. Sorted by date then by
    match_id for a stable order.
    """
    idx = _round_index()
    entry = idx.get(int(round_number))
    if entry is None:
        return []

    out: list[dict] = []
    for f in sorted(
        entry["fixtures"],
        key=lambda x: (str(x.get("date", "")), str(x.get("match_id", ""))),
    ):
        out.append(_to_week_fixture(f))
    return out


def _to_week_fixture(f: dict[str, Any]) -> dict:
    """Convert a raw baked record to a WeekFixture-shaped dict."""
    return {
        "match_id": str(f.get("match_id", "")),
        "season": BAKED_SEASON,
        "match_date": str(f.get("date", "")),
        "home_team": f.get("home_team", ""),
        "away_team": f.get("away_team", ""),
        "home_score": f.get("home_score"),
        "away_score": f.get("away_score"),
        "venue": f.get("venue"),
        "round": int(f.get("round", 0) or 0) or None,
        "phase": f.get("phase"),
    }


def is_baked_season(season: str | None) -> bool:
    """True when ``season`` is the season the baked dataset covers ("2025")."""
    return season is not None and str(season) == BAKED_SEASON


# ---------------------------------------------------------------------------
# Standings (play-off / play-out split) from the baked completed scores
# ---------------------------------------------------------------------------

# Regular-season cutoff for the 2025-26 SuperLiga. Fixtures dated strictly
# before this split into the top-6 Championship group and the bottom-10
# Relegation group, matching ``FixtureService._REGULAR_SEASON_CUTOFFS["2025"]``.
# Round 30 (the regular season's last round) was played 6-9 March 2026 as one
# table; the Championship and Relegation groups began on 13-14 March 2026.
_REGULAR_SEASON_CUTOFF: date = date(2026, 3, 13)


def _build_table(rows: list[dict]) -> list[dict]:
    """Aggregate a list of completed baked fixtures into a sorted league table.

    Mirrors ``FixtureService._build_standings``: points = 3*W + 1*D, ordered by
    points, then goal difference, then goals for. Team names are emitted as the
    CANONICAL (CSV) names so they line up with the rest of the demo's team
    references; the frontend ``_loadPlayoffGroups`` normalises names anyway.
    Returns the same row shape the standings endpoints already emit.
    """
    teams: dict[str, dict] = {}
    for r in rows:
        hs = r.get("home_score")
        as_ = r.get("away_score")
        if hs is None or as_ is None:
            continue
        ht = canonical_team_name(r.get("home_team", ""))
        at = canonical_team_name(r.get("away_team", ""))
        hs = int(hs)
        as_ = int(as_)
        for t in (ht, at):
            if t not in teams:
                teams[t] = {
                    "team": t, "played": 0, "wins": 0, "draws": 0,
                    "losses": 0, "gf": 0, "ga": 0, "pts": 0,
                }
        teams[ht]["played"] += 1
        teams[at]["played"] += 1
        teams[ht]["gf"] += hs
        teams[ht]["ga"] += as_
        teams[at]["gf"] += as_
        teams[at]["ga"] += hs
        if hs > as_:
            teams[ht]["wins"] += 1
            teams[ht]["pts"] += 3
            teams[at]["losses"] += 1
        elif hs < as_:
            teams[at]["wins"] += 1
            teams[at]["pts"] += 3
            teams[ht]["losses"] += 1
        else:
            teams[ht]["draws"] += 1
            teams[at]["draws"] += 1
            teams[ht]["pts"] += 1
            teams[at]["pts"] += 1

    ordered = sorted(
        teams.values(),
        key=lambda t: (-t["pts"], -(t["gf"] - t["ga"]), -t["gf"]),
    )
    return [
        {
            "position": i,
            "team": t["team"],
            "played": t["played"],
            "wins": t["wins"],
            "draws": t["draws"],
            "losses": t["losses"],
            "goals_for": t["gf"],
            "goals_against": t["ga"],
            "goal_difference": t["gf"] - t["ga"],
            "points": t["pts"],
        }
        for i, t in enumerate(ordered, 1)
    ]


def baked_standings_with_groups() -> dict:
    """Return the three-bucket standings for the baked 2025-26 season.

    ``regular``: the full 16-team table from every completed fixture dated
    before the regular-season cutoff (2026-03-13). ``championship``: the top six
    of that table, re-ranked from 1. ``relegation``: the bottom ten, re-ranked
    from 1. Shape mirrors ``FixtureService.standings_with_groups`` so it can be
    consumed by the same endpoints. Buckets are computed from the baked
    completed scores only, never from Sportradar.
    """
    regular_rows: list[dict] = []
    for f in load_baked_fixtures():
        if _parse_date(f.get("date", "")) < _REGULAR_SEASON_CUTOFF:
            regular_rows.append(f)

    table = _build_table(regular_rows)

    if len(table) >= 16:
        championship = [dict(r) for r in table[:6]]
        relegation = [dict(r) for r in table[6:]]
        for i, row in enumerate(championship, 1):
            row["position"] = i
        for i, row in enumerate(relegation, 1):
            row["position"] = i
    else:
        championship = []
        relegation = []

    return {
        "regular": table,
        "championship": championship,
        "relegation": relegation,
    }
