from __future__ import annotations

import logging

import httpx

from clients.sportradar_client import SportradarClient
from sportradar.schemas import CoverageReport, FeedProbeResult, SRSeasonCoverage
from sportradar.services.competition_sync import CompetitionSyncService, get_discovered_id

logger = logging.getLogger(__name__)

FEED_CATALOG: list[tuple[str, str, str, str]] = [
    # (feed_name, path_template, data_key, umbraro_relevance)
    (
        "season_info",
        "seasons/{sid}/info.json",
        "season",
        "CRITICAL, confirms coverage tier and available data types for this season",
    ),
    (
        "season_competitors",
        "seasons/{sid}/competitors.json",
        "season_competitors",
        "CRITICAL, provides all teams in the league, needed for standings/fixtures/dashboard",
    ),
    (
        "season_schedules",
        "seasons/{sid}/schedules.json",
        "schedules",
        "CRITICAL, full fixture list for the season, needed for calendar/fixture screens",
    ),
    (
        "season_standings",
        "seasons/{sid}/standings.json",
        "standings",
        "HIGH, league table data, drives the standings screen",
    ),
    (
        "season_summaries",
        "seasons/{sid}/summaries.json",
        "summaries",
        "HIGH, bulk match results and stats, useful for batch syncing completed fixtures",
    ),
    (
        "season_lineups",
        "seasons/{sid}/lineups.json",
        "lineups",
        "MEDIUM, season-wide lineups, useful for team/match detail screens",
    ),
    (
        "season_leaders",
        "seasons/{sid}/leaders.json",
        "lists",
        "LOW, top scorers/assists, nice-to-have for analytics but not core to UmbraRo",
    ),
]


class CoverageValidationService:

    def __init__(self, client: SportradarClient):
        self._client = client

    async def validate_season(self, season_id: str) -> CoverageReport:
        comp_svc = CompetitionSyncService(self._client)
        coverage = await comp_svc.season_coverage(season_id)

        sid_enc = season_id.replace(":", "%3A")
        probes: list[FeedProbeResult] = []
        summary: dict[str, bool] = {}

        for feed_name, path_tmpl, data_key, relevance in FEED_CATALOG:
            path = path_tmpl.format(sid=sid_enc)
            result = await self._probe(path, data_key)
            result.feed_name = feed_name
            result.umbraro_relevance = relevance
            probes.append(result)
            summary[feed_name] = result.available

        # Probe one competitor profile if teams are available
        teams_probe = next((p for p in probes if p.feed_name == "season_competitors"), None)
        if teams_probe and teams_probe.available:
            import asyncio
            await asyncio.sleep(1.2)
            data = await self._client.season_competitors(season_id)
            first_team = (data or {}).get("season_competitors", [{}])[0] if data else {}
            team_id = first_team.get("id", "")
            if team_id:
                tid_enc = team_id.replace(":", "%3A")

                profile_r = await self._probe(f"competitors/{tid_enc}/profile.json", "competitor")
                profile_r.feed_name = "competitor_profile"
                profile_r.umbraro_relevance = "HIGH, team venue, manager, full squad roster"
                probes.append(profile_r)
                summary["competitor_profile"] = profile_r.available

                sched_r = await self._probe(f"competitors/{tid_enc}/schedules.json", "schedules")
                sched_r.feed_name = "competitor_schedule"
                sched_r.umbraro_relevance = "MEDIUM, team-specific past/future matches"
                probes.append(sched_r)
                summary["competitor_schedule"] = sched_r.available

        # Probe one closed match if fixtures are available
        sched_probe = next((p for p in probes if p.feed_name == "season_schedules"), None)
        if sched_probe and sched_probe.available:
            import asyncio
            await asyncio.sleep(1.2)
            sched_data = await self._client.season_schedules(season_id)
            closed = [
                e for e in (sched_data or {}).get("schedules", [])
                if e.get("sport_event_status", {}).get("status") == "closed"
            ]
            if closed:
                eid = closed[0].get("sport_event", {}).get("id", "")
                if eid:
                    eid_enc = eid.replace(":", "%3A")

                    sum_r = await self._probe(f"sport_events/{eid_enc}/summary.json", "sport_event_status")
                    sum_r.feed_name = "sport_event_summary"
                    sum_r.umbraro_relevance = "CRITICAL, per-match stats (possession, shots, corners) used by the ML model"
                    probes.append(sum_r)
                    summary["sport_event_summary"] = sum_r.available

                    lin_r = await self._probe(f"sport_events/{eid_enc}/lineups.json", "lineups")
                    lin_r.feed_name = "sport_event_lineups"
                    lin_r.umbraro_relevance = "MEDIUM, starting XI and formations for match detail view"
                    probes.append(lin_r)
                    summary["sport_event_lineups"] = lin_r.available

        available_count = sum(1 for v in summary.values() if v)
        logger.info("Coverage: %d/%d feeds available for %s", available_count, len(summary), season_id)

        return CoverageReport(
            season_id=season_id,
            competition_id=get_discovered_id() or "",
            coverage_info=coverage,
            feed_probes=probes,
            summary=summary,
        )

    async def _probe(self, path: str, data_key: str) -> FeedProbeResult:
        try:
            import asyncio
            await asyncio.sleep(1.2)

            url = f"{self._client._base}/{path}"
            headers = {"x-api-key": self._client._key}

            async with httpx.AsyncClient(timeout=15.0) as http:
                resp = await http.get(url, headers=headers)

            if resp.status_code == 200:
                body = resp.json()
                count = None
                val = body.get(data_key)
                if isinstance(val, list):
                    count = len(val)
                elif isinstance(val, dict):
                    count = 1
                return FeedProbeResult(
                    feed_name="",
                    endpoint=path,
                    available=True,
                    status_code=200,
                    record_count=count,
                )

            return FeedProbeResult(
                feed_name="",
                endpoint=path,
                available=False,
                status_code=resp.status_code,
                error="Not found" if resp.status_code == 404 else resp.text[:200],
            )
        except Exception as exc:
            return FeedProbeResult(
                feed_name="",
                endpoint=path,
                available=False,
                error=str(exc)[:200],
            )
