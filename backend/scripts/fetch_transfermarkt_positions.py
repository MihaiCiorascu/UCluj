"""
One-off Transfermarkt cross-check for the FC Universitatea Cluj squad.

This script is intentionally a *manual tool*, not part of any deployed
pipeline. It fetches the primary and secondary positions of each U Cluj
player from Transfermarkt to provide an external verification of the
fine-position labels derived from the Wyscout data
(:func:`ml.feature_engineering.derive_primary_fine_position`).

The script is scoped strictly to the FC Universitatea Cluj squad (≈28
players from the Wyscout profiles file), making it a one-off snapshot
rather than a recurring scrape. The data is written to
``backend/ml/data/transfermarkt_positions.json``.

Usage
-----

    python -m pip install transfermarkt-wrapper        # see Note below
    python backend/scripts/fetch_transfermarkt_positions.py

Note on dependencies
--------------------

Transfermarkt does not publish an official API. The Python wrapper used
here (``transfermarkt-wrapper`` on PyPI, or the equivalent
``felipeall/transfermarkt-api`` FastAPI service) scrapes Transfermarkt
pages directly, which Transfermarkt's Terms of Use restrict. The author
runs this script as a one-off verification step, not as a recurring
data-collection pipeline. Users who reproduce the work should consult
Transfermarkt's terms and their local jurisdiction before installing
the wrapper.

The output JSON is checked into the repository so that re-running the
script is not required to verify the cross-check.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # backend/
DRIVE_CACHE = ROOT / "ml" / "data" / "drive_cache"
PROFILES_FILE = DRIVE_CACHE / "players (1).json"
OUT_PATH = ROOT / "ml" / "data" / "transfermarkt_positions.json"

UCLUJ_TEAM_ID = 11571


def _try_import_wrapper():
    """Return the transfermarkt wrapper module or None if unavailable."""
    try:
        import transfermarkt_wrapper as tw  # type: ignore

        return tw
    except Exception:
        return None


def _load_ucluj_squad() -> list[dict]:
    """Return the list of U Cluj player profiles from the Wyscout export."""
    with PROFILES_FILE.open("r", encoding="utf-8") as f:
        raw = json.load(f)
    if isinstance(raw, list):
        profiles = raw
    elif isinstance(raw, dict):
        profiles = list((raw.get("players") or raw.values()))
    else:
        return []
    return [p for p in profiles if isinstance(p, dict) and p.get("currentTeamId") == UCLUJ_TEAM_ID]


def main() -> int:
    wrapper = _try_import_wrapper()
    if wrapper is None:
        print(
            "transfermarkt-wrapper is not installed. Install it via:\n"
            "    python -m pip install transfermarkt-wrapper\n"
            "and rerun this script. Skipping cross-check.",
            file=sys.stderr,
        )
        # Write an empty stub so the cross-check script can still report cleanly.
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        with OUT_PATH.open("w", encoding="utf-8") as f:
            json.dump({"status": "skipped — wrapper not installed", "entries": {}}, f, indent=2)
        return 1

    squad = _load_ucluj_squad()
    print(f"FC Universitatea Cluj squad in Wyscout profiles: {len(squad)} players")

    entries: dict[str, dict] = {}
    for profile in squad:
        wy_id = profile.get("wyId")
        name = profile.get("shortName") or profile.get("lastName") or ""
        if not wy_id or not name:
            continue
        try:
            results = wrapper.search_player(name)  # type: ignore[attr-defined]
        except Exception as exc:
            print(f"  [{wy_id}] {name}: search error: {exc}", file=sys.stderr)
            continue
        if not results:
            print(f"  [{wy_id}] {name}: no match")
            continue
        # Naive resolution: first result. The user can refine by checking
        # nationality / DOB against the Wyscout profile if needed.
        first = results[0]
        try:
            detail = wrapper.player_profile(first.get("id"))  # type: ignore[attr-defined]
        except Exception as exc:
            print(f"  [{wy_id}] {name}: profile fetch error: {exc}", file=sys.stderr)
            continue
        entries[str(wy_id)] = {
            "name": name,
            "transfermarkt_id": first.get("id"),
            "primary_position": detail.get("main_position") or detail.get("position"),
            "other_positions": detail.get("other_positions") or [],
        }
        print(f"  [{wy_id}] {name} -> TM id {first.get('id')} / {detail.get('main_position')}")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump({"status": "ok", "entries": entries}, f, indent=2, ensure_ascii=False)
    print(f"\nWrote {len(entries)} entries to {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
