"""
Starting-XI service for UmbraRo.

Iteration L generalisation: ``XiService`` now accepts a per-request
``home_team_substring`` (or a team short label or Sportradar ID) and
returns the predicted XI for that team. The previous U Cluj-only path
is preserved as the default — every method falls back to U Cluj when
the caller does not specify a team. The Flutter app keeps working
unchanged, but any of the sixteen Romanian Superliga teams can now be
queried.

Per-team feature DataFrames are cached on the service instance so that
repeat calls for the same team stay fast (the cold path costs roughly
five seconds while the league dataset is materialised and the per-team
availability features are computed).
"""

from __future__ import annotations

import glob
import os
import pickle
from typing import Dict, List, Optional

import pandas as pd

from ml.feature_engineering import get_team_squad_from_matches
from ml.pipeline import _format_output, build_dataset_from_files, load_player_profiles
from ml.xi_predictor import StartingXIPredictor
from sportradar.team_registry import (
    SUPERLIGA_TEAMS,
    TeamRef,
    team_by_alias,
    team_by_short,
    team_by_sr_id,
)

# Wyscout team IDs (used historically by the front-end for team selection).
# Retained for backwards compatibility — new code should prefer
# :data:`sportradar.team_registry.SUPERLIGA_TEAMS`.
FIXTURE_NAME_TO_ID: dict[str, int] = {
    "U Cluj": 11571,
    "CFR Cluj": 11611,
    "FCSB": 8164,
    "Rapid Bucuresti": 11566,
    "Dinamo Bucuresti": 11564,
    "FC Botosani": 11634,
    "Unirea Slobozia": 11663,
    "Metaloglobus Bucuresti": 11943,
    "Csikszereda M. Ciuc": 22731,
    "FC Arges": 23334,
    "U Craiova 1948": 26233,
    "Univ. Craiova": 26233,
    "UTA Arad": 30817,
    "FC Hermannstadt": 55427,
    "Petrolul Ploiesti": 60390,
    "Farul Constanta": 61242,
    "Otelul Galati": 69049,
    "Sepsi Sf. Gheorghe": None,
}


