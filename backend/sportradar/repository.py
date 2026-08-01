from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from sportradar.db_models import (
    SrCompetition,
    SrFixture,
    SrLineup,
    SrMatchStats,
    SrPlayer,
    SrSeason,
    SrSeasonCoverage,
    SrStanding,
    SrSyncLog,
    SrTeam,
    SrTimelineEvent,
)
from sportradar.schemas import (
    NormalizedCompetitorProfile,
    NormalizedFixture,
    NormalizedLineup,
    NormalizedMatchStats,
    NormalizedStandingsRow,
    NormalizedTeam,
    NormalizedTimelineEvent,
    SRCompetition,
    SRSeason,
    SRSeasonCoverage,
)

logger = logging.getLogger(__name__)


async def log_sync(
    session: AsyncSession,
    entity_type: str,
    entity_id: str,
    operation: str,
    record_count: int,
    status: str = "ok",
    error: str = "",
):
    entry = SrSyncLog(
        entity_type=entity_type,
        entity_id=entity_id,
        operation=operation,
        record_count=record_count,
        status=status,
        error_message=error,
        synced_at=datetime.now(timezone.utc),
    )
    session.add(entry)
    await session.flush()


# COMPETITION

async def upsert_competition(session: AsyncSession, comp: SRCompetition):
    existing = await session.get(SrCompetition, comp.id)
    if existing:
        existing.name = comp.name
        existing.category_name = comp.category.name
        existing.country_code = comp.category.country_code
        existing.gender = comp.gender
    else:
        session.add(SrCompetition(
            id=comp.id,
            name=comp.name,
            category_name=comp.category.name,
            country_code=comp.category.country_code,
            gender=comp.gender,
        ))
    await log_sync(session, "competition", comp.id, "upsert", 1)


# SEASONS

async def upsert_seasons(session: AsyncSession, seasons: list[SRSeason]):
    for s in seasons:
        existing = await session.get(SrSeason, s.id)
        if existing:
            existing.name = s.name
            existing.start_date = s.start_date
            existing.end_date = s.end_date
            existing.year = s.year
            existing.competition_id = s.competition_id
        else:
            session.add(SrSeason(
                id=s.id,
                competition_id=s.competition_id,
                name=s.name,
                start_date=s.start_date,
                end_date=s.end_date,
                year=s.year,
            ))
    await log_sync(session, "seasons", seasons[0].competition_id if seasons else "", "upsert", len(seasons))


# SEASON COVERAGE

async def upsert_season_coverage(
    session: AsyncSession,
    cov: SRSeasonCoverage,
    raw: dict | None = None,
):
    raw_json = ""
    if raw is not None:
        try:
            raw_json = json.dumps(raw)[:16000]
        except (TypeError, ValueError):
            raw_json = ""

    existing = await session.get(SrSeasonCoverage, cov.season_id)
    if existing:
        existing.competition_id = cov.competition_id
        existing.max_coverage_level = cov.max_coverage_level
        existing.max_covered_matches = cov.max_covered_matches
        existing.scheduled_matches = cov.scheduled_matches
        existing.players_statistics = cov.players_statistics
        existing.team_statistics = cov.team_statistics
        existing.lineups = cov.lineups
        existing.squads = cov.squads
        existing.transfers = cov.transfers
        existing.missing_players = cov.missing_players
        existing.raw_json = raw_json
        existing.synced_at = datetime.now(timezone.utc)
    else:
        session.add(SrSeasonCoverage(
            season_id=cov.season_id,
            competition_id=cov.competition_id,
            max_coverage_level=cov.max_coverage_level,
            max_covered_matches=cov.max_covered_matches,
            scheduled_matches=cov.scheduled_matches,
            players_statistics=cov.players_statistics,
            team_statistics=cov.team_statistics,
            lineups=cov.lineups,
            squads=cov.squads,
            transfers=cov.transfers,
            missing_players=cov.missing_players,
            raw_json=raw_json,
            synced_at=datetime.now(timezone.utc),
        ))
    await log_sync(session, "season_coverage", cov.season_id, "upsert", 1)


# TEAMS

async def upsert_teams(session: AsyncSession, teams: list[NormalizedTeam]):
    for t in teams:
        existing = await session.get(SrTeam, t.sr_id)
        if existing:
            existing.name = t.name
            existing.short_name = t.short_name
            existing.abbreviation = t.abbreviation
            existing.country = t.country
            existing.country_code = t.country_code
            existing.venue_id = t.venue_id or existing.venue_id
            existing.venue_name = t.venue_name
            existing.manager_name = t.manager_name
            if t.logo_url:
                existing.logo_url = t.logo_url
        else:
            session.add(SrTeam(
                id=t.sr_id,
                name=t.name,
                short_name=t.short_name,
                abbreviation=t.abbreviation,
                country=t.country,
                country_code=t.country_code,
                venue_id=t.venue_id,
                venue_name=t.venue_name,
                manager_name=t.manager_name,
                logo_url=t.logo_url,
            ))
    await log_sync(session, "teams", "", "upsert", len(teams))


# PROFILES (team + players)

