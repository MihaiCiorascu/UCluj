"""
Cross-check Wyscout-derived fine positions against the Sportradar snapshot.

This is the Sportradar analogue of
:mod:`backend.scripts.cross_check_positions`. It is the *licensed*
cross-check path: Sportradar is one of the project's contracted data
providers (see :mod:`backend.sportradar`), so reading the local
``sr_players`` projection of its competitor-profile feed is
contractually clean — unlike the Transfermarkt path which relies on a
ToS-restricted scrape.

Inputs
------

* ``ml/data/drive_cache/players (1).json`` — Wyscout profiles for the
  FC Universitatea Cluj squad. Used together with the per-match files
  in ``ml/data/drive_cache/*_players_stats.json`` to derive each
  player's primary fine-position label
  (see :func:`ml.feature_engineering.derive_primary_fine_position`).
* ``ml/data/sportradar_positions.json`` — produced by
  :mod:`backend.scripts.fetch_sportradar_positions`. Carries one
  ``{"id", "name", "position", "jersey_number", "nationality"}`` row
  per U Cluj player as Sportradar sees them.

Output
------

Writes ``ml/data/position_cross_check_sportradar.csv`` with one row per
*matched* player (Wyscout side), columns:

    wyId, wyscout_name, wyscout_fine, wyscout_coarse,
    sportradar_id, sportradar_name, sportradar_position,
    sportradar_coarse, match

The Wyscout side carries both the ten-group fine label and its
four-group coarse projection (``FINE_GROUP_TO_COARSE``); the Sportradar
side carries the raw position string and its mapping into the same
coarse taxonomy. The ``match`` column is computed at the **coarse**
level because Sportradar's competitor-profile feed emits only the four
broad position types (``goalkeeper`` / ``defender`` / ``midfielder`` /
``forward``); a fine-vs-coarse comparison would under-report the
agreement. Players who could not be name-matched between the two
sources are appended at the bottom of the CSV with empty Sportradar
fields and ``match=False``, so they are easy to inspect manually.

Skipped paths
-------------

If the Sportradar snapshot is empty or marked ``status: skipped`` (the
fetch script could not reach the database or the team had no rows yet),
the cross-check reports that and exits cleanly with rc=0 so it remains
usable in CI.
"""

from __future__ import annotations

import csv
import glob
import json
import os
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    FINE_GROUP_TO_COARSE,
    derive_primary_fine_position,
    get_team_squad_from_matches,
)
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402

DRIVE = ROOT / "ml" / "data" / "drive_cache"
SR_PATH = ROOT / "ml" / "data" / "sportradar_positions.json"
OUT_CSV = ROOT / "ml" / "data" / "position_cross_check_sportradar.csv"

TEAM_NAME_NEEDLE = "Universitatea Cluj"


# ── Sportradar -> coarse 4-group position mapping ────────────────────────────
#
# Sportradar's competitor-profile endpoint emits only four broad position
# strings (``goalkeeper``, ``defender``, ``midfielder``, ``forward``), so
# a fair comparison with the Wyscout-derived label must happen at the
# coarse four-group taxonomy (GK / DEF / MID / FWD). The Wyscout fine
# label is projected to coarse via
# :data:`ml.feature_engineering.FINE_GROUP_TO_COARSE`. The CSV preserves
# both the fine label and the coarse projection so the granularity of
# the comparison is visible.
#
# Some Sportradar endpoints occasionally emit finer-grained labels
# (e.g. ``"Centre-Back"`` from the historical sport_event_lineups feed);
# the mapping accepts those too and projects them onto the four-group
# axis. Unknown labels become ``"?"`` and are reported as non-matches.

