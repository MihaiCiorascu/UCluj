from __future__ import annotations

import numpy as np
import pandas as pd

from app.config import settings
from ml.feature_config import OPTIMIZABLE_FEATURES
from services.model_service import ModelService
from services.tactical_bounds import get_ratio_bounds
from services.tactical_sampling import sample_feasible

_HOME_STATS = [
    "Home_Poss_5", "Home_Shots_5", "Home_SoT_5",
    "Home_Corners_5", "Home_Goals_5", "Home_Conceded_5",
]
_AWAY_STATS = [
    "Away_Poss_5", "Away_Shots_5", "Away_SoT_5",
    "Away_Corners_5", "Away_Goals_5", "Away_Conceded_5",
]

_LABELS = {
    "Home_Poss_5":     "possession",
    "Home_Shots_5":    "shots",
    "Home_SoT_5":      "shots on target",
    "Home_Corners_5":  "corners",
    "Home_Goals_5":    "goals scored",
    "Home_Conceded_5": "goals conceded",
    "Away_Poss_5":     "possession",
    "Away_Shots_5":    "shots",
    "Away_SoT_5":      "shots on target",
    "Away_Corners_5":  "corners",
    "Away_Goals_5":    "goals scored",
    "Away_Conceded_5": "goals conceded",
}

_UNITS = {
    "Home_Poss_5": "%", "Away_Poss_5": "%",
}


class PrescriptionService:
    def __init__(self, model_svc: ModelService):
        self._model = model_svc

    def prescribe(
        self,
        features: pd.DataFrame,
        subject_is_home: bool,
        num_simulations: int | None = None,
        random_state: int | None = None,
    ) -> dict:
        """Run the constrained Monte Carlo optimizer from the notebook (Cell 38).

        Returns baseline_prob, best_prob, improvement, and a human-readable
        prescription string in English. When ``num_simulations`` or
        ``random_state`` are not given they default to the thesis production
        values from ``settings`` (N = 25,000, seed = 42), so the sample count
        is configured in exactly one place. The loop builds every candidate
        first and predicts the whole batch in a single CatBoost call, so the
        larger N stays sub-second per fixture.
        """
        if not self._model.is_ready:
            return {"text": "", "improvement": 0.0}

        if num_simulations is None:
            num_simulations = settings.optimizer_num_simulations
        if random_state is None:
            random_state = settings.optimizer_seed

        feature_cols = self._model.feature_cols
        bounds = self._model.bounds          # {stat: {'low': x, 'high': y}}
        target_stats = _HOME_STATS if subject_is_home else _AWAY_STATS

        # Build index map once
        feat_idx = {col: i for i, col in enumerate(feature_cols)}

        # Baseline vector (numpy array for fast copy in loop)
        X_row = features[feature_cols].copy()
        if self._model._imputer is not None:
            X_row = pd.DataFrame(
                self._model._imputer.transform(X_row),
                columns=feature_cols,
            )
        baseline_vec = X_row.iloc[0].to_numpy(dtype=float)

        def _predict(vec: np.ndarray) -> float:
            df = pd.DataFrame([vec], columns=feature_cols)
            return float(self._model._model.predict_proba(df)[0, 1])

        raw_baseline = _predict(baseline_vec)
        # Convert to P(subject win) perspective for display
        baseline_prob = raw_baseline if subject_is_home else 1.0 - raw_baseline

        # Resolve marginal bounds for the four controllable levers, keyed by the
        # Home_* names the shared sampler expects. The bundle only ships Home_*
        # bounds, so an Away_* subject reuses the Home_* band (the marginal
        # distribution of, e.g., shots-in-5 is team-agnostic). Goals/Conceded
        # are no longer sampled here: they stay frozen at baseline in the
        # candidate vector and still feed the win-probability.
        canon = {  # target-stat column -> canonical Home_* key
            target_stats[i]: OPTIMIZABLE_FEATURES[i]
            for i in range(len(OPTIMIZABLE_FEATURES))
        }

        def _bounds(stat: str):
            b = bounds.get(stat) or bounds.get(stat.replace("Away_", "Home_"))
            if b is None:
                return None
            return {"low": b["low"], "high": b["high"]}

        marginal_bounds: dict[str, dict] = {}
        base_row: dict[str, float] = {}
        for i, home_key in enumerate(OPTIMIZABLE_FEATURES):
            stat = target_stats[i]
            mb = _bounds(stat)
            if mb is None:
                return {"text": "", "improvement": 0.0}
            marginal_bounds[home_key] = mb
            base_row[home_key] = float(baseline_vec[feat_idx[stat]])

        rng = np.random.default_rng(random_state)

        # Shared conditional sampler: every draw already satisfies the empirical
        # SoT/Shots and Corners/Shots bands and the trust region, so there is no
        # rejection loop and no wasted samples.
        levers = sample_feasible(
            base_row=base_row,
            marginal_bounds=marginal_bounds,
            ratio_bounds=get_ratio_bounds(),
            trust_frac=float(settings.optimizer_trust_region_frac),
            n=num_simulations,
            rng=rng,
        )

        # Build the candidate matrix: clone the baseline vector for every draw,
        # then overwrite only the four controllable levers (Goals/Conceded stay
        # frozen at baseline).
        n_drawn = int(len(levers))
        best_tactic: dict | None = None
        best_raw = raw_baseline
        if n_drawn > 0:
            batch_arr = np.tile(baseline_vec, (n_drawn, 1))
            for i, home_key in enumerate(OPTIMIZABLE_FEATURES):
                batch_arr[:, feat_idx[target_stats[i]]] = levers[home_key].to_numpy(dtype=float)
            batch = pd.DataFrame(batch_arr, columns=feature_cols)
            probs = self._model._model.predict_proba(batch)[:, 1]
            best_idx = int(np.argmax(probs) if subject_is_home else np.argmin(probs))
            candidate_raw = float(probs[best_idx])
            improved = (candidate_raw > best_raw) if subject_is_home else (candidate_raw < best_raw)
            if improved:
                best_raw = candidate_raw
                best_tactic = {
                    target_stats[i]: round(float(levers[home_key].iloc[best_idx]), 1)
                    for i, home_key in enumerate(OPTIMIZABLE_FEATURES)
                }

        best_prob = best_raw if subject_is_home else 1.0 - best_raw
        improvement = best_prob - baseline_prob

        if best_tactic is None or improvement < 0.01:
            return {
                "text": _no_improvement_text(baseline_prob),
                "improvement": round(improvement, 4),
                "structured": None,
            }

        # Only the controllable levers are recommendable; Goals/Conceded are
        # frozen at baseline and never appear as a recommendation.
        lever_stats = target_stats[: len(OPTIMIZABLE_FEATURES)]
        text = _build_prescription_text(
            baseline_prob, best_prob, improvement,
            baseline_vec, feat_idx, best_tactic, lever_stats,
        )
        structured = _build_structured(
            baseline_prob, best_prob, improvement,
            baseline_vec, feat_idx, best_tactic, lever_stats,
        )
        return {
            "text": text,
            "improvement": round(improvement, 4),
            "structured": structured,
        }


