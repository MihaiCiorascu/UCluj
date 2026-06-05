from __future__ import annotations

import pandas as pd
import numpy as np

from ml.feature_config import BASE_FEATURES, OPTIONAL_FEATURES

# Sportradar full names → All_Data.csv canonical names
_SR_TO_CSV: dict[str, str] = {
    "FC Universitatea Cluj": "U Cluj",
    "Universitatea Cluj": "U Cluj",
    "FC CFR 1907 Cluj": "CFR Cluj",
    "Fotbal Club FCSB": "FCSB",
    "Rapid Bucuresti 1923": "Rapid Bucuresti",
    "FC Dinamo Bucuresti 1948": "Dinamo Bucuresti",
    "FC Unirea 2004 Slobozia": "Unirea Slobozia",
    "AFK Csikszereda Miercurea Ciuc": "Csikszereda M. Ciuc",
    "ACS Champions FC Arges": "FC Arges",
    "CS Universitatea Craiova": "Univ. Craiova",
    "FC Uta Arad": "UTA Arad",
    "AFC Hermannstadt": "FC Hermannstadt",
    "FC Petrolul Ploiesti": "Petrolul Ploiesti",
    "FC Farul Constanta": "Farul Constanta",
    "ASC Otelul Galati": "Otelul Galati",
}


def _normalize_team(name: str) -> str:
    return _SR_TO_CSV.get(name, name)


class FeatureService:
    """Builds feature vectors for a fixture from the historical dataset."""

    def __init__(self, df: pd.DataFrame):
        self._df = df

    def build_feature_vector(
        self,
        home_team: str,
        away_team: str,
        feature_cols: list[str],
    ) -> pd.DataFrame:
        """Assemble the latest available feature row for a fixture.

        Looks up the most recent match for each team and combines their
        rolling/Elo/H2H stats into a single-row DataFrame aligned to
        feature_cols.
        """
        home_team = _normalize_team(home_team)
        away_team = _normalize_team(away_team)
        home_row = self._latest_home_stats(home_team)
        away_row = self._latest_away_stats(away_team)

        vector: dict[str, float] = {}
        for col in feature_cols:
            if col in home_row:
                vector[col] = home_row[col]
            elif col in away_row:
                vector[col] = away_row[col]
            else:
                vector[col] = np.nan

        return pd.DataFrame([vector], columns=feature_cols)

    def win_prob(self, model, subject_team: str, opponent_team: str) -> float:
        """Return P(``subject_team`` wins) for the subject-vs-opponent fixture.

        The CatBoost bundle is a BINARY home-win classifier, so it answers
        "does the home side win?" for whatever fixture the feature vector
        encodes. To read a specific team's win probability directly, we build
        the feature vector with that team placed in the HOME slot and the
        opponent in the AWAY slot, then call ``predict_proba`` (which returns
        P(home win)). Calling this once per side yields each team's true win
        probability without ever introducing a forbidden 3-way classifier;
        each call is an independent binary prediction.
        """
        feat = self.build_feature_vector(subject_team, opponent_team, model.feature_cols)
        return float(model.predict_proba(feat))

    def _latest_home_stats(self, team: str) -> dict[str, float]:
        matches = self._df[self._df["home_team"] == team].sort_values("match_date")
        if matches.empty:
            return {}
        row = matches.iloc[-1]
        return {c: float(row[c]) for c in _home_columns() if c in row.index and pd.notna(row[c])}

    def _latest_away_stats(self, team: str) -> dict[str, float]:
        matches = self._df[self._df["away_team"] == team].sort_values("match_date")
        if matches.empty:
            return {}
        row = matches.iloc[-1]
        return {c: float(row[c]) for c in _away_columns() if c in row.index and pd.notna(row[c])}

    def available_teams(self) -> list[str]:
        home = set(self._df["home_team"].dropna().unique())
        away = set(self._df["away_team"].dropna().unique())
        return sorted(home | away)

    def head_to_head(self, team_a: str, team_b: str, n: int = 5) -> list[dict]:
        mask = (
            ((self._df["home_team"] == team_a) & (self._df["away_team"] == team_b))
            | ((self._df["home_team"] == team_b) & (self._df["away_team"] == team_a))
        )
        h2h = self._df[mask].sort_values("match_date", ascending=False).head(n)
        return h2h[["match_date", "home_team", "away_team", "home_score", "away_score"]].to_dict("records")


def _home_columns() -> list[str]:
    return [c for c in BASE_FEATURES + OPTIONAL_FEATURES if c.startswith("Home_") or c.startswith("Computed_")]


def _away_columns() -> list[str]:
    return [c for c in BASE_FEATURES + OPTIONAL_FEATURES if c.startswith("Away_")]
