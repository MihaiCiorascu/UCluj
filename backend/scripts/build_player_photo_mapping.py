"""Build a Wyscout -> SofaScore mapping for Romanian Superliga players.

Walks the canonical Wyscout player roster at
``backend/ml/data/drive_cache/players (1).json``, queries SofaScore's
public search API for each player, and writes:

  ml/data/wyscout_to_sofascore.json   : confident matches (wy_id -> sofascore_id)
  ml/data/photo_manual_review.csv     : ambiguous / no-match cases for the
                                        user to resolve by hand

Match policy:

  - Exact date-of-birth match between Wyscout and SofaScore is the strongest
    signal. When a candidate has the same DOB as the Wyscout entry, we
    accept it.
  - If no DOB match but exactly one candidate has the same first name + last
    name (case-insensitive), we accept it.
  - Otherwise the player goes to manual review with all candidates listed.

Rate-limit: 1 request per second by default to stay well under SofaScore's
informal limits. Use --rps to override. Progress is checkpointed every 25
players so a network interruption only loses the most recent batch.

Run from backend/ with:
    python scripts/build_player_photo_mapping.py
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from pathlib import Path
from typing import Any

# curl_cffi impersonates a real browser TLS fingerprint to clear SofaScore's
# Cloudflare bot check, which 403s plain httpx/requests from any IP.
from curl_cffi import requests as cffi


try:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows cp1252 safety for diacritics
except Exception:
    pass

SOFASCORE_SEARCH = "https://api.sofascore.com/api/v1/search/player-team-persons"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
)


def _normalise(name: str) -> str:
    return (name or "").strip().lower()


def _full_name(player: dict) -> str:
    parts = [
        (player.get("firstName") or "").strip(),
        (player.get("middleName") or "").strip(),
        (player.get("lastName") or "").strip(),
    ]
    return " ".join(p for p in parts if p)


def _search_query(player: dict) -> str:
    first = (player.get("firstName") or "").strip()
    last = (player.get("lastName") or "").strip()
    short = (player.get("shortName") or "").strip()
    candidates = [
        f"{first} {last}".strip(),
        last,
        short.replace(".", " ").strip(),
    ]
    for c in candidates:
        if len(c) >= 3:
            return c
    return short


def _sofascore_search(client, query: str) -> list[dict]:
    """Hit the SofaScore search endpoint and return the player results.

    The endpoint returns an envelope ``{"results": [{"entity": {...},
    "type": "player"}, ...]}`` mixing players, teams and persons. We keep
    only the player entries.
    """
    try:
        resp = client.get(
            SOFASCORE_SEARCH,
            params={"q": query, "page": 0},
            timeout=15,
        )
    except Exception as exc:
        print(f"  [http-error] {exc}", file=sys.stderr)
        return []
    if resp.status_code == 429:
        print("  [rate-limit] backing off 30 s ...", file=sys.stderr)
        time.sleep(30)
        return _sofascore_search(client, query)
    if resp.status_code != 200:
        print(f"  [http {resp.status_code}] {resp.text[:120]}", file=sys.stderr)
        return []
    try:
        body = resp.json()
    except ValueError:
        return []
    results = body.get("results") or []
    return [r.get("entity") for r in results if r.get("type") == "player"]


def _candidate_dob(cand: dict) -> str | None:
    """SofaScore returns birth date as a unix timestamp at midnight UTC."""
    ts = cand.get("dateOfBirthTimestamp")
    if ts is None:
        return None
    try:
        # Format as YYYY-MM-DD without dragging in pytz.
        import datetime as _dt
        return _dt.datetime.fromtimestamp(int(ts), tz=_dt.timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return None


def _pick_match(player: dict, candidates: list[dict]) -> tuple[dict | None, str]:
    """Pick a single SofaScore candidate or fall through to manual review.

    Returns (candidate, reason). When candidate is None, reason explains
    why the player went to manual review.
    """
    if not candidates:
        return None, "no-candidates"

    wy_dob = player.get("birthDate")
    wy_first = _normalise(player.get("firstName"))
    wy_last = _normalise(player.get("lastName"))

    dob_matches = [c for c in candidates if _candidate_dob(c) == wy_dob]
    if len(dob_matches) == 1:
        return dob_matches[0], "dob-match"
    if len(dob_matches) > 1:
        # Multiple players with the same DOB; prefer the one whose last name
        # also matches.
        narrowed = [
            c for c in dob_matches
            if _normalise(c.get("lastName")) == wy_last
        ]
        if len(narrowed) == 1:
            return narrowed[0], "dob-and-lastname"
        return None, "multiple-dob-matches"

    name_matches = [
        c for c in candidates
        if _normalise(c.get("firstName")) == wy_first
        and _normalise(c.get("lastName")) == wy_last
    ]
    if len(name_matches) == 1:
        return name_matches[0], "exact-name-no-dob"

    return None, f"weak-match (top: {candidates[0].get('name')!r})"


def _load_progress(out_path: Path) -> dict[str, dict]:
    if not out_path.exists():
        return {}
    try:
        return json.loads(out_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_progress(out_path: Path, mapping: dict[str, dict]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(mapping, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--players",
        default="ml/data/drive_cache/players (1).json",
        help="Path to the Wyscout roster JSON.",
    )
    parser.add_argument(
        "--out",
        default="ml/data/wyscout_to_sofascore.json",
        help="Where to write confident wy_id -> sofascore_id matches.",
    )
    parser.add_argument(
        "--manual-review",
        default="ml/data/photo_manual_review.csv",
        help="Where to write ambiguous and no-match players for manual review.",
    )
    parser.add_argument(
        "--rps",
        type=float,
        default=1.0,
        help="Requests per second to SofaScore. Lower is safer.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="If positive, only process this many players (debug).",
    )
    args = parser.parse_args()

    players_path = Path(args.players)
    out_path = Path(args.out)
    review_path = Path(args.manual_review)

    if not players_path.exists():
        print(f"[fatal] players file not found: {players_path}", file=sys.stderr)
        return 2

    raw = json.loads(players_path.read_text(encoding="utf-8"))
    players = raw.get("players", []) if isinstance(raw, dict) else raw
    if args.limit:
        players = players[: args.limit]
    print(f"loaded {len(players)} players from {players_path.name}")

    mapping = _load_progress(out_path)
    print(f"resuming with {len(mapping)} previously-mapped players")

    review_rows: list[dict] = []
    delay = 1.0 / max(args.rps, 0.1)

    with cffi.Session(impersonate="chrome") as client:
        for idx, player in enumerate(players, start=1):
            wy_id = str(player.get("wyId"))
            if not wy_id:
                continue
            if wy_id in mapping:
                continue

            query = _search_query(player)
            print(f"[{idx}/{len(players)}] wy={wy_id} query={query!r}", end=" ")
            candidates = _sofascore_search(client, query)
            cand, reason = _pick_match(player, candidates)

            if cand:
                sofascore_id = cand.get("id")
                mapping[wy_id] = {
                    "sofascore_id": sofascore_id,
                    "sofascore_name": cand.get("name"),
                    "sofascore_team": (cand.get("team") or {}).get("name"),
                    "reason": reason,
                }
                print(f"-> sr={sofascore_id} ({reason})")
            else:
                top = [
                    {
                        "sofascore_id": c.get("id"),
                        "name": c.get("name"),
                        "team": (c.get("team") or {}).get("name"),
                        "dob": _candidate_dob(c),
                    }
                    for c in (candidates[:5] if candidates else [])
                ]
                review_rows.append({
                    "wy_id": wy_id,
                    "wy_name": _full_name(player),
                    "wy_dob": player.get("birthDate"),
                    "wy_team_id": player.get("currentTeamId"),
                    "reason": reason,
                    "top_candidates": json.dumps(top, ensure_ascii=False),
                })
                print(f"-> manual ({reason})")

            time.sleep(delay)

            if idx % 25 == 0:
                _save_progress(out_path, mapping)

    _save_progress(out_path, mapping)
    review_path.parent.mkdir(parents=True, exist_ok=True)
    with review_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["wy_id", "wy_name", "wy_dob", "wy_team_id", "reason", "top_candidates"],
        )
        writer.writeheader()
        writer.writerows(review_rows)

    print(f"\nsuccess: mapped {len(mapping)} players to {out_path.name}")
    print(f"        {len(review_rows)} entries flagged for manual review in {review_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
