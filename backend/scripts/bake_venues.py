"""Bake the official venue (stadium) into
``backend/ml/data/superliga_2025_26_fixtures.json`` from the Sportradar schedule,
so the dashboard and the match sheet can show the stadium fully offline.

The baked fixtures carried ``"venue": null``; the schedule feed
(``seasons/.../schedules.json``) carries ``sport_event.venue.name`` per event.
Joined by the canonical (home, away, date) key, the same join the round restamp
uses. Runtime never calls Sportradar; only the committed JSON ships.

    SPORTRADAR_API_KEY=... python backend/scripts/bake_venues.py
"""
from __future__ import annotations

import asyncio
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)

from clients.sportradar_client import SportradarClient  # noqa: E402
from sportradar.team_registry import team_by_alias  # noqa: E402

FIXTURES = os.path.join(ROOT, "ml", "data", "superliga_2025_26_fixtures.json")
SEASON_ID = "sr:season:131507"


def _canon(name: str):
    t = team_by_alias(name or "")
    return t.short if t else None


async def _fetch_schedule() -> list[dict]:
    c = SportradarClient()
    data = await c.season_schedules(SEASON_ID)
    rows: list[dict] = []
    for r in (data or {}).get("schedules", []):
        se = r.get("sport_event", {}) or {}
        comps = se.get("competitors", []) or []
        h = next((x for x in comps if x.get("qualifier") == "home"), {})
        a = next((x for x in comps if x.get("qualifier") == "away"), {})
        date = (se.get("start_time") or se.get("scheduled") or "")[:10]
        venue = ((se.get("venue") or {}).get("name") or "").strip()
        rows.append({
            "home": _canon(h.get("name", "")),
            "away": _canon(a.get("name", "")),
            "date": date,
            "venue": venue,
        })
    return rows


def main() -> int:
    sched = asyncio.run(_fetch_schedule())
    print("SR schedule events:", len(sched))
    if not sched:
        print("No schedule returned (missing key or quota throttle). Aborting.")
        return 1

    by_key: dict = {}
    for f in sched:
        if f["home"] and f["away"] and f["date"] and f["venue"]:
            by_key[(f["home"], f["away"], f["date"])] = f["venue"]
    print("events carrying a venue:", len(by_key))

    doc = json.load(open(FIXTURES, encoding="utf-8"))
    fixtures = doc["fixtures"]
    filled = 0
    missing: list = []
    for fx in fixtures:
        key = (_canon(fx["home_team"]), _canon(fx["away_team"]), fx["date"])
        v = by_key.get(key)
        if v:
            fx["venue"] = v
            filled += 1
        else:
            missing.append(f'{fx["date"]} {fx["home_team"]} vs {fx["away_team"]}')

    print(f"baked fixtures: {len(fixtures)}  venues filled: {filled}  missing: {len(missing)}")
    for u in missing[:25]:
        print("  ", u)

    with open(FIXTURES, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print("wrote", FIXTURES)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
