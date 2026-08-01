from __future__ import annotations

import logging

from clients.sportradar_client import SportradarClient
from sportradar.schemas import (
    NormalizedCompetitorProfile,
    NormalizedPlayer,
    NormalizedTeam,
    SRJersey,
    SRManager,
    SRVenue,
)

logger = logging.getLogger(__name__)


def _logo_url_from_competitor(comp: dict) -> str:
    logo = comp.get("logo")
    if isinstance(logo, str):
        return logo
    if isinstance(logo, dict):
        return str(logo.get("href") or logo.get("url") or "")
    return ""


class TeamSyncService:

    def __init__(self, client: SportradarClient):
        self._client = client

    async def sync_competitor_profile(self, competitor_id: str) -> NormalizedCompetitorProfile | None:
        data = await self._client.competitor_profile(competitor_id)
        if not data:
            return None

        comp = data.get("competitor", {})
        venue_raw = comp.get("venue", {})
        mgr_raw = comp.get("manager", {})
        jerseys_raw = comp.get("jerseys", [])
        players_raw = data.get("players", [])

        venue = SRVenue(
            id=venue_raw.get("id", ""),
            name=venue_raw.get("name", ""),
            city_name=venue_raw.get("city_name", ""),
            country_name=venue_raw.get("country_name", ""),
            capacity=venue_raw.get("capacity"),
        ) if venue_raw else None

        manager = SRManager(
            id=mgr_raw.get("id", ""),
            name=mgr_raw.get("name", ""),
            nationality=mgr_raw.get("nationality", ""),
        ) if mgr_raw.get("id") else None

        jerseys = [
            SRJersey(
                type=j.get("type", ""),
                base=j.get("base", ""),
                sleeve=j.get("sleeve", ""),
                number=j.get("number", ""),
            )
            for j in jerseys_raw
        ]

        players = [
            NormalizedPlayer(
                sr_id=p.get("id", ""),
                name=p.get("name", ""),
                type=p.get("type", ""),
                nationality=p.get("nationality", ""),
                date_of_birth=p.get("date_of_birth", ""),
                height=p.get("height"),
                weight=p.get("weight"),
                jersey_number=p.get("jersey_number"),
            )
            for p in players_raw
        ]

        profile = NormalizedCompetitorProfile(
            sr_id=comp.get("id", competitor_id),
            name=comp.get("name", ""),
            short_name=comp.get("short_name", ""),
            abbreviation=comp.get("abbreviation", ""),
            country=comp.get("country", ""),
            country_code=comp.get("country_code", ""),
            logo_url=_logo_url_from_competitor(comp),
            venue=venue,
            manager=manager,
            jerseys=jerseys,
            players=players,
        )

        logger.info(
            "Profile synced: %s, %d players, venue=%s, manager=%s",
            profile.name,
            len(players),
            profile.venue.name if profile.venue else "N/A",
            profile.manager.name if profile.manager else "N/A",
        )
        return profile

    async def sync_all_profiles(self, season_id: str) -> list[NormalizedCompetitorProfile]:
        data = await self._client.season_competitors(season_id)
        if not data:
            return []

        team_ids = [t.get("id", "") for t in data.get("season_competitors", []) if t.get("id")]
        logger.info("Syncing profiles for %d teams in season %s", len(team_ids), season_id)

        profiles: list[NormalizedCompetitorProfile] = []
        for tid in team_ids:
            profile = await self.sync_competitor_profile(tid)
            if profile:
                profiles.append(profile)

        return profiles

    async def sync_competitor_schedule(self, competitor_id: str) -> list[dict]:
        data = await self._client.competitor_schedules(competitor_id)
        if not data:
            return []

        events = []
        for item in data.get("schedules", []):
            se = item.get("sport_event", {})
            status = item.get("sport_event_status", {})
            competitors = se.get("competitors", [])
            home = next((c for c in competitors if c.get("qualifier") == "home"), {})
            away = next((c for c in competitors if c.get("qualifier") == "away"), {})

            events.append({
                "id": se.get("id", ""),
                "scheduled": se.get("scheduled", ""),
                "status": status.get("status", ""),
                "home_team": home.get("name", ""),
                "away_team": away.get("name", ""),
                "home_score": status.get("home_score"),
                "away_score": status.get("away_score"),
            })

        logger.info("Competitor schedule: %d events for %s", len(events), competitor_id)
        return events
