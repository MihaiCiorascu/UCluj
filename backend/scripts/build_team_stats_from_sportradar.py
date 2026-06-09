"""Build ``backend/ml/data/matchid_to_team_stats.json`` from the Sportradar
season summaries, so concluded-match team stats can be served OFFLINE as the
official provider totals instead of the per-player Wyscout approximation.

The season summaries feed (``seasons/.../summaries.json``) carries, per event, a
``statistics.totals.competitors[]`` block with the official team totals (ball
possession, shots, corners, fouls, cards, offsides, and so on). This fetches it
(paginated, a couple of calls for the whole season), joins each event to a baked
Wyscout match by the canonical (home, away, date) key, and writes
``{matchId: {home_stats, away_stats}}`` in the same field shape that
``build_offline_match_details`` emits.

Runtime never calls Sportradar; only the committed JSON ships.

    SPORTRADAR_API_KEY=... python backend/scripts/build_team_stats_from_sportradar.py
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
OUT = os.path.join(ROOT, "ml", "data", "matchid_to_team_stats.json")
SEASON_ID = "sr:season:131507"


def _canon(name: str):
    t = team_by_alias(name or "")
    return t.short if t else None


def _map_stats(sr: dict | None) -> dict | None:
    """Map a Sportradar competitor statistics block to the offline dict shape."""
    if not sr:
        return None

    def _i(k):
        v = sr.get(k)
        return int(v) if v is not None else None

    red = (sr.get("red_cards") or 0) + (sr.get("yellow_red_cards") or 0)
    bp = sr.get("ball_possession")
    return {
        "ball_possession": float(bp) if bp is not None else None,
        "shots_on_target": _i("shots_on_target"),
        "shots_off_target": _i("shots_off_target"),
        "shots_total": _i("shots_total"),
        "corner_kicks": _i("corner_kicks"),
        "yellow_cards": _i("yellow_cards"),
        "red_cards": int(red),
        "offsides": _i("offsides"),
        "fouls": _i("fouls"),
        "goalkeeper_saves": _i("shots_saved"),
        # Not carried by the summaries feed; left null (also not displayed).
        "pass_accuracy": None,
        "duel_win_rate": None,
    }


async def _fetch_summaries() -> list[dict]:
    # The trial tier caps each page at 100, so page by 100 until a short page.
    c = SportradarClient()
    out: list[dict] = []
    offset = 0
    while offset < 1000:
        d = await c.season_summaries(SEASON_ID, offset=offset, limit=100)
        chunk = (d or {}).get("summaries", []) or []
        print(f"  page offset={offset}: {len(chunk)} summaries")
        out.extend(chunk)
        if len(chunk) < 100:
            break
        offset += 100
    return out


def main() -> int:
    summaries = asyncio.run(_fetch_summaries())
    print("SR summaries:", len(summaries))
    if not summaries:
        print("No summaries returned (missing key or quota throttle). Aborting.")
        return 1

    sr_by_key: dict = {}
    with_stats = 0
    for s in summaries:
        se = s.get("sport_event", {}) or {}
        comps = se.get("competitors", []) or []
        h = next((x for x in comps if x.get("qualifier") == "home"), {})
        a = next((x for x in comps if x.get("qualifier") == "away"), {})
        date = (se.get("start_time") or se.get("scheduled") or "")[:10]
        ch, ca = _canon(h.get("name", "")), _canon(a.get("name", ""))
        stat_comps = (((s.get("statistics", {}) or {}).get("totals", {}) or {})
                      .get("competitors", []) or [])
        sh = next((x.get("statistics") for x in stat_comps if x.get("qualifier") == "home"), None)
        sa = next((x.get("statistics") for x in stat_comps if x.get("qualifier") == "away"), None)
        if sh or sa:
            with_stats += 1
        if ch and ca and date and (sh or sa):
            sr_by_key[(ch, ca, date)] = (_map_stats(sh), _map_stats(sa))
    print("summaries carrying stats:", with_stats, "| keyed:", len(sr_by_key))

    doc = json.load(open(FIXTURES, encoding="utf-8"))
    fixtures = doc["fixtures"]
    mapping: dict = {}
    matched = 0
    unmatched_with_score: list = []
    for f in fixtures:
        key = (_canon(f["home_team"]), _canon(f["away_team"]), f["date"])
        hit = sr_by_key.get(key)
        if hit and (hit[0] or hit[1]):
            mapping[str(f["match_id"])] = {"home_stats": hit[0], "away_stats": hit[1]}
            matched += 1
        elif f.get("home_score") is not None:
            unmatched_with_score.append(f'{f["date"]} {f["home_team"]} vs {f["away_team"]}')

    print(f"baked fixtures: {len(fixtures)}  with official stats: {matched}")
    print(f"scored fixtures WITHOUT official stats: {len(unmatched_with_score)}")
    for u in unmatched_with_score[:25]:
        print("  ", u)

    json.dump(mapping, open(OUT, "w", encoding="utf-8"),
              ensure_ascii=False, indent=0, sort_keys=True)
    print("wrote", OUT, "entries:", len(mapping))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
