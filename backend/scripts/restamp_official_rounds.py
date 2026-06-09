"""One-off re-stamper for the official Superliga matchday numbers in
``backend/ml/data/superliga_2025_26_fixtures.json``.

The baked fixtures' ``round`` field was produced by date-clustering in
``build_fixtures_from_drive_cache.py``: a new round started whenever the gap to
the previous match date exceeded two days. That merged official matchdays that
were spread across more than two days, leaving the labels roughly two behind the
official Superliga count. This script replaces ``round`` with the official
Sportradar matchday number for every fixture.

Source: the Sportradar 25/26 schedule (``seasons/sr:season:131507/schedules``),
where each event carries ``sport_event_context.round.number`` and
``sport_event_context.stage.phase``. It joins to the baked fixtures by the
canonical (home, away, date) key, which is unique because the date disambiguates
the two meetings of any pair (the baked dates already came from this same
schedule via ``build_matchid_dates.py``).

Regular-season fixtures take the official round number directly. Playoff /
play-out fixtures (a separate Sportradar stage whose round numbers may restart at
one) are offset to continue after the last regular round, so the single global
``round`` field the dashboard serves by stays contiguous and unique. The split is
driven by the baked ``phase`` field; the runtime keeps the playoff window
date-anchored to the 2026-03-13 cutoff regardless, so re-numbering rounds is
safe.

Runtime never calls Sportradar; only the committed JSON ships.

    SPORTRADAR_API_KEY=... python backend/scripts/restamp_official_rounds.py            # dry run
    SPORTRADAR_API_KEY=... python backend/scripts/restamp_official_rounds.py --apply    # write JSON
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # backend/
sys.path.insert(0, ROOT)

from clients.sportradar_client import SportradarClient  # noqa: E402
from sportradar.team_registry import team_by_alias  # noqa: E402

FIXTURES = os.path.join(ROOT, "ml", "data", "superliga_2025_26_fixtures.json")
SEASON_ID = "sr:season:131507"  # Superliga 25/26


def _canon(name: str):
    t = team_by_alias(name or "")
    return t.short if t else None


async def _fetch_sr():
    c = SportradarClient()
    data = await c.season_schedules(SEASON_ID)
    rows = []
    for r in (data or {}).get("schedules", []):
        se = r.get("sport_event", {}) or {}
        ctx = se.get("sport_event_context", {}) or {}
        comps = se.get("competitors", []) or []
        h = next((x for x in comps if x.get("qualifier") == "home"), {})
        a = next((x for x in comps if x.get("qualifier") == "away"), {})
        date = (se.get("start_time") or se.get("scheduled") or "")[:10]
        rnd = (ctx.get("round", {}) or {}).get("number")
        phase = (ctx.get("stage", {}) or {}).get("phase")
        rows.append({
            "home": _canon(h.get("name", "")),
            "away": _canon(a.get("name", "")),
            "date": date,
            "round": rnd,
            "phase": phase,
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="write the JSON (default: dry run, prints diagnostics only)")
    args = ap.parse_args()

    sr = asyncio.run(_fetch_sr())
    print(f"SR schedule events: {len(sr)}")
    if not sr:
        print("No schedule returned (missing/invalid SPORTRADAR_API_KEY or quota?). Aborting.")
        return 1

    sr_by_key: dict = {}
    sr_phase_rounds: dict = defaultdict(set)
    for f in sr:
        if f["round"] is not None:
            sr_phase_rounds[f["phase"]].add(f["round"])
        if f["home"] and f["away"] and f["date"] and f["round"] is not None:
            sr_by_key[(f["home"], f["away"], f["date"])] = (f["round"], f["phase"])
    print("SR phase -> round-number range:")
    for ph, rounds in sorted(sr_phase_rounds.items(), key=lambda kv: str(kv[0])):
        print(f"  {ph!r}: {min(rounds)}..{max(rounds)} ({len(rounds)} distinct)")

    with open(FIXTURES, encoding="utf-8") as fh:
        doc = json.load(fh)
    fixtures = doc["fixtures"]

    # Resolve each baked fixture's official (round, sr_phase) via the join key.
    matched = 0
    unmatched: list = []
    reg_rounds: set = set()
    po_rounds: set = set()
    resolved: list = []  # parallel to fixtures: (official_round, sr_phase) or None
    for fx in fixtures:
        key = (_canon(fx["home_team"]), _canon(fx["away_team"]), fx["date"])
        hit = sr_by_key.get(key)
        resolved.append(hit)
        if hit is None:
            unmatched.append(
                f'{fx["home_team"]} vs {fx["away_team"]} {fx["date"]} (baked r{fx["round"]})')
            continue
        matched += 1
        rnd, _ = hit
        (reg_rounds if fx["phase"] == "regular" else po_rounds).add(rnd)

    print(f"\nbaked fixtures: {len(fixtures)}  matched: {matched}  unmatched: {len(unmatched)}")
    if reg_rounds:
        print(f"regular sr-rounds present: {min(reg_rounds)}..{max(reg_rounds)} "
              f"({len(reg_rounds)} distinct)")
    if po_rounds:
        print(f"playoff sr-rounds present: {min(po_rounds)}..{max(po_rounds)} "
              f"({len(po_rounds)} distinct)")
    if unmatched:
        print(f"UNMATCHED ({len(unmatched)}):")
        for u in unmatched[:25]:
            print("  ", u)

    # Offset playoff rounds so the global round field stays contiguous + unique.
    reg_max = max(reg_rounds) if reg_rounds else 0
    po_min = min(po_rounds) if po_rounds else None
    offset = reg_max if (po_min is not None and po_min <= reg_max) else 0
    if po_rounds:
        print(f"\nregular max round = {reg_max}; playoff offset = {offset} "
              f"(playoff global rounds {min(po_rounds) + offset}..{max(po_rounds) + offset})")

    new_rounds: list = []
    for fx, hit in zip(fixtures, resolved):
        if hit is None:
            new_rounds.append(None)
            continue
        rnd, _ = hit
        new_rounds.append(rnd if fx["phase"] == "regular" else rnd + offset)

    # Sanity: each date should map to a single global round (unless a real
    # matchday legitimately spanned more than one calendar day).
    date_rounds: dict = defaultdict(set)
    changed = 0
    for fx, nr in zip(fixtures, new_rounds):
        if nr is None:
            continue
        date_rounds[fx["date"]].add(nr)
        if nr != fx["round"]:
            changed += 1
    multi = {d: sorted(rs) for d, rs in date_rounds.items() if len(rs) > 1}
    print(f"\nrounds changed: {changed}/{len(fixtures)}")
    print(f"dates mapping to >1 round: {len(multi)}")
    for d, rs in list(multi.items())[:15]:
        print("  ", d, rs)

    if unmatched:
        print("\nNOT applying: some baked fixtures did not match the SR schedule. "
              "Resolve the join (team aliases / dates) first.")
        return 1

    if not args.apply:
        print("\nDry run only. Re-run with --apply to write the JSON.")
        return 0

    new_round_count = max(r for r in new_rounds if r is not None)
    for fx, nr in zip(fixtures, new_rounds):
        fx["round"] = nr
    out = {
        "season": doc.get("season"),
        "generated_from": doc.get("generated_from"),
        "round_count": new_round_count,
        "round_source": "sportradar_official_matchday",
        "fixtures": fixtures,
    }
    with open(FIXTURES, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print(f"\nwrote {FIXTURES}: round_count={new_round_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
