"""
League-wide starting-XI history extractor (Iteration L.3a).

Generalises ``extract_starting_xi_history.py`` (which was U Cluj-only)
to every team in :data:`backend.sportradar.team_registry.SUPERLIGA_TEAMS`.
For each team and each of their match files in
``backend/ml/data/drive_cache/``, the script identifies the players who
started the fixture for that team (``matchesInStart > 0``) and emits a
combined JSON file with all sixteen teams' starting-XI histories.

The combined file is the canonical training input for the league-wide
supervised lineup classifier (Iteration L.3b + L.4).

Output: ``backend/ml/data/lineup_history_league.json`` with structure::

    {
      "n_teams": 16,
      "teams": [
        {
          "team_short": "U Cluj",
          "team_sr_id": "sr:competitor:7734",
          "team_wy_substr": "Universitatea Cluj",
          "n_fixtures": 35,
          "n_squad_players": 27,
          "squad_ids": [...],
          "fixtures": [
            {
              "match_id": int,
              "season_id": int,
              "round_id": int,
              "filename": str,
              "starters": [{"playerId", "shortName", "role_group", "minutes"}, ...],
              "subs":     [{"playerId", "shortName", "role_group", "minutes"}, ...]
            },
            ...
          ]
        },
        ...
      ]
    }

The per-team blocks are independent (each team has its own chronology
and squad), but the file is intentionally one document so the classifier
trainer can scan it linearly without globbing.
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
from sportradar.team_registry import (  # type: ignore  # noqa: E402
    SUPERLIGA_TEAMS,
    files_for_team,
)

DRIVE = ROOT / "ml" / "data" / "drive_cache"
OUT_PATH = ROOT / "ml" / "data" / "lineup_history_league.json"


def _role_group(profile: dict) -> str:
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

    all_match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    print(f"Indexing {len(all_match_files)} match files ...")

    league_blob: dict = {
        "n_teams": len(SUPERLIGA_TEAMS),
        "teams": [],
    }

    total_starters = 0
    total_fixtures = 0
    print()
    print(f"{'team':24s} {'fixtures':9s} {'squad':6s} {'starters':9s}")
    print("-" * 55)

    for team in SUPERLIGA_TEAMS:
        team_files = files_for_team(all_match_files, team)
        if not team_files:
            print(f"{team.short:24s} (no Wyscout files; skipped)")
            continue

        chronology = get_team_match_chronology(all_match_files, team.wy_substr)
        squad = get_team_squad_from_matches(all_match_files, team.wy_substr)

        # matchId -> filename lookup over this team's files only.
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

        team_fixtures = []
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

            team_fixtures.append({
                "match_id": int(mid),
                "season_id": int(season_id) if season_id is not None else None,
                "round_id": int(round_id) if round_id is not None else None,
                "filename": os.path.basename(fp),
                "starters": starters,
                "subs": subs,
            })
            total_starters += len(starters)

        league_blob["teams"].append({
            "team_short": team.short,
            "team_sr_id": team.sr_id,
            "team_wy_substr": team.wy_substr,
            "n_fixtures": len(team_fixtures),
            "n_squad_players": len(squad),
            "squad_ids": sorted(int(p) for p in squad),
            "fixtures": team_fixtures,
        })
        total_fixtures += len(team_fixtures)
        print(f"{team.short:24s} {len(team_fixtures):9d} {len(squad):6d} "
              f"{sum(len(f['starters']) for f in team_fixtures):9d}")

    print("-" * 55)
    print(f"{'LEAGUE TOTAL':24s} {total_fixtures:9d} {'-':6s} {total_starters:9d}")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(league_blob, f, indent=2, ensure_ascii=False)
    sz = os.path.getsize(OUT_PATH)
    print(f"\nWrote {OUT_PATH.relative_to(ROOT)} ({sz:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