SPORTRADAR_TO_COARSE: Dict[str, str] = {
    # Broad Sportradar `type` values.
    "goalkeeper":   "GK",
    "defender":     "DEF",
    "midfielder":   "MID",
    "forward":      "FWD",
    "attacker":     "FWD",
    # Finer-grained labels (project to coarse).
    "centre-back":          "DEF",
    "center-back":          "DEF",
    "centre back":          "DEF",
    "center back":          "DEF",
    "left back":            "DEF",
    "right back":           "DEF",
    "left-back":            "DEF",
    "right-back":           "DEF",
    "left wing-back":       "DEF",
    "right wing-back":      "DEF",
    "wing-back":            "DEF",
    "wing back":            "DEF",
    "defensive midfielder": "MID",
    "central midfielder":   "MID",
    "attacking midfielder": "MID",
    "left midfielder":      "MID",
    "right midfielder":     "MID",
    "left winger":          "FWD",
    "right winger":         "FWD",
    "winger":               "FWD",
    "second striker":       "FWD",
    "centre-forward":       "FWD",
    "centre forward":       "FWD",
    "center-forward":       "FWD",
    "center forward":       "FWD",
    "striker":              "FWD",
}

UCLUJ_TEAM_ID = 11571  # Wyscout team identifier; kept for backward compatibility.


# ── Name normalisation ────────────────────────────────────────────────────────

def _strip_diacritics(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", s)
        if not unicodedata.combining(c)
    )


def _normalise_last_name(name: str) -> str:
    """Return a lower-cased, diacritic-free last name suitable for matching.

    Handles three name formats produced by the two upstream sources:

    * **Wyscout ``shortName``** — ``"A. Chipciu"``, ``"O. El Sawy"``,
      ``"Miguel Silva"``. Format: ``"<initial>. <last name>"`` or
      occasionally ``"<first> <last>"`` for foreign players. The last
      name is everything after the first ``.`` if a dot is present;
      otherwise the whole-name tail after the first whitespace.
    * **Sportradar ``name``** — ``"Bic, Ovidiu"``, ``"El Sawy, Omar"``,
      ``"Van der Werff, Jasper"``. Format: ``"<last name>, <first
      name>"``. The last name is everything *before* the first ``,``.
    * **Edge case** — a single-token name falls through as itself.

    The result is lower-cased, diacritic-stripped, and internal
    whitespace is collapsed to a single space.
    """
    n = (name or "").strip()
    if not n:
        return ""

    if "," in n:
        # Sportradar-style "Bic, Ovidiu" -> "Bic"; "El Sawy, Omar" -> "El Sawy".
        tail = n.split(",", 1)[0].strip()
    elif "." in n:
        # Wyscout-style "A. Chipciu" -> "Chipciu"; "O. El Sawy" -> "El Sawy".
        tail = n.split(".", 1)[1].strip()
    else:
        # "Miguel Silva" -> "Silva"; "Ovidiu El Sawy" -> "El Sawy".
        parts = n.split(None, 1)
        tail = parts[1] if len(parts) > 1 else parts[0]

    tail = _strip_diacritics(tail).lower()
    tail = " ".join(tail.split())
    return tail


def _build_wyscout_fine(profiles: Dict[int, dict], squad_ids: set) -> Dict[int, Tuple[str, str]]:
    """Return ``{wyId: (shortName, fine_group)}`` for every player in the empirical squad."""
    files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    player_stats: Dict[int, List[dict]] = {}
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            data = json.load(f)
        for entry in data.get("players", []) or []:
            pid = entry.get("playerId")
            if pid is None or pid not in squad_ids:
                continue
            combined = dict(entry.get("total") or {})
            combined["positions"] = entry.get("positions") or []
            combined["matchId"] = entry.get("matchId")
            combined["total"] = dict(entry.get("total") or {})
            player_stats.setdefault(pid, []).append(combined)
    result: Dict[int, Tuple[str, str]] = {}
    for pid, stats in player_stats.items():
        prof = profiles.get(pid, {})
        short = prof.get("shortName") or prof.get("lastName") or ""
        result[pid] = (short, derive_primary_fine_position(stats))
    return result


