"""
Sportradar-based position snapshot for the FC Universitatea Cluj squad.

This script is the Sportradar analogue of
:mod:`backend.scripts.fetch_transfermarkt_positions`. It is the
*legitimate* cross-check path: Sportradar is one of the project's
licensed data providers (used for fixtures and standings throughout the
backend), and its competitor-profile feed already exposes a per-player
``position`` field that lands in the ``sr_players`` table via
:func:`backend.sportradar.repository.upsert_profile`.

Where the Transfermarkt path required scraping a site whose Terms of
Use restrict automated access, Sportradar is a paid API the project
already has an integration for; reading the local ``sr_players``
projection of that feed is contractually clean.

Output
------

Writes ``backend/ml/data/sportradar_positions.json`` of the form::

    {
      "status": "ok",
      "team_id": "sr:competitor:NNNNN",
      "team_name": "Universitatea Cluj",
      "fetched_at": "2026-05-15T...",
      "entries": [
        {"id": "sr:player:NNNNN", "name": "A. Chipciu",
         "position": "midfielder", "jersey_number": 10},
        ...
      ]
    }

When the database is unreachable, the U Cluj team cannot be located, or
the team has zero rows in ``sr_players`` (typical when the Sportradar
profile sync has not been run recently), the script writes a stub::

    {"status": "skipped — sportradar table empty or db unavailable",
     "reason": "<short message>", "entries": []}

so the downstream cross-check (:mod:`backend.scripts.cross_check_positions_via_sportradar`)
can still report cleanly.

Why not query the API directly?
-------------------------------

A direct ``GET /admin/sync/data/players?team_id=...`` HTTP call would
require the FastAPI app to be running, plus a working Sportradar API
key and an active subscription. Querying the local ``sr_players``
projection instead keeps the script (a) runnable offline whenever the
DB has been populated previously, and (b) cleanly skippable when it has
not. To refresh the data when a Sportradar subscription is active, run::

    POST /admin/sync/seasons/{current_season_id}/profiles

through the running FastAPI app, then rerun this script.

Usage
-----

::

    python backend/scripts/fetch_sportradar_positions.py
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]  # backend/

OUT_PATH = ROOT / "ml" / "data" / "sportradar_positions.json"
TEAM_NAME_NEEDLE = "Universitatea Cluj"  # case-insensitive substring


def _resolve_sync_database_url() -> Tuple[str, str]:
    """Return ``(url, source)`` for a sync SQLAlchemy connection.

    The project ships an *async* engine (``sqlite+aiosqlite://`` /
    ``postgresql+asyncpg://``). For a one-shot script we strip the async
    dialect suffix so a normal sync engine can connect. The driver
    swaps are:

    * ``sqlite+aiosqlite://`` -> ``sqlite:///``
    * ``postgresql+asyncpg://`` -> ``postgresql+psycopg://`` (falling
      back to ``postgresql://`` if ``psycopg`` is not installed)
    """
    env_url = os.environ.get("DATABASE_URL", "").strip()
    if env_url:
        url = env_url
        source = "env DATABASE_URL"
    else:
        # Match the default in backend/app/config.py.
        url = "sqlite+aiosqlite:///./umbraro.db"
        source = "default (sqlite+aiosqlite:///./umbraro.db)"

    if url.startswith("sqlite+aiosqlite"):
        url = url.replace("sqlite+aiosqlite", "sqlite", 1)
    elif url.startswith("postgresql+asyncpg"):
        url = url.replace("postgresql+asyncpg", "postgresql+psycopg", 1)
    return url, source


def _write_skipped(reason: str) -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "status": "skipped — sportradar table empty or db unavailable",
        "reason": reason,
        "team_name_needle": TEAM_NAME_NEEDLE,
        "fetched_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "entries": [],
    }
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(f"Wrote stub snapshot to {OUT_PATH.relative_to(ROOT)} (status: skipped)")


def _try_query_sportradar(db_url: str) -> Optional[Tuple[Dict[str, Any], List[Dict[str, Any]]]]:
    """Return ``({team_id, team_name}, players)`` or ``None`` on any failure.

    Failure modes that map to ``None``:

    * SQLAlchemy not installed.
    * Database connection failure (file missing, server unreachable).
    * Required tables not present (no migrations have run on this DB).
    * No row in ``sr_teams`` matches the U Cluj name needle.
    * The matching team has zero player rows in ``sr_players``.
    """
    try:
        from sqlalchemy import create_engine, text  # type: ignore
    except Exception as exc:
        print(f"  sqlalchemy unavailable ({exc!r}); cannot query database",
              file=sys.stderr)
        return None

    try:
        engine = create_engine(db_url)
        with engine.connect() as conn:
            # Try a case-insensitive substring match on the team name.
            team_row = conn.execute(
                text(
                    "SELECT id, name FROM sr_teams "
                    "WHERE LOWER(name) LIKE :needle "
                    "ORDER BY name LIMIT 1"
                ),
                {"needle": f"%{TEAM_NAME_NEEDLE.lower()}%"},
            ).fetchone()
            if team_row is None:
                print(f"  no sr_teams row matched '{TEAM_NAME_NEEDLE}'",
                      file=sys.stderr)
                return None
            team_id = str(team_row[0])
            team_name = str(team_row[1])

            player_rows = conn.execute(
                text(
                    "SELECT id, name, position, jersey_number, nationality "
                    "FROM sr_players WHERE team_id = :tid ORDER BY name"
                ),
                {"tid": team_id},
            ).fetchall()
            if not player_rows:
                print(
                    f"  team '{team_name}' (id={team_id}) found but has zero "
                    "rows in sr_players (sync not run?)",
                    file=sys.stderr,
                )
                return None

            players = [
                {
                    "id": str(r[0]),
                    "name": str(r[1] or ""),
                    "position": str(r[2] or ""),
                    "jersey_number": int(r[3]) if r[3] is not None else None,
                    "nationality": str(r[4] or ""),
                }
                for r in player_rows
            ]
            return ({"team_id": team_id, "team_name": team_name}, players)
    except Exception as exc:
        print(f"  database query failed: {exc!r}", file=sys.stderr)
        return None


def main() -> int:
    db_url, db_source = _resolve_sync_database_url()
    print(f"Sportradar position snapshot for '{TEAM_NAME_NEEDLE}'")
    print(f"  DB URL: {db_url}  (source: {db_source})")

    result = _try_query_sportradar(db_url)
    if result is None:
        _write_skipped(
            "Sportradar profile data unavailable. To populate it, configure "
            "DATABASE_URL and run POST /admin/sync/seasons/{season_id}/profiles "
            "with an active Sportradar API key."
        )
        return 0  # exit 0 — graceful skip, mirrors fetch_transfermarkt_positions

    meta, players = result
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload: Dict[str, Any] = {
        "status": "ok",
        "team_id": meta["team_id"],
        "team_name": meta["team_name"],
        "fetched_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "entries": players,
    }
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(
        f"  wrote {len(players)} Sportradar players for "
        f"team '{meta['team_name']}' (id={meta['team_id']}) "
        f"to {OUT_PATH.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
