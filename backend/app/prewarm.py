"""Startup pre-warm for the Sportradar-backed endpoints and the local ML paths.

App Runner instances are ephemeral, so the on-disk response caches used by the
week-fixtures and standings endpoints start COLD on every cold start (a new
deployment, an App Runner resume, or an autoscale event). On a cold cache the
first dashboard load fires five parallel week requests plus a standings
request, all of which try to fetch the full season schedule at once; the trial
Sportradar tier answers the burst with 429s and the client times out, which is
the ``ApiException(408)`` the UI shows on first load.

This module fetches the season schedule and the standings ONCE when the
container boots and writes them into those same cache files, so the cache is
already warm before the first user request arrives. It is:

* best-effort: every failure is logged and swallowed (the endpoints still fetch
  on their own and fall back to the CSV), so it can never break startup;
* idempotent: it skips a cache that is already fresh;
* non-blocking: ``main.lifespan`` schedules it as a background task, so it never
  delays startup or the App Runner health check.

The season is resolved inside the endpoint helpers via ``effective_season_id()``
(demo or production), so the pre-warm needs no mode-specific logic.
"""
from __future__ import annotations

import asyncio
import logging

from app.config import effective_season, settings
from services.fixture_service import FixtureService

logger = logging.getLogger(__name__)

# Generous: the trial tier retries 429 a few times before succeeding.
_TIMEOUT = 25.0


async def _warm_fixtures() -> None:
    # Imported lazily so this module has no import-time dependency on the
    # endpoint graph (avoids any circular-import risk at app load).
    from api.v1.endpoints import week

    if week._load_cache() is not None:
        return  # already warm
    sr = await asyncio.wait_for(week._fetch_all_sr_fixtures(), timeout=_TIMEOUT)
    if sr:
        week._save_cache(sr)
        logger.info("Pre-warm: cached %d Sportradar fixtures", len(sr))
    else:
        logger.info("Pre-warm: Sportradar returned no fixtures; cache left cold")


async def _warm_standings(df, stadium_map: dict) -> None:
    from api.v1.endpoints import standings

    if standings._load_cache() is not None:
        return  # already warm
    sr_data = await asyncio.wait_for(standings._fetch_sr_standings(), timeout=_TIMEOUT)
    if not sr_data:
        logger.info("Pre-warm: Sportradar returned no standings; cache left cold")
        return
    regular = sr_data.get("regular") or []
    championship = sr_data.get("championship") or []
    relegation = sr_data.get("relegation") or []
    # Mirror the endpoint: when Sportradar serves the regular table but not the
    # playoff groups, backfill them from the CSV so the GRUPA CAMPIONAT /
    # GRUPA RETROGRADARE tabs are populated from the cache too.
    if regular and (not championship or not relegation):
        svc = FixtureService(df, stadium_map)
        csv_groups = svc.standings_with_groups(season=effective_season())
        if not championship:
            championship = csv_groups.get("championship") or []
        if not relegation:
            relegation = csv_groups.get("relegation") or []
    standings._save_cache({
        "regular": regular,
        "championship": championship,
        "relegation": relegation,
    })
    logger.info("Pre-warm: cached standings (regular=%d)", len(regular))


async def _warm_model(df, bundle) -> None:
    """Exercise the CatBoost win-probability path once (feature build + predict).

    This is what ``/week-fixtures`` runs per fixture; warming it loads the native
    CatBoost predictor and the feature pipeline so the first request is cheap.
    """
    if bundle is None:
        return
    from services.model_service import ModelService
    from services.feature_service import FeatureService

    model_svc = ModelService(bundle)
    if not model_svc.is_ready:
        return
    feat = FeatureService(df).build_feature_vector(
        "U Cluj", "FCSB", model_svc.feature_cols
    )
    await asyncio.to_thread(model_svc.predict_proba, feat)
    logger.info("Pre-warm: CatBoost win-probability path ready")


async def _warm_week(df, stadium_map: dict, bundle) -> None:
    """Pre-compute the current week's dashboard predictions into the in-process
    cache so the first /week-fixtures load is instant.

    /week-fixtures is otherwise the heaviest endpoint: it runs a Monte Carlo
    prescription per upcoming fixture. week.py memoises the result, so a single
    warm here makes the panel return immediately for the first user.
    """
    from api.v1.endpoints.week import _compute_week

    await _compute_week(df, stadium_map, bundle, 0)
    logger.info("Pre-warm: week-fixtures predictions cached (current week)")


async def _warm_xi(xi_service) -> None:
    """Exercise the XI match-preview path once (the heaviest cold cost).

    The first ``match_preview`` lazily builds the Wyscout feature dataset
    (``build_dataset_from_files`` over the whole drive_cache) and caches it on
    the service, then runs the supervised lineup model + Hungarian assignment.
    Running it once at boot moves that one-time build off the first user's
    request clock. The opponent is arbitrary; the expensive home-squad feature
    build runs regardless. It is sync + CPU-bound, so run it in a worker thread.
    """
    if xi_service is None:
        return
    await asyncio.to_thread(xi_service.match_preview, "FCSB", "4-3-3")
    logger.info("Pre-warm: XI match-preview path ready")


async def prewarm_caches(df, stadium_map: dict, xi_service=None, bundle=None) -> None:
    """Warm the Sportradar caches and the local ML inference paths once at boot.

    Best-effort and self-contained: a failure in one warm does not stop the
    others, and none can propagate out of this coroutine.
    """
    # 1. Sportradar-backed caches (dashboard + standings): the first-screen
    #    429 -> 408 burst. Needs the trial key; skipped when it is absent.
    if settings.sportradar_api_key:
        try:
            await _warm_fixtures()
        except Exception as exc:  # noqa: BLE001 - never let pre-warm break boot
            logger.warning("Pre-warm fixtures failed (non-fatal): %s", exc)
        try:
            await _warm_standings(df, stadium_map)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Pre-warm standings failed (non-fatal): %s", exc)

    # 2. Local ML inference paths (no Sportradar dependency): the CatBoost
    #    win-probability path and, most importantly, the XI match-preview path,
    #    whose first call builds the Wyscout feature dataset.
    try:
        await _warm_model(df, bundle)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Pre-warm model failed (non-fatal): %s", exc)
    try:
        await _warm_week(df, stadium_map, bundle)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Pre-warm week predictions failed (non-fatal): %s", exc)
    try:
        await _warm_xi(xi_service)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Pre-warm XI failed (non-fatal): %s", exc)
