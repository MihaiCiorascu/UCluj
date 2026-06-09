"""Validate the multi-team subject parameterisation end to end (read-only).

Loads the real model + data and runs the week-fixtures compute for several clubs
as the analytical subject, confirming that:
  - the subject's own fixtures carry the rich analysis (P(subject win), drivers,
    prescription) and a non-null subject_is_home,
  - non-subject fixtures carry neutral 3-way odds and subject_is_home is None,
  - U Cluj still works (regression).

    python backend/scripts/validate_multiteam.py
"""
from __future__ import annotations

import asyncio
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from app.config import settings  # noqa: E402
from data.loader import load_all_data, load_stadium_map, load_model_bundle  # noqa: E402
from api.v1.endpoints.week import _compute_week  # noqa: E402
from sportradar.team_registry import team_by_alias  # noqa: E402


async def main() -> int:
    df = load_all_data(settings.resolved_data_path)
    stadium_map = load_stadium_map(settings.resolved_stadium_map_path)
    bundle = load_model_bundle(settings.resolved_model_path)
    print(f"demo_mode={settings.demo_mode}")

    for club in ["U Cluj", "FCSB", "Rapid Bucureşti"]:
        subj = team_by_alias(club)
        found = None
        # Scan a few rounds to land on one where this club actually plays.
        for off in [0, 1, -1, 2, -2]:
            rows = await _compute_week(df, stadium_map, bundle, off, subj)
            subj_rows = [r for r in rows if r.get("subject_is_home") is not None]
            if subj_rows:
                found = (off, rows, subj_rows)
                break
        print(f"\n=== subject={club!r} -> resolved {subj.short if subj else None} ===")
        if not found:
            print("  no fixture found for this club in offsets -2..2")
            continue
        off, rows, subj_rows = found
        print(f"  round offset {off}: {len(rows)} fixtures, {len(subj_rows)} involve the subject")
        for r in subj_rows:
            print(f"    SUBJ {r['home_team']} vs {r['away_team']} | "
                  f"subj_is_home={r['subject_is_home']} | "
                  f"P(subj win)={r.get('home_win_probability')} | "
                  f"drivers={len(r.get('key_drivers') or [])} | "
                  f"presc={'yes' if r.get('prescription') else 'no'}")
        other = [r for r in rows if r.get("subject_is_home") is None]
        if other:
            o = other[0]
            assert o.get("home_win_probability") is None, "non-subject must have null headline"
            print(f"    OTHER {o['home_team']} vs {o['away_team']} | "
                  f"3way H={o.get('home_team_win_prob')} D={o.get('draw_prob')} "
                  f"A={o.get('away_team_win_prob')} | subj_is_home={o.get('subject_is_home')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
