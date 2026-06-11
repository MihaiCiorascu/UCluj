"""One-time: map each Wyscout drive_cache match to its Sportradar fixture id.

Pull the Sportradar season schedule once (cached to TEMP so re-runs cost no calls),
then match each Wyscout match (date + the two team names parsed from the drive_cache
filename) to the Sportradar fixture on the same date whose competitors token-match.
Emits backend/ml/data/wyscout_to_sr_fixture.json. Run from backend/ with
PYTHONPATH=. and a working SPORTRADAR_API_KEY in the environment.
"""
from __future__ import annotations

import asyncio
import json
import re
import tempfile
import unicodedata
from pathlib import Path

from clients.sportradar_client import SportradarClient
from api.v1.endpoints._drive_cache_match import build_drive_cache_index

SEASON = "sr:season:131507"  # Romanian Superliga 2025-26
_DATA = Path(__file__).resolve().parents[1] / "ml" / "data"
_OUT = _DATA / "wyscout_to_sr_fixture.json"
_SCHED_CACHE = Path(tempfile.gettempdir()) / "sr_schedule_131507.json"

# Generic words that carry no club identity; dropped before token matching.
_STOP = {"fc", "afc", "cs", "acs", "asc", "sc", "csm", "fotbal", "club", "calcio"}
# Wyscout/Sportradar name variants that should collapse to the same token.
_ALIAS = {"fcs": "fcsb", "steaua": "fcsb"}


def _norm_tokens(name: str) -> frozenset[str]:
    s = "".join(c for c in unicodedata.normalize("NFKD", name or "") if not unicodedata.combining(c))
    toks = set()
    for t in re.split(r"[^a-z0-9]+", s.lower()):
        if not t or t in _STOP or t.isdigit():
            continue
        toks.add(_ALIAS.get(t, t))
    return frozenset(toks)


def _contain(a: frozenset[str], b: frozenset[str]) -> float:
    """Overlap coefficient: |a&b| / min(|a|,|b|). 1.0 when the smaller set is contained."""
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


_FNAME = re.compile(r"^(.*?) - (.*?), (\d+)-(\d+)(?:_\d+)?_players_stats\.json$")


def _parse_filename(path: str) -> tuple[str, str] | None:
    m = _FNAME.match(Path(path).name)
    return (m.group(1), m.group(2)) if m else None


def _extract_sr_fixtures(sched: dict) -> list[dict]:
    rows = sched.get("schedules") or sched.get("sport_events") or []
    out = []
    for r in rows:
        ev = r.get("sport_event", r) if isinstance(r, dict) else {}
        eid = ev.get("id")
        start = ev.get("start_time") or ev.get("scheduled") or ""
        date = start[:10] if isinstance(start, str) else ""
        comps = ev.get("competitors") or []
        home = next((c.get("name", "") for c in comps if c.get("qualifier") == "home"), "")
        away = next((c.get("name", "") for c in comps if c.get("qualifier") == "away"), "")
        if eid and date and home and away:
            out.append({"id": eid, "date": date, "home": home, "away": away})
    return out


async def _load_schedule() -> dict | None:
    if _SCHED_CACHE.exists():
        print(f"using cached schedule {_SCHED_CACHE}")
        return json.loads(_SCHED_CACHE.read_text(encoding="utf-8"))
    print("fetching season schedule (1 call)...")
    sched = await SportradarClient().season_schedules(SEASON)
    if sched:
        _SCHED_CACHE.write_text(json.dumps(sched, ensure_ascii=False), encoding="utf-8")
    return sched


async def main() -> None:
    sched = await _load_schedule()
    if not sched:
        print("NO SCHEDULE (blocked/empty)")
        return
    sr = _extract_sr_fixtures(sched)
    print(f"SR fixtures: {len(sr)}")
    by_date: dict[str, list[dict]] = {}
    for f in sr:
        f["_h"], f["_a"] = _norm_tokens(f["home"]), _norm_tokens(f["away"])
        by_date.setdefault(f["date"], []).append(f)

    mid_to_date = json.loads((_DATA / "matchid_to_date.json").read_text(encoding="utf-8"))
    index = build_drive_cache_index()  # {wyscout_matchId(str): filepath}

    bridge: dict[str, str] = {}
    unmatched: list[str] = []
    for mid, fpath in index.items():
        teams = _parse_filename(fpath)
        date = mid_to_date.get(str(mid))
        if not teams or not date:
            unmatched.append(f"{mid} (no teams/date)")
            continue
        wh, wa = _norm_tokens(teams[0]), _norm_tokens(teams[1])
        best, best_score = None, 0.0
        for cand in by_date.get(date, []):
            h, a = _contain(wh, cand["_h"]), _contain(wa, cand["_a"])
            if min(h, a) >= 0.99 and (h + a) > best_score:
                best, best_score = cand, h + a
        if best:
            bridge[str(mid)] = best["id"]
        else:
            unmatched.append(f"{mid} {teams[0]} vs {teams[1]} ({date})")

    _OUT.write_text(json.dumps(bridge, ensure_ascii=False, indent=0), encoding="utf-8")
    print(f"\nbridged {len(bridge)}/{len(index)} matches -> {_OUT.name}")
    if unmatched:
        print(f"unmatched ({len(unmatched)}):")
        for u in unmatched[:30]:
            print("  ", u)


if __name__ == "__main__":
    asyncio.run(main())
