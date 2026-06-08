from __future__ import annotations

from datetime import datetime

import pandas as pd
import numpy as np

from app.config import effective_now, settings


# Regular-season cutoff dates per SuperLiga season. Used by
# ``standings_with_groups`` to split the league into Championship Round
# (top 6) and Relegation Round (bottom 10). The Romanian Superliga
# regular season ends around the start of March; playoffs begin mid-March.
_REGULAR_SEASON_CUTOFFS: dict[str, str] = {
    "2024": "2025-03-10",
    "2025": "2026-03-08",
}


class FixtureService:

    def __init__(self, df: pd.DataFrame, stadium_map: dict[str, str]):
        self._df = df
        self._stadium_map = stadium_map
        self._tracked = settings.tracked_team

    def list_fixtures(self, team: str | None = None, season: str | None = None, limit: int = 20) -> list[dict]:
        df = self._df.copy()
        if team:
            df = df[(df["home_team"] == team) | (df["away_team"] == team)]
        if season:
            df = df[df["season"].astype(str) == str(season)]
        df = df.sort_values("match_date", ascending=False).head(limit)
        return [self._row_to_fixture(r) for _, r in df.iterrows()]

    def fixture_detail(self, match_id: str) -> dict | None:
        row = self._df[self._df["match_id"] == match_id]
        if row.empty:
            return None
        return self._row_to_fixture(row.iloc[0])

    def recent_fixtures(self, team: str, n: int = 5) -> list[dict]:
        df = self._df[(self._df["home_team"] == team) | (self._df["away_team"] == team)]
        completed = df.dropna(subset=["home_score", "away_score"])
        # In demo mode, "recent" means completed fixtures up to the demo date.
        if settings.demo_mode:
            now_iso = effective_now().isoformat()
            completed = completed[completed["match_date"].astype(str) <= now_iso]
            completed = completed.sort_values("match_date", ascending=True)
        return [self._row_to_fixture(r) for _, r in completed.tail(n).iterrows()]

    def upcoming_fixtures(self, team: str, n: int = 3) -> list[dict]:
        df = self._df[(self._df["home_team"] == team) | (self._df["away_team"] == team)]

        # In demo mode, "upcoming" means scheduled after the demo date,
        # regardless of whether the result is in the dataset, because the
        # 2024-2025 season is fully scored. The score field stays populated so
        # downstream consumers that read it for a tactical retrospective still
        # work; demo presentation simply treats them as forthcoming.
        if settings.demo_mode:
            now_iso = effective_now().isoformat()
            future = df[df["match_date"].astype(str) > now_iso].sort_values("match_date", ascending=True)
            return [self._row_to_fixture(r) for _, r in future.head(n).iterrows()]

        upcoming = df[df["home_score"].isna()]

        # Return the real upcoming fixtures only (possibly empty). The demo
        # path above already populates the committee view; production no longer
        # injects a synthetic placeholder match.
        return [self._row_to_fixture(r) for _, r in upcoming.head(n).iterrows()]

    def standings(self, season: str | None = None) -> list[dict]:
        df = self._df.copy()
        if season:
            df = df[df["season"].astype(str) == str(season)]
        return self._build_standings(df)

    def list_week_fixtures(
        self,
        monday: datetime,
        sunday: datetime,
        season: str | None = None,
    ) -> list[dict]:
        """Return every CSV fixture inside ``[monday, sunday)`` for ``season``.

        Used by the week-fixtures endpoint's CSV fallback so the dashboard's
        "Alte meciuri" section populates with non-U-Cluj matches when
        Sportradar is unavailable. Sorted ascending by match_date.
        """
        df = self._df.copy()
        if season:
            df = df[df["season"].astype(str) == str(season)]
        dt = pd.to_datetime(df["match_date"], errors="coerce", utc=True)
        monday_ts = pd.Timestamp(monday).tz_convert("UTC") if pd.Timestamp(monday).tzinfo else pd.Timestamp(monday).tz_localize("UTC")
        sunday_ts = pd.Timestamp(sunday).tz_convert("UTC") if pd.Timestamp(sunday).tzinfo else pd.Timestamp(sunday).tz_localize("UTC")
        mask = (dt >= monday_ts) & (dt < sunday_ts)
        window = df[mask].sort_values("match_date", ascending=True)
        return [self._row_to_fixture(r) for _, r in window.iterrows()]

    def standings_with_groups(self, season: str | None = None) -> dict:
        """Return a three-bucket standings dict for the given season.

        ``regular``: the full 16-team table as it stood at the end of the
        regular season (or all completed fixtures if no cutoff is configured).
        ``championship``: the top six by regular-season points / GD / GF.
        ``relegation``: the bottom ten by the same ordering.

        The split mirrors what Sportradar returns for the same season; the
        function is the demo-time fallback when the trial-tier API does not
        serve historical playoff groups. When no cutoff is configured for the
        requested season the function still returns a populated ``regular``
        and empty playoff buckets, matching the legacy single-table shape.

        For the baked 2025-26 season the table is built from the committed
        fixtures dataset (``ml/data/superliga_2025_26_fixtures.json``) instead of
        the CSV, because All_Data.csv carries no 2025-26 rows. This keeps the
        play-off / play-out split real and Sportradar-free.
        """
        # Local import: avoids a hard dependency at module load and any cycle.
        from services.baked_fixtures import baked_standings_with_groups, is_baked_season

        if is_baked_season(season):
            return baked_standings_with_groups()

        cutoff_iso = _REGULAR_SEASON_CUTOFFS.get(str(season)) if season else None

        df = self._df.copy()
        if season:
            df = df[df["season"].astype(str) == str(season)]

        if cutoff_iso:
            cutoff_ts = pd.Timestamp(cutoff_iso, tz="UTC")
            dt = pd.to_datetime(df["match_date"], errors="coerce", utc=True)
            regular_df = df[dt < cutoff_ts]
        else:
            regular_df = df

        regular_rows = self._build_standings(regular_df)

        if cutoff_iso and len(regular_rows) >= 16:
            top_six = regular_rows[:6]
            bottom_ten = regular_rows[6:]
            championship = [dict(r) for r in top_six]
            relegation = [dict(r) for r in bottom_ten]
            # Re-rank the playoff groups from 1 inside their own group so the
            # Flutter table reads "Championship Round 1..6" not "5..10".
            for i, row in enumerate(championship, 1):
                row["position"] = i
            for i, row in enumerate(relegation, 1):
                row["position"] = i
        else:
            championship = []
            relegation = []

        return {
            "regular": regular_rows,
            "championship": championship,
            "relegation": relegation,
        }

    def _build_standings(self, df: pd.DataFrame) -> list[dict]:
        """Aggregate a DataFrame of fixtures into a sorted standings list.

        Shared by ``standings()`` and ``standings_with_groups()``. Returns the
        same row shape as ``standings()``.
        """
        completed = df.dropna(subset=["home_score", "away_score"]).copy()
        if completed.empty:
            return []
        completed["home_score"] = completed["home_score"].astype(int)
        completed["away_score"] = completed["away_score"].astype(int)

        teams: dict[str, dict] = {}
        for _, r in completed.iterrows():
            ht, at = r["home_team"], r["away_team"]
            hs, as_ = r["home_score"], r["away_score"]
            for t in (ht, at):
                if t not in teams:
                    teams[t] = {"team": t, "played": 0, "wins": 0, "draws": 0, "losses": 0, "gf": 0, "ga": 0, "pts": 0}
            teams[ht]["played"] += 1
            teams[at]["played"] += 1
            teams[ht]["gf"] += hs
            teams[ht]["ga"] += as_
            teams[at]["gf"] += as_
            teams[at]["ga"] += hs
            if hs > as_:
                teams[ht]["wins"] += 1
                teams[ht]["pts"] += 3
                teams[at]["losses"] += 1
            elif hs < as_:
                teams[at]["wins"] += 1
                teams[at]["pts"] += 3
                teams[ht]["losses"] += 1
            else:
                teams[ht]["draws"] += 1
                teams[at]["draws"] += 1
                teams[ht]["pts"] += 1
                teams[at]["pts"] += 1

        rows = sorted(teams.values(), key=lambda t: (-t["pts"], -(t["gf"] - t["ga"]), -t["gf"]))
        return [
            {
                "position": i,
                "team": t["team"],
                "played": t["played"],
                "wins": t["wins"],
                "draws": t["draws"],
                "losses": t["losses"],
                "goals_for": t["gf"],
                "goals_against": t["ga"],
                "goal_difference": t["gf"] - t["ga"],
                "points": t["pts"],
            }
            for i, t in enumerate(rows, 1)
        ]

    def _row_to_fixture(self, r: pd.Series) -> dict:
        venue = self._stadium_map.get(r.get("home_team", ""), None)
        return {
            "match_id": str(r.get("match_id", "")),
            "season": str(r.get("season", "")),
            "match_date": str(r.get("match_date", "")),
            "home_team": r.get("home_team", ""),
            "away_team": r.get("away_team", ""),
            "home_score": int(r["home_score"]) if pd.notna(r.get("home_score")) else None,
            "away_score": int(r["away_score"]) if pd.notna(r.get("away_score")) else None,
            "venue": venue,
        }