_READABLE_LABELS = {
    "Home_Poss_5":     "Possession",
    "Home_Shots_5":    "Shots",
    "Home_SoT_5":      "Shots on Target",
    "Home_Corners_5":  "Corners",
    "Home_Goals_5":    "Goals Scored",
    "Home_Conceded_5": "Goals Conceded",
    "Away_Poss_5":     "Possession",
    "Away_Shots_5":    "Shots",
    "Away_SoT_5":      "Shots on Target",
    "Away_Corners_5":  "Corners",
    "Away_Goals_5":    "Goals Scored",
    "Away_Conceded_5": "Goals Conceded",
}


def _build_structured(
    baseline_prob: float,
    best_prob: float,
    improvement: float,
    baseline_vec: np.ndarray,
    feat_idx: dict,
    best_tactic: dict,
    target_stats: list[str],
) -> dict:
    recs = []
    for stat in target_stats:
        current = round(float(baseline_vec[feat_idx[stat]]), 1)
        target  = best_tactic[stat]
        delta   = target - current
        if abs(delta) < 0.05:
            continue
        if stat in _HIGHER_IS_BETTER and delta < 0:
            continue
        if stat in _LOWER_IS_BETTER and delta > 0:
            continue
        recs.append({
            "label":     _READABLE_LABELS.get(stat, stat),
            "unit":      "%" if stat in _UNITS else "",
            "current":   current,
            "target":    target,
            "direction": "up" if delta > 0 else "down",
        })
    return {
        "baseline_prob": round(baseline_prob, 4),
        "best_prob":     round(best_prob, 4),
        "improvement":   round(improvement, 4),
        "recommendations": recs,
    }


def _no_improvement_text(prob: float) -> str:
    if prob >= 0.65:
        return (
            "The current tactical profile is already optimal for this fixture. "
            "Maintain the attacking approach and ball control."
        )
    return (
        "The tactical optimizer did not identify a game plan meaningfully better "
        "than the current approach. Focus on defensive discipline."
    )


# Stats where higher is better (▲ good), and which where lower is better (▼ good)
_HIGHER_IS_BETTER = {
    "Home_Poss_5", "Away_Poss_5",
    "Home_Shots_5", "Away_Shots_5",
    "Home_SoT_5", "Away_SoT_5",
    "Home_Corners_5", "Away_Corners_5",
    "Home_Goals_5", "Away_Goals_5",
}
_LOWER_IS_BETTER = {
    "Home_Conceded_5", "Away_Conceded_5",
}


def _build_prescription_text(
    baseline_prob: float,
    best_prob: float,
    improvement: float,
    baseline_vec: np.ndarray,
    feat_idx: dict,
    best_tactic: dict,
    target_stats: list[str],
) -> str:
    lines = []
    for stat in target_stats:
        current = round(float(baseline_vec[feat_idx[stat]]), 1)
        target  = best_tactic[stat]
        delta   = target - current
        if abs(delta) < 0.05:
            continue
        # Only show changes that go in the intuitive coaching direction
        if stat in _HIGHER_IS_BETTER and delta < 0:
            continue
        if stat in _LOWER_IS_BETTER and delta > 0:
            continue
        label = _LABELS.get(stat, stat)
        unit  = _UNITS.get(stat, "")
        arrow = "▲" if delta > 0 else "▼"
        lines.append(f"{arrow} {label}: {current}{unit} → {target}{unit}")

    if not lines:
        return _no_improvement_text(baseline_prob)

    header = (
        f"OPTIMAL TACTICAL PLAN — projected probability {best_prob:.0%} "
        f"(+{improvement:.0%} vs baseline {baseline_prob:.0%}):"
    )
    return header + "\n" + "  |  ".join(lines)
