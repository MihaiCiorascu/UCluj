"""Recompute the per-fine-position grade anchors (``_GRADE_ANCHORS`` in
``services/grade_service.py``) from the committed drive_cache corpus.

Run this whenever ``FINE_POSITION_STAT_WEIGHTS`` or the per-90 normalisation in
``compute_performance_score`` changes, because the anchors are the empirical
[p10, p90] of the raw composite per position group and go stale otherwise. It
prints a ready-to-paste ``_GRADE_ANCHORS`` literal plus a distribution summary.
Uses the same minimum-minutes threshold the grade path applies, so the median
appearance keeps landing near a conventional 6.x rating.

    python backend/scripts/calibrate_grade_anchors.py
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

DRIVE = os.path.join(ROOT, "ml", "data", "drive_cache")
MIN_MINUTES = 20.0  # keep in sync with grade_service._MIN_GRADE_MINUTES
ORDER = ["GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"]


def _percentile(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (p / 100.0)
    lo = int(k)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = k - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def main() -> int:
    files = sorted(glob.glob(os.path.join(DRIVE, "*_players_stats.json")))
    raws: dict[str, list[float]] = defaultdict(list)
    n_players = 0
    for fp in files:
        try:
            data = json.load(open(fp, encoding="utf-8"))
        except Exception:
            continue
        for entry in data.get("players", []) or []:
            total = entry.get("total") or {}
            minutes = total.get("minutesOnField", 0) or 0
            if minutes < MIN_MINUTES:
                continue
            fine = derive_primary_fine_position([entry])
            coarse = FINE_GROUP_TO_COARSE.get(fine, "MID")
            raw = compute_performance_score(total, coarse, fine_group=fine)
            raws[fine].append(float(raw))
            n_players += 1

    print(f"files: {len(files)}  graded appearances (>= {MIN_MINUTES} min): {n_players}")
    anchors: dict[str, tuple[float, float]] = {}
    for g in ORDER:
        vals = sorted(raws.get(g, []))
        if len(vals) < 5:
            print(f"  {g}: only {len(vals)} samples (keep existing anchor)")
            continue
        p10 = round(_percentile(vals, 10), 2)
        p50 = round(_percentile(vals, 50), 2)
        p90 = round(_percentile(vals, 90), 2)
        anchors[g] = (p10, p90)
        print(f"  {g}: n={len(vals):4d}  p10={p10:8.2f}  p50={p50:8.2f}  "
              f"p90={p90:8.2f}  min={round(vals[0], 2):8.2f}  max={round(vals[-1], 2):8.2f}")

    print("\n_GRADE_ANCHORS: dict[str, tuple[float, float]] = {")
    for g in ORDER:
        if g in anchors:
            lo, hi = anchors[g]
            print(f'    "{g}": ({lo}, {hi}),')
    print("}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
