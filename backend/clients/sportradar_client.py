from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

_last_request_time: float = 0.0


class SportradarError(Exception):
    def __init__(self, status: int, detail: str):
        self.status = status
        self.detail = detail
        super().__init__(f"Sportradar {status}: {detail}")


class SportradarClient:

    def __init__(self):
        self._base = settings.sportradar_base_url.rstrip("/")
        self._key = settings.sportradar_api_key
        self._delay = settings.sportradar_rate_delay
        self._timeout = 15.0
        self._max_retries = 3

    async def _throttle(self):
        global _last_request_time
        now = time.monotonic()
        elapsed = now - _last_request_time
        if elapsed < self._delay:
            await asyncio.sleep(self._delay - elapsed)
        _last_request_time = time.monotonic()

    async def get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any] | None:
        url = f"{self._base}/{path.lstrip('/')}"
        all_params = {"api_key": self._key, **(params or {})}

        for attempt in range(1, self._max_retries + 1):
            await self._throttle()
            try:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    resp = await client.get(url, params=all_params)

                logger.info("SR %s %s -> %d", "GET", path, resp.status_code)

                if resp.status_code == 200:
                    return resp.json()

                if resp.status_code == 404:
                    logger.warning("SR 404: %s (resource not found)", path)
                    return None

                if resp.status_code == 403:
                    logger.error("SR 403: access denied for %s", path)
                    raise SportradarError(403, "Access denied — check API key and access level")

                if resp.status_code == 429 or resp.status_code >= 500:
                    wait = 2 ** attempt
                    logger.warning("SR %d on %s, retry %d/%d in %ds", resp.status_code, path, attempt, self._max_retries, wait)
                    await asyncio.sleep(wait)
                    continue

                raise SportradarError(resp.status_code, resp.text[:200])

            except httpx.TimeoutException:
                logger.warning("SR timeout on %s, attempt %d/%d", path, attempt, self._max_retries)
                if attempt == self._max_retries:
                    return None
                await asyncio.sleep(2 ** attempt)
            except httpx.RequestError as exc:
                logger.error("SR request error on %s: %s", path, exc)
                if attempt == self._max_retries:
                    return None
                await asyncio.sleep(2 ** attempt)

        return None

    # -- convenience shortcuts --

    async def competitions(self) -> dict | None:
        return await self.get("competitions.json")

    async def competition_seasons(self, competition_id: str) -> dict | None:
        cid = competition_id.replace(":", "%3A")
        return await self.get(f"competitions/{cid}/seasons.json")

    async def season_info(self, season_id: str) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/info.json")

    async def season_competitors(self, season_id: str) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/competitors.json")

    async def season_schedules(self, season_id: str) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/schedules.json")

    async def season_standings(self, season_id: str) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/standings.json")

    async def season_summaries(self, season_id: str, offset: int = 0, limit: int = 200) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/summaries.json", params={"offset": offset, "limit": limit})

    async def competitor_profile(self, competitor_id: str) -> dict | None:
        cid = competitor_id.replace(":", "%3A")
        return await self.get(f"competitors/{cid}/profile.json")

    async def sport_event_summary(self, event_id: str) -> dict | None:
        eid = event_id.replace(":", "%3A")
        return await self.get(f"sport_events/{eid}/summary.json")

    async def sport_event_lineups(self, event_id: str) -> dict | None:
        eid = event_id.replace(":", "%3A")
        return await self.get(f"sport_events/{eid}/lineups.json")

    async def sport_event_timeline(self, event_id: str) -> dict | None:
        eid = event_id.replace(":", "%3A")
        return await self.get(f"sport_events/{eid}/timeline.json")

    async def daily_schedules(self, date_iso: str) -> dict | None:
        """date_iso: YYYY-MM-DD — `/schedules/{date}/schedules.json`"""
        return await self.get(f"schedules/{date_iso}/schedules.json")

    async def competitor_schedules(self, competitor_id: str) -> dict | None:
        cid = competitor_id.replace(":", "%3A")
        return await self.get(f"competitors/{cid}/schedules.json")

    async def season_lineups(self, season_id: str, offset: int = 0, limit: int = 200) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/lineups.json", params={"offset": offset, "limit": limit})

    async def competitor_vs_competitor(self, comp1: str, comp2: str) -> dict | None:
        c1 = comp1.replace(":", "%3A")
        c2 = comp2.replace(":", "%3A")
        return await self.get(f"competitors/{c1}/vs/{c2}/summaries.json")

    async def season_leaders(self, season_id: str) -> dict | None:
        sid = season_id.replace(":", "%3A")
        return await self.get(f"seasons/{sid}/leaders.json")