async def upsert_profile(session: AsyncSession, profile: NormalizedCompetitorProfile):
    existing = await session.get(SrTeam, profile.sr_id)
    venue = profile.venue
    manager = profile.manager
    venue_id = venue.id if venue else ""
    vals = dict(
        name=profile.name,
        short_name=profile.short_name,
        abbreviation=profile.abbreviation,
        country=profile.country,
        country_code=profile.country_code,
        venue_id=venue_id,
        venue_name=venue.name if venue else "",
        venue_city=venue.city_name if venue else "",
        venue_capacity=venue.capacity if venue else None,
        manager_name=manager.name if manager else "",
        squad_size=len(profile.players),
        logo_url=profile.logo_url,
    )
    if existing:
        for k, v in vals.items():
            setattr(existing, k, v)
    else:
        session.add(SrTeam(id=profile.sr_id, **vals))

    # Upsert players
    for p in profile.players:
        ep = await session.get(SrPlayer, p.sr_id)
        if ep:
            ep.team_id = profile.sr_id
            ep.name = p.name
            ep.position = p.type
            ep.nationality = p.nationality
            ep.date_of_birth = p.date_of_birth
            ep.height = p.height
            ep.weight = p.weight
            ep.jersey_number = p.jersey_number
        else:
            session.add(SrPlayer(
                id=p.sr_id,
                team_id=profile.sr_id,
                name=p.name,
                position=p.type,
                nationality=p.nationality,
                date_of_birth=p.date_of_birth,
                height=p.height,
                weight=p.weight,
                jersey_number=p.jersey_number,
            ))

    await log_sync(session, "profile", profile.sr_id, "upsert", 1 + len(profile.players))


# FIXTURES

async def upsert_fixtures(session: AsyncSession, fixtures: list[NormalizedFixture]):
    for f in fixtures:
        existing = await session.get(SrFixture, f.sr_id)
        if existing:
            existing.season_id = f.season_id
            existing.scheduled = f.scheduled
            existing.status = f.status
            existing.home_team_id = f.home_team_id
            existing.home_team_name = f.home_team_name
            existing.away_team_id = f.away_team_id
            existing.away_team_name = f.away_team_name
            existing.home_score = f.home_score
            existing.away_score = f.away_score
            existing.venue_name = f.venue_name
            existing.round_number = f.round_number
            existing.matchday = f.matchday
        else:
            session.add(SrFixture(
                id=f.sr_id,
                season_id=f.season_id,
                scheduled=f.scheduled,
                status=f.status,
                home_team_id=f.home_team_id,
                home_team_name=f.home_team_name,
                away_team_id=f.away_team_id,
                away_team_name=f.away_team_name,
                home_score=f.home_score,
                away_score=f.away_score,
                venue_name=f.venue_name,
                round_number=f.round_number,
                matchday=f.matchday,
            ))
    sid = fixtures[0].season_id if fixtures else ""
    await log_sync(session, "fixtures", sid, "upsert", len(fixtures))


# STANDINGS

async def upsert_all_standings(
    session: AsyncSession,
    season_id: str,
    groups: dict[str, list[NormalizedStandingsRow]],
):
    await session.execute(delete(SrStanding).where(SrStanding.season_id == season_id))
    now = datetime.now(timezone.utc)
    total = 0
    for rows in groups.values():
        for r in rows:
            session.add(SrStanding(
                season_id=season_id,
                group_name=r.group_name,
                group_id=r.group_id,
                team_id=r.team_id,
                team_name=r.team_name,
                rank=r.rank,
                played=r.played,
                wins=r.wins,
                draws=r.draws,
                losses=r.losses,
                goals_for=r.goals_for,
                goals_against=r.goals_against,
                goal_diff=r.goal_diff,
                points=r.points,
                form=r.form,
                synced_at=now,
            ))
            total += 1
    await log_sync(session, "standings", season_id, "replace", total)


# MATCH STATS

async def upsert_match_stats(session: AsyncSession, fixture_id: str, stats: list[NormalizedMatchStats]):
    await session.execute(delete(SrMatchStats).where(SrMatchStats.fixture_id == fixture_id))
    for s in stats:
        session.add(SrMatchStats(
            fixture_id=fixture_id,
            team_id=s.team_id,
            team_name=s.team_name,
            ball_possession=s.ball_possession,
            shots_total=s.shots_total,
            shots_on_target=s.shots_on_target,
            corner_kicks=s.corner_kicks,
            fouls=s.fouls,
            yellow_cards=s.yellow_cards,
            red_cards=s.red_cards,
            offsides=s.offsides,
            free_kicks=s.free_kicks,
            goal_kicks=s.goal_kicks,
            throw_ins=s.throw_ins,
        ))
    await log_sync(session, "match_stats", fixture_id, "replace", len(stats))


# LINEUPS

async def upsert_lineups(session: AsyncSession, fixture_id: str, lineups: list[NormalizedLineup]):
    await session.execute(delete(SrLineup).where(SrLineup.fixture_id == fixture_id))
    for lu in lineups:
        players_data = [p.model_dump() for p in lu.players]
        session.add(SrLineup(
            fixture_id=fixture_id,
            team_id=lu.team_id,
            team_name=lu.team_name,
            formation=lu.formation,
            players_json=json.dumps(players_data),
        ))
    await log_sync(session, "lineups", fixture_id, "replace", len(lineups))


# TIMELINE

async def upsert_timeline_events(
    session: AsyncSession,
    fixture_id: str,
    events: list[NormalizedTimelineEvent],
):
    await session.execute(delete(SrTimelineEvent).where(SrTimelineEvent.fixture_id == fixture_id))
    now = datetime.now(timezone.utc)
    for ev in events:
        session.add(SrTimelineEvent(
            fixture_id=fixture_id,
            event_id=ev.event_id,
            event_type=ev.event_type,
            minute=ev.minute,
            team_id=ev.team_id,
            player_name=ev.player_name,
            detail=ev.detail,
            synced_at=now,
        ))
    await log_sync(session, "timeline", fixture_id, "replace", len(events))
