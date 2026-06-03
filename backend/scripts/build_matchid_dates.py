"""One-off builder for ``backend/ml/data/matchid_to_date.json``.

The Wyscout drive_cache match files carry no date, and their integer matchIds do
not map to ``All_Data.csv`` (which ends in the 2024-25 season, before the
drive_cache's 2025-26 season). The only dated source that covers the drive_cache
season is the Sportradar 25/26 schedule, where each fixture has a ``start_time``.

This script fetches that schedule and joins it to the drive_cache matches by the
canonical (home, away) ordered pair, with a chronological tiebreak for the two or
three meetings of the same pair across a season, and writes
``{matchId: 'YYYY-MM-DD'}``. Scores are used as a sanity check, not the join key,
so identical-score repeats are still dated correctly.

Re-run whenever the drive_cache is refreshed:
    SPORTRADAR_API_KEY=... python backend/scripts/build_matchid_dates.py
Runtime never calls Sportradar; it reads the committed JSON via ``ml.match_dates``.
"""
from __future__ import annotations

import asyncio
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)

from clients.sportradar_client import SportradarClient  # noqa: E402
from sportradar.team_registry import team_by_alias  # noqa: E402

DRIVE = os.path.join(ROOT, "ml", "data", "drive_cache")
OUT = os.path.join(ROOT, "ml", "data", "matchid_to_date.json")
SEASON_ID = "sr:season:131507"  # Superliga 25/26 = the drive_cache season


def _canon(name: str):
    t = team_by_alias(name or "")
    return t.short if t else None


def _parse_fn(path: str):
    base = os.path.basename(path).replace("_players_stats.json", "")
    base = re.sub(r"_\d+$", "", base)  # strip trailing _<digits> dedupe suffix
    m = re.match(r"^(.*) - (.*), (\d+)-(\d+)$", base)
    if not m:
        return None
    return (m.group(1).strip(), m.group(2).strip(), int(m.group(3)), int(m.group(4)))


def _file_meta(path: str):
    """Return (matchId, roundId, seasonId) from the first player entry."""
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception:
        return None
    for e in d.get("players", []) or []:
        mid = e.get("matchId")
        if mid is not None:
            return (int(mid), e.get("roundId", 0) or 0, e.get("seasonId", 0) or 0)
    return None


async def _fetch_sr():
    c = SportradarClient()
    data = await c.season_schedules(SEASON_ID)
    rows = []
    for r in (data or {}).get("schedules", []):
        se = r.get("sport_event", {}) or {}
        st = r.get("sport_event_status", {}) or {}
        comps = se.get("competitors", []) or []
        h = next((x for x in comps if x.get("qualifier") == "home"), {})
        a = next((x for x in comps if x.get("qualifier") == "away"), {})
        date = (se.get("start_time") or se.get("scheduled") or "")[:10]
        rows.append({
            "home": _canon(h.get("name", "")),
            "away": _canon(a.get("name", "")),
            "hs": st.get("home_score"),
            "as": st.get("away_score"),
            "date": date,
        })
    return rows


def main() -> int:
    sr = asyncio.run(_fetch_sr())
    print("SR fixtures:", len(sr))
    sr_by_pair = defaultdict(list)
    for f in sr:
        if f["home"] and f["away"] and f["date"]:
            sr_by_pair[(f["home"], f["away"])].append(f)
    for k in sr_by_pair:
        sr_by_pair[k].sort(key=lambda x: x["date"])

    files = sorted(glob.glob(os.path.join(DRIVE, "*_players_stats.json")))
    drive = []
    for fp in files:
        p = _parse_fn(fp)
        meta = _file_meta(fp)
        if not p or meta is None:
            continue
        mid, rid, sid = meta
        drive.append({
            "mid": mid, "home": _canon(p[0]), "away": _canon(p[1]),
            "hs": p[2], "as": p[3], "rid": rid, "sid": sid,
            "fn": os.path.basename(fp),
        })
    drive_by_pair = defaultdict(list)
    for d in drive:
        if d["home"] and d["away"]:
            drive_by_pair[(d["home"], d["away"])].append(d)
    for k in drive_by_pair:
        drive_by_pair[k].sort(key=lambda x: (x["sid"], x["rid"], x["mid"]))

    mapping = {}
    score_mismatch = 0
    unmatched = []
    for pair, dmatches in drive_by_pair.items():
        slist = sr_by_pair.get(pair, [])
        for i, dm in enumerate(dmatches):
            if i < len(slist):
                sf = slist[i]
                mapping[str(dm["mid"])] = sf["date"]
                if sf["hs"] is not None and (sf["hs"], sf["as"]) != (dm["hs"], dm["as"]):
                    score_mismatch += 1
            else:
                unmatched.append(dm["fn"])
    unresolved_team = [d["fn"] for d in drive if not d["home"] or not d["away"]]

    print(f"drive matches: {len(drive)}  mapped: {len(mapping)}  "
          f"unmatched(pair/index): {len(unmatched)}  unresolved-team: {len(unresolved_team)}")
    print(f"score-order sanity mismatches: {score_mismatch}")
    if unmatched[:8]:
        print("unmatched sample:", unmatched[:8])
    if unresolved_team[:8]:
        print("unresolved-team sample:", unresolved_team[:8])

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(mapping, f, indent=0, sort_keys=True)
    print("wrote", OUT, "with", len(mapping), "entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
