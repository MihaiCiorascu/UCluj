"""
Cross-check Wyscout-derived fine positions against the Transfermarkt snapshot.

Reads:
  - ``ml/data/drive_cache/players (1).json``, Wyscout profiles for the
    FC Universitatea Cluj squad.
  - ``ml/data/transfermarkt_positions.json``, produced by
    :mod:`scripts.fetch_transfermarkt_positions`.

Writes a CSV (``ml/data/position_cross_check.csv``) with one row per
player, columns ``[wyId, name, wyscout_fine, transfermarkt_primary,
match]``, and prints the overall match rate.

If the Transfermarkt snapshot is empty or marked ``status: skipped`` (the
wrapper was not installed when the fetch script ran), the script reports
that and exits without an error so it remains usable in CI.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    POSITION_CODE_TO_FINE_GROUP,
    derive_primary_fine_position,
)
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402

DRIVE = ROOT / "ml" / "data" / "drive_cache"
TM_PATH = ROOT / "ml" / "data" / "transfermarkt_positions.json"
OUT_CSV = ROOT / "ml" / "data" / "position_cross_check.csv"
UCLUJ_TEAM_ID = 11571

TRANSFERMARKT_TO_FINE: dict[str, str] = {
    "Goalkeeper": "GK",
    "Centre-Back": "CB",
    "Left-Back": "FB",
    "Right-Back": "FB",
    "Defender": "CB",
    "Defensive Midfield": "DM",
    "Central Midfield": "CM",
    "Attacking Midfield": "AM",
    "Left Midfield": "CM",
    "Right Midfield": "CM",
    "Left Winger": "W",
    "Right Winger": "W",
    "Second Striker": "WF",
    "Centre-Forward": "ST",
    "Striker": "ST",
    "Forward": "ST",
}


def _build_wyscout_fine(profiles: dict[int, dict]) -> dict[int, str]:
    """Return ``{wyId: fine_group}`` for every U Cluj player."""
    files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    player_stats: dict[int, list[dict]] = {}
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            data = json.load(f)
        for entry in data.get("players", []) or []:
            pid = entry.get("playerId")
            if pid is None:
                continue
            combined = dict(entry.get("total") or {})
            combined["positions"] = entry.get("positions") or []
            combined["matchId"] = entry.get("matchId")
            player_stats.setdefault(pid, []).append(combined)
    result: dict[int, str] = {}
    for pid, stats in player_stats.items():
        prof = profiles.get(pid, {})
        if prof.get("currentTeamId") != UCLUJ_TEAM_ID:
            continue
        result[pid] = derive_primary_fine_position(stats)
    return result


def main() -> int:
    if not TM_PATH.exists():
        print(f"{TM_PATH} not found. Run fetch_transfermarkt_positions.py first.")
        return 1
    with TM_PATH.open("r", encoding="utf-8") as f:
        tm_blob = json.load(f)
    if tm_blob.get("status") != "ok" or not tm_blob.get("entries"):
        print(
            f"Transfermarkt snapshot status: {tm_blob.get('status', 'empty')}. "
            "Cross-check skipped."
        )
        return 0

    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    fine = _build_wyscout_fine(profiles)

    rows: list[dict] = []
    matches = 0
    for wy_id_str, entry in tm_blob["entries"].items():
        wy_id = int(wy_id_str)
        wyscout_fine = fine.get(wy_id, "?")
        tm_primary = entry.get("primary_position") or ""
        mapped = TRANSFERMARKT_TO_FINE.get(tm_primary, "?")
        match = wyscout_fine == mapped
        if match:
            matches += 1
        rows.append({
            "wyId": wy_id,
            "name": entry.get("name", ""),
            "wyscout_fine": wyscout_fine,
            "transfermarkt_primary": tm_primary,
            "transfermarkt_fine_mapped": mapped,
            "match": match,
        })

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else
                           ["wyId", "name", "wyscout_fine", "transfermarkt_primary",
                            "transfermarkt_fine_mapped", "match"])
        w.writeheader()
        w.writerows(rows)

    total = len(rows)
    rate = matches / total if total else 0.0
    print(f"Cross-checked {total} players. Match rate: {matches}/{total} = {rate:.2%}")
    print(f"Wrote {OUT_CSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
