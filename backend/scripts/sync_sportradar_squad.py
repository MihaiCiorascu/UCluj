"""
One-shot Sportradar squad sync for FC Universitatea Cluj.

Smoke-tests the configured Sportradar API key, discovers the Romanian
Superliga competition and its current season, then runs
:func:`backend.sportradar.services.team_sync.TeamSyncService.sync_all_profiles`
which (per team) fetches ``/competitors/{tid}/profile.json`` and upserts
the result into ``sr_teams`` + ``sr_players`` via
:func:`backend.sportradar.repository.upsert_profile`.

After this script succeeds the cross-check pipeline (already in the repo
from Iteration K) becomes runnable end-to-end::

    python backend/scripts/sync_sportradar_squad.py            # populate DB
    python backend/scripts/fetch_sportradar_positions.py       # write snapshot
    python backend/scripts/cross_check_positions_via_sportradar.py  # write CSV

Hardcoded fallbacks (used only when discovery fails):

* Competition: ``sr:competition:152`` — Romania Superliga
* Season:      ``sr:season:131507`` — 2025/26 (cross-referenced from
  ``backend/api/v1/endpoints/standings.py``)

Exit codes:

* ``0`` — sync completed successfully.
* ``1`` — Sportradar API key invalid / 403.
* ``2`` — Sportradar unreachable / no competitions returned.
* ``3`` — sync raised an exception midway (the partial state is still
  committed; rerun safely).
"""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from clients.sportradar_client import SportradarClient, SportradarError  # type: ignore  # noqa: E402
from db.engine import async_session, init_db, engine  # type: ignore  # noqa: E402
from sportradar import repository as repo  # type: ignore  # noqa: E402
from sportradar.services.competition_sync import CompetitionSyncService  # type: ignore  # noqa: E402
from sportradar.services.team_sync import TeamSyncService  # type: ignore  # noqa: E402
from sqlalchemy import select, func  # type: ignore  # noqa: E402

from sportradar.db_models import SrPlayer, SrTeam  # type: ignore  # noqa: E402

# Fallbacks (used only when discovery fails).
FALLBACK_COMPETITION_ID = "sr:competition:152"
FALLBACK_SEASON_ID = "sr:season:131507"

# Tighten the SR client's log spam to WARNING so the progress lines stand out.
logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")


def _print(msg: str) -> None:
    """Flush each progress line immediately so the user sees live output."""
    print(msg, flush=True)


async def _smoke_test_key(client: SportradarClient) -> bool:
    """Return True iff the configured key reaches Sportradar successfully."""
    try:
        data = await client.competitions()
    except SportradarError as exc:
        _print(f"FAIL: Sportradar rejected the key ({exc}).")
        return False
    if not data or not data.get("competitions"):
        _print("FAIL: /competitions.json returned nothing — Sportradar may be unreachable.")
        return False
    _print(f"OK: API key verified — {len(data.get('competitions', []))} competitions returned.")
    return True


async def _resolve_season_id(client: SportradarClient) -> tuple[str, str, str]:
    """Return ``(competition_id, season_id, season_start)``.

    Both pieces fall back to the hardcoded constants if Sportradar
    returns no matching competition or no seasons under it.
    """
    comp_svc = CompetitionSyncService(client)
    comp = await comp_svc.discover_superliga()
    if comp is None:
        _print(
            f"WARN: Romania Superliga not in discovery; falling back to "
            f"{FALLBACK_COMPETITION_ID}."
        )
        competition_id = FALLBACK_COMPETITION_ID
    else:
        competition_id = comp.id
        _print(
            f"OK: Discovered competition '{comp.name}' "
            f"(id={comp.id}, country={comp.category.country_code})."
        )

    seasons = await comp_svc.list_seasons(competition_id)
    if not seasons:
        _print(
            f"WARN: list_seasons returned no rows for {competition_id}; "
            f"falling back to {FALLBACK_SEASON_ID}."
        )
        return competition_id, FALLBACK_SEASON_ID, ""
    current = seasons[0]
    _print(
        f"OK: Using season '{current.name}' (id={current.id}, "
        f"start={current.start_date}). {len(seasons)} seasons available."
    )
    return competition_id, current.id, current.start_date


async def _run_sync(client: SportradarClient, season_id: str) -> int:
    """Run sync_all_profiles + per-profile upsert. Return rc."""
    rc = 0
    team_svc = TeamSyncService(client)
    _print(f"Fetching competitor list + profiles for season {season_id} …")
    try:
        profiles = await team_svc.sync_all_profiles(season_id)
    except SportradarError as exc:
        _print(f"FAIL: Sportradar error during sync_all_profiles: {exc}")
        return 3
    except Exception as exc:
        _print(f"FAIL: unexpected error during sync_all_profiles: {exc!r}")
        return 3
    _print(f"OK: fetched {len(profiles)} team profiles.")

    if not profiles:
        _print("WARN: zero profiles to persist; nothing to do.")
        return 0

    # Persist via async session.
    persisted = 0
    async with async_session() as session:
        try:
            for prof in profiles:
                await repo.upsert_profile(session, prof)
                persisted += 1
            await session.commit()
        except Exception as exc:
            await session.rollback()
            _print(f"FAIL: DB error during upsert: {exc!r}")
            return 3
    _print(f"OK: persisted {persisted}/{len(profiles)} profiles to sr_teams + sr_players.")

    # Verify counts.
    async with async_session() as session:
        team_count = (await session.execute(select(func.count(SrTeam.id)))).scalar_one()
        player_count = (await session.execute(select(func.count(SrPlayer.id)))).scalar_one()
        ucluj_row = (
            await session.execute(
                select(SrTeam.id, SrTeam.name).where(
                    func.lower(SrTeam.name).like("%universitatea cluj%")
                )
            )
        ).first()
    _print(f"Verified: sr_teams = {team_count} rows, sr_players = {player_count} rows.")
    if ucluj_row is not None:
        ucluj_id = ucluj_row[0]
        async with async_session() as session:
            ucluj_squad = (
                await session.execute(
                    select(func.count(SrPlayer.id)).where(SrPlayer.team_id == ucluj_id)
                )
            ).scalar_one()
        _print(
            f"FC Universitatea Cluj: id={ucluj_id}, "
            f"name='{ucluj_row[1]}', squad size = {ucluj_squad}."
        )
    else:
        _print("WARN: No sr_teams row matched 'Universitatea Cluj' — sync ran but "
               "the team is missing from the season's competitor list.")
        rc = 3
    return rc


async def _main() -> int:
    _print("Sportradar squad sync — FC Universitatea Cluj")
    client = SportradarClient()
    if not await _smoke_test_key(client):
        return 1

    competition_id, season_id, season_start = await _resolve_season_id(client)
    _ = competition_id  # competition_id is logged but not used beyond discovery.
    _ = season_start

    _print("Initialising local DB schema (idempotent) …")
    try:
        await init_db()
    except Exception as exc:
        _print(f"WARN: init_db raised {exc!r}; assuming schema already exists.")

    rc = await _run_sync(client, season_id)

    # Best-effort: close the engine cleanly so the SQLite connection releases.
    try:
        await engine.dispose()
    except Exception:
        pass
    return rc


def main() -> int:
    try:
        return asyncio.run(_main())
    except KeyboardInterrupt:
        _print("Interrupted by user.")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
