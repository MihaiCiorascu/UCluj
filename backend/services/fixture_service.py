from __future__ import annotations

import pandas as pd
import numpy as np

from app.config import effective_now, settings


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

        fixtures = [self._row_to_fixture(r) for _, r in upcoming.head(n).iterrows()]

        if not fixtures:
            # Mock upcoming match for presentation purposes
            fixtures.append({
                "match_id": "mock_fcsb_1",
                "season": "2024",
                "match_date": "2024-05-10T20:00:00Z",
                "home_team": team,
                "away_team": "FCSB",
                "home_score": None,
                "away_score": None,
                "venue": self._stadium_map.get(team, "Cluj Arena"),
            })

        return fixtures[:n]

    def standings(self, season: str | None = None) -> list[dict]:
        df = self._df.copy()
        if season:
            df = df[df["season"].astype(str) == str(season)]

        completed = df.dropna(subset=["home_score", "away_score"]).copy()
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
        result = []
        for i, t in enumerate(rows, 1):
            result.append({
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
            })
        return result

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
