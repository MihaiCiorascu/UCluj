"""
League-wide Wyscout-vs-Sportradar position cross-check (Iteration L.2).

Iterates over every team in :data:`backend.sportradar.team_registry.SUPERLIGA_TEAMS`,
fetches Sportradar players from the local DB (populated by
``sync_sportradar_squad.py``), pairs them to the Wyscout-derived
fine-position labels for each team's squad, and reports both per-team
and league-aggregate coarse-position match rates.

Outputs:

* ``backend/ml/data/sportradar_positions_league.json`` — one entry per
  Sportradar player across the league (~640 entries), grouped by team.
* ``backend/ml/data/position_cross_check_league.csv`` — one row per
  name-matched Wyscout player across the league, with both fine and
  coarse labels from both sources.
* stdout — per-team match-rate table plus a league aggregate.

Replaces (and supersedes) the single-team
``cross_check_positions_via_sportradar.py`` script used in Iteration K
for U Cluj only.
"""

from __future__ import annotations

import csv
import glob
import json
import sqlite3
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    FINE_GROUP_TO_COARSE,
    derive_primary_fine_position,
    get_team_squad_from_matches,
)
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402
from sportradar.team_registry import (  # type: ignore  # noqa: E402
    SUPERLIGA_TEAMS,
    TeamRef,
    files_for_team,
    normalise,
)

DRIVE = ROOT / "ml" / "data" / "drive_cache"
DB_PATH = ROOT / "umbraro.db"
OUT_JSON = ROOT / "ml" / "data" / "sportradar_positions_league.json"
OUT_CSV = ROOT / "ml" / "data" / "position_cross_check_league.csv"


# ── Sportradar → coarse 4-group mapping ──────────────────────────────────────
# Sportradar's competitor-profile feed emits only four broad position
# strings (``goalkeeper``, ``defender``, ``midfielder``, ``forward``);
# rarely it adds a granular label such as ``"Centre-Back"``. The fair
# comparison is at the four-group coarse taxonomy (GK / DEF / MID / FWD).

SPORTRADAR_TO_COARSE: Dict[str, str] = {
    "goalkeeper": "GK",
    "defender": "DEF",
    "midfielder": "MID",
    "forward": "FWD",
    "attacker": "FWD",
    "centre-back": "DEF", "center-back": "DEF",
    "centre back": "DEF", "center back": "DEF",
    "left back": "DEF", "right back": "DEF",
    "left-back": "DEF", "right-back": "DEF",
    "left wing-back": "DEF", "right wing-back": "DEF",
    "wing-back": "DEF", "wing back": "DEF",
    "defensive midfielder": "MID",
    "central midfielder": "MID",
    "attacking midfielder": "MID",
    "left midfielder": "MID", "right midfielder": "MID",
    "left winger": "FWD", "right winger": "FWD",
    "winger": "FWD",
    "second striker": "FWD",
    "centre-forward": "FWD", "centre forward": "FWD",
    "center-forward": "FWD", "center forward": "FWD",
    "striker": "FWD",
}


def _strip_diacritics(s: str) -> str:
    nfd = unicodedata.normalize("NFD", s or "")
    out = "".join(c for c in nfd if not unicodedata.combining(c))
    replacements = {"ș": "s", "ț": "t", "ş": "s", "ţ": "t",
                    "Ș": "S", "Ț": "T", "Ş": "S", "Ţ": "T"}
    return "".join(replacements.get(c, c) for c in out)


def _normalise_last_name(name: str) -> str:
    """Diacritic-stripped, lower-cased last name for cross-source matching.

    Handles three name formats:
      * Sportradar ``"LastName, FirstName"`` -> last name before the comma.
      * Wyscout ``"<initial>. <last name>"`` -> the part after the dot.
      * Plain ``"<first> <last>"`` -> everything after the first space.
    """
    n = (name or "").strip()
    if not n:
        return ""
    if "," in n:
        tail = n.split(",", 1)[0].strip()
    elif "." in n:
        tail = n.split(".", 1)[1].strip()
    else:
        parts = n.split(None, 1)
        tail = parts[1] if len(parts) > 1 else parts[0]
    return " ".join(_strip_diacritics(tail).lower().split())


