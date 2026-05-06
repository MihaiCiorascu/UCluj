from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

import joblib
import pandas as pd
from catboost import CatBoostClassifier, CatBoostRegressor

# Canonical tactical strings mapped to valid role counts (always 11 with GK).
FORMATIONS: Dict[str, Dict[str, int]] = {
    "4-4-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-3-3": {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3},
    "4-2-3-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-5-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-1-4-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-3-2-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-2-2-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "3-1-4-2": {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-5-2": {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-4-3": {"GK": 1, "DEF": 3, "MID": 4, "FWD": 3},
    "3-6-1": {"GK": 1, "DEF": 3, "MID": 6, "FWD": 1},
    "5-3-2": {"GK": 1, "DEF": 5, "MID": 3, "FWD": 2},
    "5-4-1": {"GK": 1, "DEF": 5, "MID": 4, "FWD": 1},
}


def normalize_formation_key(formation: str) -> str:
    key = (formation or "").strip()
    return key if key in FORMATIONS else "4-3-3"


def formation_role_counts(formation: str) -> Dict[str, int]:
    key = normalize_formation_key(formation)
    f = FORMATIONS[key]
    return {"GK": 1, "DEF": f["DEF"], "MID": f["MID"], "FWD": f["FWD"]}


class XIPredictor:
    """
    Handles player performance scoring and optimal XI selection.
    Uses a hybrid approach:
    1. Supervised: If historical match ratings are available.
    2. Unsupervised: Composite scoring based on role-specific KPIs.
    """

    def __init__(
        self,
        model_path: Optional[str] = None,
        feature_cols: Optional[List[str]] = None,
    ):
        self.model_path = model_path
        self.feature_cols = feature_cols or [
            "performance_score",
            "recent_form_score",
            "matches_played",
            "pass_accuracy",
            "duel_win_rate",
            "def_action_success",
            "shot_accuracy",
            "dribble_success",
        ]
        self.model = self._load_model()
        self.is_supervised = self.model is not None

    def _load_model(self) -> Optional[Any]:
        if not self.model_path:
            return None
        try:
            return joblib.load(self.model_path)
        except Exception:
            return None

    def _create_fallback_model(self):
        """Create a default CatBoost model if none provided."""
        return CatBoostRegressor(
            iterations=500,
            learning_rate=0.05,
            depth=6,
            random_seed=42,
            # Ordered boosting — implicit activ, dar poți forța:
            boosting_type="Ordered",  # ← previne leakage temporal
            # Regularizare built-in:
            l2_leaf_reg=3.0,
            bagging_temperature=0.8,
        )

    def _composite_score(self, row: pd.Series) -> float:
        """
        Unsupervised composite score — used when no labeled data is available.
        Blends performance score, recent form, and efficiency metrics based on position.
        Scaled to 0-1 range (multiplied by 100 in UI for 0-100 scale).
        """
        # Improvement 3: floor = 0.35 for ≥3 matches, 0.0 for sparse data
        matches = int(row.get("matches_played", 0) or 0)
        base_floor = 0.35 if matches >= 3 else 0.0

        # Available capacity for variable stats: 0.55
        # Weights for variable components:
        # Performance (0.22), Form (0.15), Experience (0.03) -> 0.40 total
        # Position-specific (0.15) -> 0.15 total
        # Sum = 0.40 + 0.15 = 0.55. Total score = base_floor + components = 1.0

        perf = row.get("performance_score", 0) or 0
        form = row.get("recent_form_score", 0) or 0

        # If performance_score is on 0-100 scale, normalize it
        if perf > 1.1:
            perf /= 100.0
        if form > 1.1:
            form /= 100.0

        base_vars = (
            0.22 * perf
            + 0.15 * form
            + 0.03 * min((row.get("matches_played", 0) or 0) / 20, 1.0)
        )

        role = str(row.get("role_group", "")).upper()

        if role == "GK":
            bonus = (
                0.07 * min((row.get("per90_gkSaves", 0) or 0) / 3.0, 1.0)
                + 0.05 * min((row.get("per90_gkCleanSheets", 0) or 0) / 0.5, 1.0)
                + 0.03 * (row.get("pass_accuracy", 0) or 0) / 100
            )
        elif role == "DEF":
            bonus = (
                0.07 * (row.get("def_action_success", 0) or 0) / 100
                + 0.05 * (row.get("duel_win_rate", 0) or 0) / 100
                + 0.03 * (row.get("pass_accuracy", 0) or 0) / 100
            )
        elif role == "MID":
            bonus = (
                0.07 * (row.get("pass_accuracy", 0) or 0) / 100
                + 0.05 * (row.get("duel_win_rate", 0) or 0) / 100
                + 0.03 * min((row.get("per90_keyPasses", 0) or 0) / 2.0, 1.0)
            )
        elif role == "FWD":
            bonus = (
                0.07 * min((row.get("per90_goals", 0) or 0) / 0.8, 1.0)
                + 0.05 * (row.get("shot_accuracy", 0) or 0) / 100
                + 0.03 * (row.get("dribble_success", 0) or 0) / 100
            )
        else:
            bonus = (
                0.05 * (row.get("pass_accuracy", 0) or 0) / 100
                + 0.05 * (row.get("duel_win_rate", 0) or 0) / 100
                + 0.05 * (row.get("def_action_success", 0) or 0) / 100
            )

        return base_floor + base_vars + bonus

    # ── Opponent adjustment ────────────────────────────────────────────────────

    def compute_opponent_adjustments(
        self,
        df_opponent_players: pd.DataFrame,
    ) -> Dict[str, float]:
        """
        Improvement 4: Meaningful opponent adjustment (up to ±15 %).
        Analyses opponent attackers/midfielders to derive threat metrics,
        then boosts our DEF/MID/FWD weights accordingly.
        """
        if df_opponent_players.empty:
            return {}

        opp = df_opponent_players[
            df_opponent_players["role_group"].isin(["FWD", "MID"])
        ]
        if opp.empty:
            opp = df_opponent_players

        def _mean(col: str, default: float) -> float:
            try:
                v = opp[col].mean()
                return float(v) if not pd.isna(v) else default
            except Exception:
                return default

        shot_acc      = _mean("shot_accuracy",      40.0)
        pass_acc      = _mean("pass_accuracy",       60.0)
        def_success   = _mean("def_action_success",  50.0)

        # 0-1 threat scalars
        attack_threat  = min(max((shot_acc - 30.0) / 70.0, 0.0), 1.0)
        press_quality  = min(max((pass_acc  - 50.0) / 40.0, 0.0), 1.0)
        def_strength   = min(max(def_success / 100.0,        0.0), 1.0)

        return {
            "def_weight": 1.0 + 0.15 * attack_threat,   # up to +15 % DEF boost
            "mid_weight": 1.0 + 0.10 * press_quality,   # up to +10 % MID boost
            "fwd_weight": 1.0 - 0.05 * def_strength,    # up to −5 % FWD penalty
        }

    # ── Selection Engine ───────────────────────────────────────────────────────

    def predict_optimal_xi(
        self,
        df_players: pd.DataFrame,
        formation: str = "4-3-3",
        opponent_adjustments: Optional[Dict[str, float]] = None,
        your_team_id: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Selects the best 11 players for a given formation.

        Args:
            df_players: Pre-filtered DataFrame of candidates
            formation: e.g. "4-3-3"
            opponent_adjustments: Role-based scoring multipliers
            your_team_id: If provided, validate team membership to guard against stale profile data
        """
        adj = opponent_adjustments or {}
        pool = df_players.copy()

        # Team validation: ensure no stale profile data contaminates XI selection
        if your_team_id is not None and "teamId" in pool.columns:
            pool = pool[pool["teamId"] == your_team_id]
            if pool.empty:
                raise ValueError(f"No players found for team {your_team_id} after filtering")

        # Improvement 6: exclude players at suspension risk before scoring
        if "yellow_card_risk" in pool.columns:
            pool = pool[pool["yellow_card_risk"] == 0]

        # 1. Scoring — always compute composite for display/fallback
        pool["composite_score"] = pool.apply(self._composite_score, axis=1)

        if self.is_supervised:
            # Use predict_proba if available (gives 0-1 probability of being a starter)
            # so ranking is meaningful. Fall back to binary predict otherwise.
            try:
                pool["predicted_score"] = self.model.predict_proba(pool[self.feature_cols])[:, 1]
            except Exception:
                pool["predicted_score"] = self.model.predict(pool[self.feature_cols])
        else:
            # Fallback to composite scoring
            pool["predicted_score"] = pool["composite_score"].copy()

        # 2. Apply adjustments
        def_adj = adj.get("def_weight", 1.0)
        mid_adj = adj.get("mid_weight", 1.0)
        fwd_adj = adj.get("fwd_weight", 1.0)
        pool.loc[pool["role_group"] == "DEF", "predicted_score"] *= def_adj
        pool.loc[pool["role_group"] == "MID", "predicted_score"] *= mid_adj
        pool.loc[pool["role_group"] == "FWD", "predicted_score"] *= fwd_adj

        # 3. Formation logic (supports multi-segment patterns like 4-2-3-1).
        resolved_formation = normalize_formation_key(formation)
        slots = formation_role_counts(resolved_formation)

        xi_rows = []
        used_ids = set()

        for role, count in slots.items():
            role_pool = pool[pool["role_group"] == role].sort_values(
                "predicted_score", ascending=False
            )
            selected = role_pool.head(count)
            xi_rows.append(selected)
            used_ids.update(selected["playerId"].tolist())

        xi_df = pd.concat(xi_rows, ignore_index=True) if xi_rows else pd.DataFrame()

        # Bench: remaining top players
        bench_df = (
            pool[~pool["playerId"].isin(used_ids)]
            .sort_values("predicted_score", ascending=False)
            .head(7)
        )

        return {
            "formation": resolved_formation,
            "formation_slots": slots,
            "xi": xi_df,
            "bench": bench_df,
            "all_scored": pool.sort_values("predicted_score", ascending=False),
        }

    def get_feature_importance(self) -> Optional[pd.DataFrame]:
        """Return feature importance if a supervised model was trained."""
        if not self.is_supervised or self.model is None:
            return None
        if hasattr(self.model, "feature_importances_"):
            fi = pd.DataFrame(
                {
                    "feature": self.feature_cols,
                    "importance": self.model.feature_importances_,
                }
            ).sort_values("importance", ascending=False)
            return fi
        return None


class StartingXIPredictor(XIPredictor):
    """Backward-compatible wrapper used by pipeline/service code."""

    def __init__(self, model_type: str = "auto", model_path: Optional[str] = None):
        super().__init__(model_path=model_path)
        self.model_type = model_type

    def fit(
        self,
        df: pd.DataFrame,
        labels: Optional[pd.Series] = None,
        verbose: bool = True,
    ):
        if labels is not None and self.model is None:
            try:
                model = CatBoostClassifier(
                    iterations=300,
                    learning_rate=0.05,
                    depth=6,
                    verbose=False,
                    random_seed=42,
                )
                model.fit(df[self.feature_cols], labels)
                self.model = model
                self.is_supervised = True
            except Exception:
                self.model = None
                self.is_supervised = False
        return self

    def predict_xi(
        self,
        df: pd.DataFrame,
        formation: str = "4-3-3",
        your_team_id: Optional[int] = None,
        opponent_df: Optional[pd.DataFrame] = None,
    ) -> Dict[str, Any]:
        adjustments = {}
        if opponent_df is not None and not opponent_df.empty:
            adjustments = self.compute_opponent_adjustments(opponent_df)
        return self.predict_optimal_xi(
            df_players=df,
            formation=formation,
            opponent_adjustments=adjustments,
            your_team_id=your_team_id,
        )