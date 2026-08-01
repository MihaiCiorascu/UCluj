"""
Extract historical FC Universitatea Cluj starting elevens from the
drive-cache match-stats JSONs.

For each U Cluj fixture in ``backend/ml/data/drive_cache/*Universitatea Cluj*``,
this script identifies the players who started the match for U Cluj
(``matchesInStart == 1``) and writes a per-fixture record with::

    {
      "match_id": int,
      "season_id": int,
      "round_id": int,
      "filename": str,
      "starters": [{"playerId": ..., "shortName": ..., "role_group": ..., "minutes": ...}, ...],
      "subs":     [{"playerId": ..., "shortName": ..., "role_group": ..., "minutes": ...}, ...]
    }

The output is consumed by ``train_lineup_classifier.py`` to build the
binary-classification training table. Output path:
``backend/ml/data/lineup_history.json``.

Rationale: the supervised lineup classifier is the methodological
complement to the heuristic composite, since it learns directly which
combinations of availability, position and opponent context the coach
actually picks.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    get_team_match_chronology,
    get_team_squad_from_matches,
)
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402

DRIVE = ROOT / "ml" / "data" / "drive_cache"
OUT_PATH = ROOT / "ml" / "data" / "lineup_history.json"

TEAM_SUBSTRING = "Universitatea Cluj"


def _role_group(profile: dict) -> str:
    """Best-effort role-group lookup from a player profile."""
    role_name = (profile.get("role") or {}).get("name", "")
    n = role_name.lower()
    if "goalkeeper" in n or "gk" in n:
        return "GK"
    if "defender" in n or "back" in n:
        return "DEF"
    if "midfielder" in n or "midfield" in n:
        return "MID"
    if "forward" in n or "striker" in n or "winger" in n:
        return "FWD"
    return "MID"


def main() -> int:
    profile_path = DRIVE / "players (1).json"
    if not profile_path.exists():
        print(f"Player profile file missing: {profile_path}", file=sys.stderr)
        return 1
    profiles = load_player_profiles(str(profile_path))

    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    chronology = get_team_match_chronology(match_files, TEAM_SUBSTRING)
    squad = get_team_squad_from_matches(match_files, TEAM_SUBSTRING)

    # Build matchId -> filename lookup over U Cluj files only.
    needle = TEAM_SUBSTRING.lower()
    team_files = [fp for fp in match_files if needle in fp.lower()]
    mid_to_file = {}
    for fp in team_files:
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
            players = d.get("players", [])
            if players:
                mid = players[0].get("matchId")
                if mid is not None:
                    mid_to_file[int(mid)] = fp
        except Exception:
            continue

    fixtures = []
    for mid in chronology:
        fp = mid_to_file.get(int(mid))
        if fp is None:
            continue
        with open(fp, encoding="utf-8") as f:
            d = json.load(f)
        players = d.get("players", [])
        first = players[0] if players else {}
        season_id = first.get("seasonId")
        round_id = first.get("roundId")

        starters = []
        subs = []
        for p in players:
            pid = p.get("playerId")
            if pid not in squad:
                continue
            total = p.get("total", {}) or {}
            minutes = float(total.get("minutesOnField", 0) or 0)
            started = float(total.get("matchesInStart", 0) or 0)
            profile = profiles.get(pid, {})
            record = {
                "playerId": pid,
                "shortName": profile.get("shortName", ""),
                "role_group": _role_group(profile),
                "minutes": minutes,
            }
            if started > 0:
                starters.append(record)
            elif minutes > 0:
                subs.append(record)

        fixtures.append({
            "match_id": int(mid),
            "season_id": int(season_id) if season_id is not None else None,
            "round_id": int(round_id) if round_id is not None else None,
            "filename": os.path.basename(fp),
            "starters": starters,
            "subs": subs,
        })

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump({
            "team": TEAM_SUBSTRING,
            "n_fixtures": len(fixtures),
            "n_squad_players": len(squad),
            "squad_ids": sorted(int(p) for p in squad),
            "fixtures": fixtures,
        }, f, indent=2, ensure_ascii=False)
    print(
        f"Wrote {len(fixtures)} fixtures (squad size {len(squad)}) -> "
        f"{OUT_PATH.relative_to(ROOT)}"
    )
    # Quick summary
    total_starters = sum(len(f["starters"]) for f in fixtures)
    print(f"Total starter records: {total_starters} "
          f"(avg {total_starters/len(fixtures):.1f} per fixture)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
