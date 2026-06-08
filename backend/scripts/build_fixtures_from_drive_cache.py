"""Build a committed 2025-26 Superliga fixtures dataset from the local Wyscout
drive_cache (teams + score from the filename, date from matchid_to_date.json,
round from each match's roundId). No network / Sportradar needed.

Run from the backend/ directory:
    python scripts/build_fixtures_from_drive_cache.py

Emits backend/ml/data/superliga_2025_26_fixtures.json. Rounds are numbered
1..N chronologically by each roundId's earliest date. Phase is "regular" before
the 2026-03-08 play-off cutoff, else "playoff_window" (the actual play-off /
play-out group is resolved at serve time from the standings table).
"""
from __future__ import annotations

import glob
import json
import os
import re
from datetime import date as _date

_BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DRIVE = os.path.join(_BACKEND, "ml", "data", "drive_cache")
_DATES = os.path.join(_BACKEND, "ml", "data", "matchid_to_date.json")
_OUT = os.path.join(_BACKEND, "ml", "data", "superliga_2025_26_fixtures.json")
_PLAYOFF_CUTOFF = "2026-03-08"

try:
    from sportradar.team_registry import SUPERLIGA_TEAMS, normalise
except Exception:  # pragma: no cover - fallback if run oddly
    import sys
    sys.path.insert(0, _BACKEND)
    from sportradar.team_registry import SUPERLIGA_TEAMS, normalise


def canon_team(raw: str) -> str:
    """Map a Wyscout filename team name to the registry short label."""
    n = normalise(raw)
    best = None
    for t in SUPERLIGA_TEAMS:
        sub = normalise(t.wy_substr)
        if not sub:
            continue
        if sub in n or n in sub:
            # prefer the longest matching wy_substr (most specific)
            if best is None or len(sub) > best[1]:
                best = (t.short, len(sub))
    return best[0] if best else raw.strip()


def parse_filename(base: str):
    """'Home - Away, 2-1' -> (home, away, 2, 1). Tolerant of missing/garbled score."""
    head, _, score = base.rpartition(", ")
    home_raw, _, away_raw = head.partition(" - ")
    hs = as_ = None
    m = re.match(r"\s*(\d{1,2})\s*-\s*(\d{1,2})\b", score)
    if m:
        hs, as_ = int(m.group(1)), int(m.group(2))
        if hs > 30 or as_ > 30:  # guard against matchId bleeding into the score
            hs = as_ = None
    return home_raw.strip(), away_raw.strip(), hs, as_


def main() -> None:
    with open(_DATES, encoding="utf-8") as fh:
        dates = json.load(fh)

    fixtures = []
    for fp in glob.glob(os.path.join(_DRIVE, "*_players_stats.json")):
        base = os.path.basename(fp)[: -len("_players_stats.json")]
        home_raw, away_raw, hs, as_ = parse_filename(base)
        try:
            with open(fp, encoding="utf-8") as fh:
                players = (json.load(fh) or {}).get("players") or []
        except Exception:
            continue
        if not players:
            continue
        match_id = players[0].get("matchId")
        round_id = players[0].get("roundId")
        date = dates.get(str(match_id))
        if not date:
            continue
        fixtures.append({
            "match_id": str(match_id),
            "date": date,
            "_round_id": round_id,
            "home_team": canon_team(home_raw),
            "away_team": canon_team(away_raw),
            "home_score": hs,
            "away_score": as_,
            "venue": None,
        })

    # Dedupe by match_id (the drive_cache occasionally holds the same match twice).
    seen: set[str] = set()
    deduped = []
    for f in fixtures:
        if f["match_id"] in seen:
            continue
        seen.add(f["match_id"])
        deduped.append(f)
    fixtures = deduped

    # roundId is only the season-phase (3 values), so derive the MATCHDAY by
    # date-clustering: a new round starts when the gap to the previous match
    # date is > 2 days (Superliga rounds are Fri-Mon clusters with ~3-7 day gaps
    # between them). Numbered 1..N chronologically; same-date matches share a round.
    all_dates = sorted({f["date"] for f in fixtures})
    round_of_date: dict[str, int] = {}
    rnum = 0
    prev = None
    for ds in all_dates:
        d = _date.fromisoformat(ds)
        if prev is None or (d - prev).days > 2:
            rnum += 1
        round_of_date[ds] = rnum
        prev = d

    for f in fixtures:
        f["round"] = round_of_date[f["date"]]
        f["phase"] = "regular" if f["date"] < _PLAYOFF_CUTOFF else "playoff_window"
        f.pop("_round_id", None)
    rid_order = list(range(1, rnum + 1))

    fixtures.sort(key=lambda f: (f["date"], f["home_team"]))
    payload = {
        "season": "2025",
        "generated_from": "wyscout_drive_cache",
        "round_count": len(rid_order),
        "fixtures": fixtures,
    }
    with open(_OUT, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=1, ensure_ascii=False)
    print(f"wrote {len(fixtures)} fixtures across {len(rid_order)} rounds -> {_OUT}")


if __name__ == "__main__":
    main()
