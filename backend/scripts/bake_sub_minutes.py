"""One-time: fetch each match's Sportradar timeline and bake the substitution
clock minutes, keyed by Wyscout match id.

Reads backend/ml/data/wyscout_to_sr_fixture.json (the bridge), calls the timeline
for each fixture, and records every substitution event as
{minute, stoppage, side(home/away), out(name), in(name)} parsed from the RAW
timeline (players[].type == substituted_out/in). Merges into
backend/ml/data/match_sub_minutes.json so it can be run incrementally.

Run from backend/ with PYTHONPATH=. and SPORTRADAR_API_KEY set. Optional env
BAKE_LIMIT=N bakes only the first N still-unbaked matches (for validation);
SPORTRADAR_RATE_DELAY=1.3 is recommended for the full run to respect the trial QPS.
"""
from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

from clients.sportradar_client import SportradarClient

_DATA = Path(__file__).resolve().parents[1] / "ml" / "data"
_BRIDGE = _DATA / "wyscout_to_sr_fixture.json"
_OUT = _DATA / "match_sub_minutes.json"


def _parse_subs(timeline: dict) -> list[dict]:
    out = []
    for e in (timeline.get("timeline") or timeline.get("events") or []):
        if not isinstance(e, dict) or e.get("type") != "substitution":
            continue
        players = e.get("players") or []
        op = next((p for p in players if p.get("type") == "substituted_out"), None)
        ip = next((p for p in players if p.get("type") == "substituted_in"), None)
        mt = e.get("match_time")
        if mt is None or not (op or ip):
            continue
        out.append({
            "minute": int(mt),
            "stoppage": int(e.get("stoppage_time") or 0),
            "side": e.get("competitor") or "",       # "home" / "away"
            "out": (op or {}).get("name", ""),         # "Surname, Firstname"
            "in": (ip or {}).get("name", ""),
        })
    return out


async def main() -> None:
    bridge: dict[str, str] = json.loads(_BRIDGE.read_text(encoding="utf-8"))
    baked: dict[str, list] = json.loads(_OUT.read_text(encoding="utf-8")) if _OUT.exists() else {}

    todo = [(mid, fid) for mid, fid in bridge.items() if mid not in baked]
    limit = int(os.environ.get("BAKE_LIMIT", "0") or "0")
    if limit:
        todo = todo[:limit]
    print(f"to bake: {len(todo)} matches (already baked: {len(baked)})")

    client = SportradarClient()
    ok = empty = fail = 0
    for i, (mid, fid) in enumerate(todo, 1):
        tl = await client.sport_event_timeline(fid)
        if tl is None:
            fail += 1
            print(f"  [{i}/{len(todo)}] {mid} {fid} -> FAIL (None)")
            continue
        subs = _parse_subs(tl)
        baked[mid] = subs
        ok += 1
        if subs:
            empty += 0
        else:
            empty += 1
        if i <= 8 or i % 25 == 0:
            print(f"  [{i}/{len(todo)}] {mid} -> {len(subs)} subs")
        # periodic checkpoint so a mid-run failure keeps progress
        if i % 25 == 0:
            _OUT.write_text(json.dumps(baked, ensure_ascii=False), encoding="utf-8")

    _OUT.write_text(json.dumps(baked, ensure_ascii=False), encoding="utf-8")
    print(f"\nbaked ok={ok} fail={fail} (matches with 0 subs: {empty}); total stored: {len(baked)} -> {_OUT.name}")
    # sample
    for mid in list(baked)[:1]:
        print("sample", mid, json.dumps(baked[mid][:3], ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main())
