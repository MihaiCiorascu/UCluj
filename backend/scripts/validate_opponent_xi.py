"""Validate that the recommended XI now responds to the opponent (read-only).

Predicts U Cluj's XI against opponents from different style archetypes under a
FIXED formation (so any change is a genuine player swap, not a shape change) and
reports how the selection shifts. Also confirms the opponent's predicted XI is
returned.

    python backend/scripts/validate_opponent_xi.py
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from services.xi_service import XiService  # noqa: E402

# One opponent per archetype (from the retrain's team->cluster map).
OPPONENTS = {
    "FCSB": "cluster0 (elite/efficient)",
    "Farul Constanţa": "cluster1 (possession/solid)",
    "Dinamo Bucureşti": "cluster2 (high-possession/leaky)",
    "Rapid Bucureşti": "cluster3 (balanced)",
}
FORMATION = "4-2-3-1"


def _names(records):
    return [str(p.get("name") or p.get("shortName") or p.get("playerId")) for p in records]


def main() -> int:
    svc = XiService(model_path="ml/xi_model.pkl", data_dir="ml/data/drive_cache")
    sets = {}
    for opp, label in OPPONENTS.items():
        out = svc.match_preview(opponent_name=opp, formation=FORMATION,
                                home_team_short="U Cluj")
        xi = _names(out.get("starting_xi") or [])
        sets[opp] = set(xi)
        opp_xi = out.get("opponent_xi") or []
        print(f"\nvs {opp}  [{label}]  formation={out.get('formation')}  opponent_xi={len(opp_xi)}")
        for p in (out.get("starting_xi") or []):
            print(f"   {str(p.get('officialPosition') or p.get('position') or ''):4} "
                  f"{p.get('name') or p.get('shortName')}")

    print("\n=== selection shift across archetypes (fixed formation) ===")
    base_opp = next(iter(sets))
    base = sets[base_opp]
    any_shift = False
    for opp, xi in sets.items():
        shared = len(xi & base)
        changed = sorted(xi ^ base)
        if opp != base_opp and changed:
            any_shift = True
        print(f"  vs {opp:18}: {shared}/11 shared with vs {base_opp}; "
              f"changed={[c for c in changed]}")
    print("\nOpponent-responsive selection:", "YES" if any_shift else "NO (XI identical across opponents)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