def main() -> int:
    if not SR_PATH.exists():
        print(
            f"{SR_PATH} not found. Run fetch_sportradar_positions.py first."
        )
        return 1
    with SR_PATH.open("r", encoding="utf-8") as f:
        sr_blob = json.load(f)
    if sr_blob.get("status") != "ok" or not sr_blob.get("entries"):
        print(
            f"Sportradar snapshot status: {sr_blob.get('status', 'empty')}. "
            "Cross-check skipped."
        )
        return 0

    # Identify the empirical U Cluj squad using the same procedure that
    # the predictor uses — this ensures the two sides of the cross-check
    # reference the same set of players (see Iteration J empirical squad
    # detection in feature_engineering.get_team_squad_from_matches).
    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    squad_ids = get_team_squad_from_matches(match_files, TEAM_NAME_NEEDLE)
    wy_fine = _build_wyscout_fine(profiles, squad_ids)
    print(f"Wyscout squad with fine positions: {len(wy_fine)} players")

    # Build a Sportradar lookup keyed by normalised last name. Hyphenated
    # last names (e.g. ``"Trica-Balaci, Atanas Ioan"``) get an extra alias
    # for each hyphen-separated token so the Wyscout side, which may carry
    # only one half (e.g. ``"A. Trică"``), still matches.
    sr_by_lastname: Dict[str, dict] = {}
    sr_entries = sr_blob["entries"]
    for sr in sr_entries:
        key = _normalise_last_name(sr.get("name", ""))
        if not key:
            continue
        sr_by_lastname.setdefault(key, sr)
        if "-" in key:
            for piece in key.split("-"):
                piece = piece.strip()
                if piece:
                    sr_by_lastname.setdefault(piece, sr)
    print(f"Sportradar entries: {len(sr_entries)}; unique lookup keys: {len(sr_by_lastname)}")

    rows: List[dict] = []
    matches = 0
    unmatched_wy: List[Tuple[int, str, str, str]] = []
    for wy_id, (short, wyscout_fine) in wy_fine.items():
        wyscout_coarse = FINE_GROUP_TO_COARSE.get(wyscout_fine, "MID")
        key = _normalise_last_name(short)
        sr = sr_by_lastname.get(key)
        if sr is None:
            unmatched_wy.append((wy_id, short, wyscout_fine, wyscout_coarse))
            continue
        sr_pos = (sr.get("position") or "").strip()
        sr_coarse = SPORTRADAR_TO_COARSE.get(sr_pos.lower(), "?")
        match = (wyscout_coarse == sr_coarse)
        if match:
            matches += 1
        rows.append({
            "wyId": wy_id,
            "wyscout_name": short,
            "wyscout_fine": wyscout_fine,
            "wyscout_coarse": wyscout_coarse,
            "sportradar_id": sr.get("id", ""),
            "sportradar_name": sr.get("name", ""),
            "sportradar_position": sr_pos,
            "sportradar_coarse": sr_coarse,
            "match": match,
        })

    # Append unmatched Wyscout players for inspection.
    for wy_id, short, wyscout_fine, wyscout_coarse in unmatched_wy:
        rows.append({
            "wyId": wy_id,
            "wyscout_name": short,
            "wyscout_fine": wyscout_fine,
            "wyscout_coarse": wyscout_coarse,
            "sportradar_id": "",
            "sportradar_name": "",
            "sportradar_position": "",
            "sportradar_coarse": "",
            "match": False,
        })

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else [
            "wyId", "wyscout_name", "wyscout_fine", "wyscout_coarse",
            "sportradar_id", "sportradar_name", "sportradar_position",
            "sportradar_coarse", "match",
        ])
        w.writeheader()
        w.writerows(rows)

    matched_total = len(rows) - len(unmatched_wy)
    rate = matches / matched_total if matched_total else 0.0
    print(
        f"Cross-checked {matched_total} name-matched players "
        f"(plus {len(unmatched_wy)} unmatched on the Wyscout side). "
        f"Coarse-position match rate: {matches}/{matched_total} = {rate:.2%}"
    )
    print(f"Wrote {OUT_CSV.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