def _wyscout_squad_fine(
    team: TeamRef,
    all_match_files: List[str],
    profiles: Dict[int, dict],
) -> Dict[int, Tuple[str, str]]:
    """Return ``{wyId: (shortName, fine_position)}`` for ``team``'s squad."""
    team_files = files_for_team(all_match_files, team)
    if not team_files:
        return {}
    needle = team.wy_substr  # match-frequency-based squad detection.
    squad_ids = get_team_squad_from_matches(all_match_files, needle)
    if not squad_ids:
        return {}
    # Aggregate per-player match blocks for fine-position derivation.
    player_match_blocks: Dict[int, List[dict]] = {}
    for fp in team_files:
        try:
            with open(fp, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        for entry in data.get("players", []) or []:
            pid = entry.get("playerId")
            if pid not in squad_ids:
                continue
            blk = {
                "matchId": entry.get("matchId"),
                "positions": entry.get("positions", []) or [],
                "total": dict(entry.get("total", {}) or {}),
            }
            player_match_blocks.setdefault(int(pid), []).append(blk)

    out: Dict[int, Tuple[str, str]] = {}
    for pid, blocks in player_match_blocks.items():
        fine = derive_primary_fine_position(blocks)
        prof = profiles.get(pid, {}) or {}
        short = prof.get("shortName") or prof.get("lastName") or f"player_{pid}"
        out[pid] = (short, fine)
    return out


def _sportradar_team_players(conn: sqlite3.Connection, team: TeamRef) -> List[dict]:
    rows = conn.execute(
        "SELECT id, name, position, jersey_number, nationality "
        "FROM sr_players WHERE team_id = ? ORDER BY name",
        (team.sr_id,),
    ).fetchall()
    return [
        {
            "team_short": team.short,
            "team_sr_id": team.sr_id,
            "id": r[0],
            "name": r[1],
            "position": r[2],
            "jersey_number": r[3],
            "nationality": r[4],
        }
        for r in rows
    ]


def main() -> int:
    if not DB_PATH.exists():
        print(f"DB missing: {DB_PATH}. Run sync_sportradar_squad.py first.", file=sys.stderr)
        return 1

    print("Loading drive_cache and player profiles ...")
    all_match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    profile_path = DRIVE / "players (1).json"
    profiles = load_player_profiles(str(profile_path))
    print(f"  {len(all_match_files)} match files, {len(profiles)} player profiles.")

    conn = sqlite3.connect(str(DB_PATH))

    league_entries: Dict[str, dict] = {}
    league_rows: List[dict] = []
    league_total = 0
    league_matches = 0
    per_team_stats: List[dict] = []

    print()
    print(f"{'Team':24s} {'wy_squad':9s} {'sr_squad':9s} {'matched':9s} {'pos_ok':7s} {'rate':7s}")
    print("-" * 75)

    for team in SUPERLIGA_TEAMS:
        wy_fine = _wyscout_squad_fine(team, all_match_files, profiles)
        sr_players = _sportradar_team_players(conn, team)

        # Build Sportradar lookup (last-name -> entry; hyphen aliases too).
        sr_by_lastname: Dict[str, dict] = {}
        for sr in sr_players:
            key = _normalise_last_name(sr.get("name", ""))
            if not key:
                continue
            sr_by_lastname.setdefault(key, sr)
            if "-" in key:
                for piece in key.split("-"):
                    piece = piece.strip()
                    if piece:
                        sr_by_lastname.setdefault(piece, sr)

        n_matched = 0
        n_pos_ok = 0
        team_rows: List[dict] = []
        for wy_id, (short, fine) in wy_fine.items():
            coarse = FINE_GROUP_TO_COARSE.get(fine, "MID")
            key = _normalise_last_name(short)
            sr = sr_by_lastname.get(key)
            if sr is None:
                team_rows.append({
                    "team": team.short,
                    "wyId": wy_id, "wyscout_name": short,
                    "wyscout_fine": fine, "wyscout_coarse": coarse,
                    "sportradar_id": "", "sportradar_name": "",
                    "sportradar_position": "", "sportradar_coarse": "",
                    "match": False,
                })
                continue
            n_matched += 1
            sr_pos = (sr.get("position") or "").strip()
            sr_coarse = SPORTRADAR_TO_COARSE.get(sr_pos.lower(), "?")
            is_match = (coarse == sr_coarse)
            if is_match:
                n_pos_ok += 1
            team_rows.append({
                "team": team.short,
                "wyId": wy_id, "wyscout_name": short,
                "wyscout_fine": fine, "wyscout_coarse": coarse,
                "sportradar_id": sr.get("id", ""),
                "sportradar_name": sr.get("name", ""),
                "sportradar_position": sr_pos,
                "sportradar_coarse": sr_coarse,
                "match": is_match,
            })

        league_rows.extend(team_rows)
        league_total += n_matched
        league_matches += n_pos_ok
        rate = (n_pos_ok / n_matched) if n_matched else 0.0
        per_team_stats.append({
            "team": team.short,
            "wy_squad_size": len(wy_fine),
            "sr_squad_size": len(sr_players),
            "matched": n_matched,
            "pos_match": n_pos_ok,
            "match_rate": rate,
        })
        print(f"{team.short:24s} {len(wy_fine):9d} {len(sr_players):9d} "
              f"{n_matched:9d} {n_pos_ok:7d} {rate:6.2%}")

        league_entries[team.sr_id] = {
            "team_short": team.short,
            "team_name_sr": team.aliases[0] if team.aliases else team.short,
            "sr_id": team.sr_id,
            "entries": sr_players,
        }

    conn.close()

    league_rate = (league_matches / league_total) if league_total else 0.0
    print("-" * 75)
    print(f"{'LEAGUE TOTAL':24s} {'-':9s} {'-':9s} "
          f"{league_total:9d} {league_matches:7d} {league_rate:6.2%}")
    print()

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with OUT_JSON.open("w", encoding="utf-8") as f:
        json.dump({
            "status": "ok",
            "n_teams": len(SUPERLIGA_TEAMS),
            "teams": league_entries,
            "per_team_stats": per_team_stats,
            "league_match_rate": league_rate,
            "league_matched_players": league_total,
            "league_position_matches": league_matches,
        }, f, indent=2, ensure_ascii=False)
    print(f"Wrote {OUT_JSON.relative_to(ROOT)}")

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["team", "wyId", "wyscout_name", "wyscout_fine", "wyscout_coarse",
                  "sportradar_id", "sportradar_name", "sportradar_position",
                  "sportradar_coarse", "match"]
    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(league_rows)
    print(f"Wrote {OUT_CSV.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
