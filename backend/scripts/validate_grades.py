"""Validation for the recalibrated grade system. Read-only. Prints:
  1. the grade distribution per fine position (median should sit near 6.x, spread
     across the band, few values pinned at the 1.0 / 10.0 clamps),
  2. the busiest goalkeepers by saves with their new grade (should be high) vs
     keepers who were barely tested (should be modest), confirming grades now
     reward shot-stopping rather than the team clean sheet.

    python backend/scripts/validate_grades.py
"""
from __future__ import annotations

import glob
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)

from ml.feature_engineering import (  # noqa: E402
    FINE_GROUP_TO_COARSE,
    compute_performance_score,
    derive_primary_fine_position,
)
from services.grade_service import (  # noqa: E402
    _MIN_GRADE_MINUTES,
    _scale_to_grade,
)

DRIVE = os.path.join(ROOT, "ml", "data", "drive_cache")
ORDER = ["GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"]


def _pct(vals, p):
    if not vals:
        return 0.0
    k = (len(vals) - 1) * (p / 100.0)
    lo = int(k); hi = min(lo + 1, len(vals) - 1)
    return vals[lo] * (1 - (k - lo)) + vals[hi] * (k - lo)


def main() -> int:
    grades = defaultdict(list)
    gk_rows = []  # (saves, xgSave, conceded, grade)
    clamp_lo = clamp_hi = total = 0
    for fp in sorted(glob.glob(os.path.join(DRIVE, "*_players_stats.json"))):
        try:
            data = json.load(open(fp, encoding="utf-8"))
        except Exception:
            continue
        for entry in data.get("players", []) or []:
            t = entry.get("total") or {}
            mins = t.get("minutesOnField", 0) or 0
            if mins < _MIN_GRADE_MINUTES:
                continue
            fine = derive_primary_fine_position([entry])
            coarse = FINE_GROUP_TO_COARSE.get(fine, "MID")
            raw = compute_performance_score(t, coarse, fine_group=fine)
            g = _scale_to_grade(float(raw), fine)
            grades[fine].append(g)
            total += 1
            if g <= 1.0:
                clamp_lo += 1
            if g >= 10.0:
                clamp_hi += 1
            if fine == "GK":
                gk_rows.append((t.get("gkSaves", 0) or 0, t.get("xgSave", 0) or 0,
                                t.get("gkConcededGoals", 0) or 0, g))

    print(f"graded appearances: {total}  clamped low(<=1): {clamp_lo}  "
          f"clamped high(>=10): {clamp_hi}")
    print("grade distribution per position (p10 / median / p90):")
    for grp in ORDER:
        v = sorted(grades.get(grp, []))
        if not v:
            continue
        print(f"  {grp}: n={len(v):4d}  p10={_pct(v,10):.1f}  med={_pct(v,50):.1f}  "
              f"p90={_pct(v,90):.1f}  min={v[0]:.1f}  max={v[-1]:.1f}")

    gk_rows.sort(key=lambda r: r[0], reverse=True)
    print("\nbusiest keepers (most saves) -> grade:")
    for saves, xg, conc, g in gk_rows[:8]:
        print(f"  saves={saves:2d}  xgSave={xg:4.2f}  conceded={conc:2d}  grade={g}")
    print("least-tested keepers (fewest saves) -> grade:")
    for saves, xg, conc, g in sorted(gk_rows, key=lambda r: r[0])[:8]:
        print(f"  saves={saves:2d}  xgSave={xg:4.2f}  conceded={conc:2d}  grade={g}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