class XiService:
    """Starting-XI predictor service that supports any Romanian Superliga team.

    The default home team remains FC Universitatea Cluj for backwards
    compatibility, but the public methods now accept a
    ``home_team_substring`` (or any team-registry alias) so that callers
    can request another club's predicted XI without touching service
    internals.
    """

    DEFAULT_HOME_TEAM_SUBSTRING = "Universitatea Cluj"

    def __init__(self, model_path: str, data_dir: str):
        self.model_path = model_path
        self.data_dir = data_dir
        self.predictor: Optional[StartingXIPredictor] = None
        self._df_by_team: Dict[str, pd.DataFrame] = {}
        self._squad_by_team: Dict[str, set] = {}
        self._profiles: Dict = {}

        # Pre-load the heuristic-predictor pickle.
        if os.path.exists(model_path):
            with open(model_path, "rb") as f:
                self.predictor = pickle.load(f)

        # Iteration J.4: Auto-load the supervised lineup-classifier bundle
        # alongside the heuristic predictor. Iteration L will replace this
        # path with the league-wide bundle (``xi_lineup_model_league.joblib``)
        # once the pooled supervised model is retrained.
        league_bundle = os.path.join(
            os.path.dirname(model_path), "xi_lineup_model_league.joblib"
        )
        ucluj_bundle = os.path.join(
            os.path.dirname(model_path), "xi_lineup_model.joblib"
        )
        bundle_path = league_bundle if os.path.exists(league_bundle) else ucluj_bundle
        if self.predictor is not None and os.path.exists(bundle_path):
            try:
                import joblib
                self.predictor.supervised_bundle = joblib.load(bundle_path)
            except Exception:
                pass

    # ── Team-registry helpers ────────────────────────────────────────────────

    def _resolve_home_team(
        self,
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
    ) -> TeamRef:
        """Resolve a TeamRef from any of the supported caller inputs."""
        if home_team_sr_id:
            t = team_by_sr_id(home_team_sr_id)
            if t is not None:
                return t
        if home_team_short:
            t = team_by_short(home_team_short)
            if t is not None:
                return t
        if home_team_substring:
            t = team_by_alias(home_team_substring)
            if t is not None:
                return t
            # Fall back to a free-form substring (handy for older callers).
            return TeamRef(
                short=home_team_substring,
                wy_substr=home_team_substring,
                sr_id="",
            )
        return team_by_alias(self.DEFAULT_HOME_TEAM_SUBSTRING) or SUPERLIGA_TEAMS[0]

    # ── Feature-DataFrame builder (cached per home team) ─────────────────────

    def _get_feature_df(self, home_team: TeamRef) -> pd.DataFrame:
        cache_key = home_team.wy_substr
        if cache_key in self._df_by_team:
            return self._df_by_team[cache_key]

        match_files = sorted(glob.glob(os.path.join(self.data_dir, "*.json")))
        profile_path = os.path.join(self.data_dir, "players (1).json")
        if not self._profiles and os.path.exists(profile_path):
            self._profiles = load_player_profiles(profile_path)

        # Availability features are computed against *this* home team's
        # chronological fixture list. A player who does not belong to
        # the home team's empirical squad receives neutral availability
        # zeros — the same convention as the per-U Cluj implementation
        # used in Iterations J and K.
        df = build_dataset_from_files(
            match_files,
            self._profiles,
            availability_team_substring=home_team.wy_substr,
        )

        squad_ids = get_team_squad_from_matches(match_files, home_team.wy_substr)

        def _resolve_team(pid):
            profile = self._profiles.get(pid, {})
            return profile.get("currentTeamId", None)

        df["teamId"] = df["playerId"].apply(_resolve_team)
        df["is_home_squad"] = df["playerId"].isin(squad_ids)

        self._df_by_team[cache_key] = df
        self._squad_by_team[cache_key] = squad_ids
        return df

    # ── Public API ───────────────────────────────────────────────────────────

    def predict_xi(
        self,
        formation: str,
        opponent_team_id: Optional[int],
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
    ) -> Dict:
        if not self.predictor:
            raise RuntimeError("XI Model not loaded")

        home = self._resolve_home_team(
            home_team_substring=home_team_substring,
            home_team_sr_id=home_team_sr_id,
            home_team_short=home_team_short,
        )
        df = self._get_feature_df(home)

        my_team_df = df[df["is_home_squad"]].copy()
        if my_team_df.empty:
            raise RuntimeError(
                f"No players found for home team '{home.short}' "
                f"(empirical squad set is empty for wy_substr={home.wy_substr!r})."
            )

        opp_team_df = (
            df[df["teamId"] == opponent_team_id].copy() if opponent_team_id else None
        )

        result = self.predictor.predict_xi(
            df=my_team_df,
            formation=formation,
            your_team_id=opponent_team_id,
            opponent_df=opp_team_df,
        )

        # Surface the resolved home team in the response payload so the
        # Flutter app can confirm which team it received.
        out = _format_output(result, FIXTURE_NAME_TO_ID.get(home.short), opponent_team_id)
        out["home_team_short"] = home.short
        out["home_team_sr_id"] = home.sr_id
        return out

    def match_preview(
        self,
        opponent_name: str,
        formation: str,
        main_df: Optional[pd.DataFrame] = None,
        home_team_substring: Optional[str] = None,
        home_team_sr_id: Optional[str] = None,
        home_team_short: Optional[str] = None,
    ) -> Dict:
        """Return starting XI + team stats + H2H record for an upcoming match."""
        if not self.predictor:
            raise RuntimeError("XI model not loaded")

        home = self._resolve_home_team(
            home_team_substring=home_team_substring,
            home_team_sr_id=home_team_sr_id,
            home_team_short=home_team_short,
        )
        opp_id = FIXTURE_NAME_TO_ID.get(opponent_name)

        df = self._get_feature_df(home)

        my_team_df = df[df["is_home_squad"]].copy()
        if my_team_df.empty:
            raise RuntimeError(
                f"No players found for home team '{home.short}' "
                f"(empirical squad set is empty for wy_substr={home.wy_substr!r})."
            )

        opp_team_df = df[df["teamId"] == opp_id].copy() if opp_id else None

        result = self.predictor.predict_xi(
            df=my_team_df,
            formation=formation,
            your_team_id=FIXTURE_NAME_TO_ID.get(home.short),
            opponent_df=opp_team_df,
        )

        _PLAYER_COLS = [
            "playerId", "shortName", "role", "role_group",
            "predicted_score", "performance_score", "recent_form_score",
            "total_minutes", "matches_played",
            "pass_accuracy", "duel_win_rate",
            "per90_goals", "per90_assists", "per90_shots",
            "per90_keyPasses", "per90_interceptions", "per90_gkSaves",
        ]

        def _fmt(frame: pd.DataFrame) -> List[Dict]:
            if frame is None or frame.empty:
                return []
            cols = [c for c in _PLAYER_COLS if c in frame.columns]
            return frame[cols].fillna(0).to_dict(orient="records")

        # Team aggregate stats
        all_df = result.get("all_scored", pd.DataFrame())
        team_stats: Dict = {}
        if not all_df.empty:
            def _mean(col: str) -> float:
                return round(float(all_df[col].mean()), 2) if col in all_df.columns else 0.0

            team_stats = {
                "avg_performance_score": _mean("performance_score"),
                "avg_recent_form": _mean("recent_form_score"),
                "avg_pass_accuracy": round(_mean("pass_accuracy"), 1),
                "avg_duel_win_rate": round(_mean("duel_win_rate"), 1),
            }
            for stat, key in [("per90_goals", "top_scorer"), ("per90_keyPasses", "top_creator")]:
                if stat in all_df.columns and not all_df.empty:
                    row = all_df.nlargest(1, stat).iloc[0]
                    team_stats[key] = str(row.get("shortName", ""))
                    team_stats[f"{key}_stat"] = round(float(row.get(stat, 0)), 2)

        # Opponent aggregate stats
        opponent_stats: Dict = {}
        if opp_team_df is not None and not opp_team_df.empty:
            def _opp_mean(col: str) -> float:
                return round(float(opp_team_df[col].mean()), 2) if col in opp_team_df.columns else 0.0

            opponent_stats = {
                "avg_performance_score": _opp_mean("performance_score"),
                "avg_recent_form": _opp_mean("recent_form_score"),
                "avg_pass_accuracy": round(_opp_mean("pass_accuracy"), 1),
                "avg_duel_win_rate": round(_opp_mean("duel_win_rate"), 1),
            }
            for stat, key in [("per90_goals", "top_scorer"), ("per90_keyPasses", "top_creator")]:
                if stat in opp_team_df.columns and not opp_team_df.empty:
                    row = opp_team_df.nlargest(1, stat).iloc[0]
                    opponent_stats[key] = str(row.get("shortName", ""))
                    opponent_stats[f"{key}_stat"] = round(float(row.get(stat, 0)), 2)
        else:
            opponent_stats = {
                "avg_performance_score": 0.0,
                "avg_recent_form": 0.0,
                "avg_pass_accuracy": 0.0,
                "avg_duel_win_rate": 0.0,
                "top_scorer": "",
                "top_scorer_stat": 0.0,
                "top_creator": "",
                "top_creator_stat": 0.0,
            }

        # Head-to-head from main fixtures CSV (uses the resolved home short label)
        h2h: Dict = {"total": 0, "our_wins": 0, "draws": 0, "their_wins": 0,
                     "our_avg_goals": 0.0, "their_avg_goals": 0.0}
        if main_df is not None and not main_df.empty:
            try:
                our = home.short
                mask = (
                    ((main_df["home_team"] == our) & (main_df["away_team"] == opponent_name))
                    | ((main_df["home_team"] == opponent_name) & (main_df["away_team"] == our))
                )
                h2h_df = main_df[mask].dropna(subset=["home_score", "away_score"]).tail(10)
                if not h2h_df.empty:
                    our_wins = draws = their_wins = our_g_total = their_g_total = 0
                    for _, row in h2h_df.iterrows():
                        hs, as_ = int(row["home_score"]), int(row["away_score"])
                        is_home = row["home_team"] == our
                        og, tg = (hs, as_) if is_home else (as_, hs)
                        our_g_total += og
                        their_g_total += tg
                        if og > tg:
                            our_wins += 1
                        elif og < tg:
                            their_wins += 1
                        else:
                            draws += 1
                    n = len(h2h_df)
                    h2h = {
                        "total": n,
                        "our_wins": our_wins,
                        "draws": draws,
                        "their_wins": their_wins,
                        "our_avg_goals": round(our_g_total / n, 1),
                        "their_avg_goals": round(their_g_total / n, 1),
                    }
            except Exception:
                pass

        return {
            "formation": formation,
            "home_team_short": home.short,
            "home_team_sr_id": home.sr_id,
            "opponent_name": opponent_name,
            "opponent_team_id": opp_id,
            "starting_xi": _fmt(result["xi"]),
            "bench": _fmt(result["bench"]),
            "team_stats": team_stats,
            "opponent_stats": opponent_stats,
            "head_to_head": h2h,
        }

    def list_opponents(self, min_players: int = 20,
                       home_team_substring: Optional[str] = None) -> list[dict]:
        """Return opponent options. Iteration L: prefer the team registry
        over the legacy ``currentTeamId`` count."""
        home = self._resolve_home_team(home_team_substring=home_team_substring)

        # Primary path: team registry (returns all sixteen Superliga clubs
        # minus the home team).
        opponents = [
            {
                "id": FIXTURE_NAME_TO_ID.get(t.short),
                "name": t.short,
                "sr_id": t.sr_id,
            }
            for t in SUPERLIGA_TEAMS
            if t.short != home.short
        ]
        return sorted(opponents, key=lambda item: item["name"])

    # ── New Iteration L public method: list all Superliga teams ─────────────
    def list_home_teams(self) -> list[dict]:
        """Return every Romanian Superliga team eligible as the home team."""
        return [
            {
                "short": t.short,
                "wy_substr": t.wy_substr,
                "sr_id": t.sr_id,
            }
            for t in SUPERLIGA_TEAMS
        ]
