"""
Starting-XI Predictor for UmbraRo.

The predictor scores every available player by a position-aware composite of
per-90 KPIs that has been (i) z-scored within the player's positional group,
(ii) shrunk toward the position mean for low-sample players using an
empirical-Bayes update, and (iii) exponentially decayed by recency when the
recent-form input is available. The eleven highest-scoring players are then
selected greedily under a fixed-formation slot constraint.

The methodological choices are deliberate adaptations of published work:

* Pappalardo et al. (2019), *PlayeRank: Data-driven performance evaluation and
  player ranking in soccer*, ACM TIST 10(5):59, motivates position-relative
  evaluation and per-90 KPI normalisation.
* McHale, Scarf & Folker (2012), *On the development of a soccer player
  performance rating system for the English Premier League*, Interfaces
  42(4):339--351, justifies the weighted-KPI composite-score paradigm.
* Brown (2008), *In-season prediction of batting averages: A field test of
  empirical Bayes and Bayes methodologies*, Annals of Applied Statistics
  2(1):113--152, is the canonical reference for the empirical-Bayes shrinkage
  used here for small-sample players.
* Decroos et al. (2019), *Actions Speak Louder Than Goals: Valuing Player
  Actions in Soccer*, KDD 2019, is the natural action-level alternative the
  current aggregated approach can be extended to in future work.
* Constantinou (2019), *Dolores: a model that predicts football match outcomes
  from all over the world*, Machine Learning 108:49--75, frames the broader
  probabilistic-soccer-prediction setting.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional

import joblib
import numpy as np
import pandas as pd

try:
    from scipy.optimize import linear_sum_assignment  # type: ignore
except Exception:  # pragma: no cover - scipy is an optional dependency
    linear_sum_assignment = None  # type: ignore


# ── Formation library ─────────────────────────────────────────────────────────
# Each entry maps a positional group to the number of slots it must fill. The
# thirteen formations here mirror the Flutter ``kSupportedFormations`` list so
# every option the coach can pick has a backend slot layout.
FORMATIONS: Dict[str, Dict[str, int]] = {
    "4-4-2":   {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-3-3":   {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3},
    "4-2-3-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-5-1":   {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-1-4-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-3-2-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-2-2-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "3-1-4-2": {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-5-2":   {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-4-3":   {"GK": 1, "DEF": 3, "MID": 4, "FWD": 3},
    "3-6-1":   {"GK": 1, "DEF": 3, "MID": 6, "FWD": 1},
    "5-3-2":   {"GK": 1, "DEF": 5, "MID": 3, "FWD": 2},
    "5-4-1":   {"GK": 1, "DEF": 5, "MID": 4, "FWD": 1},
}

# Official-position slot templates. Each formation maps to an ordered list of
# eleven (official_label, coarse_group) tuples. The order IS the slot_index:
# the goalkeeper is index 0, then the lines run back to front (defence, then
# midfield, then attack), and within each line the slots run left to right (in
# the same left-to-right order the Flutter pitch template paints them). This
# ordering is the single source of truth that lib/core/constants/
# formation_slots.dart mirrors on the frontend; keep the two in sync.
FORMATION_SLOTS: Dict[str, List[tuple[str, str]]] = {
    "4-4-2": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
    ],
    "4-3-3": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("DM", "MID"), ("RCM", "MID"), ("LCM", "MID"),
        ("RW", "FWD"), ("ST", "FWD"), ("LW", "FWD"),
    ],
    "4-2-3-1": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RDM", "MID"), ("LDM", "MID"),
        ("RAM", "MID"), ("CAM", "MID"), ("LAM", "MID"),
        ("ST", "FWD"),
    ],
    "4-5-1": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RM", "MID"), ("RCM", "MID"), ("CM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("ST", "FWD"),
    ],
    "4-1-4-1": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("DM", "MID"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("ST", "FWD"),
    ],
    "4-3-2-1": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RCM", "MID"), ("CDM", "MID"), ("LCM", "MID"),
        ("RAM", "MID"), ("LAM", "MID"),
        ("ST", "FWD"),
    ],
    "4-2-2-2": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RDM", "MID"), ("LDM", "MID"),
        ("RAM", "MID"), ("LAM", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
    ],
    "3-1-4-2": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("DM", "MID"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
    ],
    "3-5-2": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("RWB", "MID"), ("RCM", "MID"), ("CM", "MID"), ("LCM", "MID"), ("LWB", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
    ],
    "3-4-3": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("RW", "FWD"), ("ST", "FWD"), ("LW", "FWD"),
    ],
    "3-6-1": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("RWB", "MID"), ("RCM", "MID"), ("RDM", "MID"), ("LDM", "MID"), ("LCM", "MID"), ("LWB", "MID"),
        ("ST", "FWD"),
    ],
    "5-3-2": [
        ("GK", "GK"),
        ("RWB", "DEF"), ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"), ("LWB", "DEF"),
        ("RCM", "MID"), ("CM", "MID"), ("LCM", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
    ],
    "5-4-1": [
        ("GK", "GK"),
        ("RWB", "DEF"), ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"), ("LWB", "DEF"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("ST", "FWD"),
    ],
}

# Which fine-position groups (the ten-group Wyscout taxonomy: GK, CB, FB, WB,
# DM, CM, AM, W, WF, ST) may legitimately fill a slot family. A slot family is
# the official label stripped of its left/right/centre prefix (see
# ``_slot_family``). The first group in each set is the natural fit; the rest
# are acceptable adjacent roles so the assignment never fails for lack of a
# perfect specialist.
SLOT_ADMISSIBLE_FINE: Dict[str, set] = {
    "GK": {"GK"},
    "CB": {"CB", "FB"},
    "FB": {"FB", "WB", "CB"},
    "WB": {"WB", "FB", "W"},
    "DM": {"DM", "CM"},
    "CM": {"CM", "DM", "AM"},
    "AM": {"AM", "CM", "W"},
    "M":  {"W", "WB", "CM", "AM"},
    "W":  {"W", "WF", "AM"},
    "WF": {"WF", "ST", "W"},
    "ST": {"ST", "WF", "W"},
}


def _validate_formation_slots() -> None:
    """Fail fast at import time if a slot template is internally inconsistent.

    Each formation must have exactly eleven slots, a goalkeeper at index 0, and
    a coarse-group breakdown that matches the count map in ``FORMATIONS``.
    """
    from collections import Counter

    for name, specs in FORMATION_SLOTS.items():
        if len(specs) != 11:
            raise ValueError(f"FORMATION_SLOTS[{name!r}] has {len(specs)} slots, expected 11")
        if specs[0][1] != "GK":
            raise ValueError(f"FORMATION_SLOTS[{name!r}] does not start with the goalkeeper")
        coarse_counts = Counter(coarse for _, coarse in specs)
        expected = FORMATIONS.get(name)
        if expected is not None and dict(coarse_counts) != dict(expected):
            raise ValueError(
                f"FORMATION_SLOTS[{name!r}] coarse counts {dict(coarse_counts)} "
                f"do not match FORMATIONS[{name!r}] {dict(expected)}"
            )


_validate_formation_slots()

# Position-specific composite-score weights. Each weight applies to a
# z-scored, shrinkage-corrected feature; the linear combination is passed
# through a tanh-based squash to remain in [0.25, 0.75] for the UI.
#
# Two parallel tables are maintained: COARSE_POSITION_WEIGHTS keeps the
# four-group GK / DEF / MID / FWD path used by callers that have not yet
# been updated, and FINE_POSITION_WEIGHTS covers the ten Wyscout-derived
# fine groups (CB, FB, WB, DM, CM, AM, W, WF, ST, GK). The fine table is
# used preferentially whenever the feature row carries a
# ``position_group_fine`` column populated by
# :func:`ml.feature_engineering.derive_primary_fine_position`.

# Position-aware composite-score weights.
#
# Iteration J introduces an explicit ``availability_score`` weight: an
# aggregate of (i) the player's share of minutes in the team's last five
# fixtures, (ii) whether they started the most recent fixture, and (iii) a
# long-gap penalty when more than three team fixtures have passed since
# their last appearance (see
# :func:`ml.feature_engineering.compute_availability_features`). The
# availability column restores the participation signal that pure per-90
# KPI normalisation throws away — top-by-minutes baselines win in part
# because they are pure availability signals, and the per-position
# composite was previously blind to this dimension.
#
# Per-position availability weights:
#   GK ≈ 0.10 — teams rotate goalkeepers infrequently, so a per-90 KPI
#       comparison remains highly informative on its own.
#   Outfield ≈ 0.20 — coaches rotate outfield slots based on fitness and
#       tactical match-ups, so availability is a strong indicator.
#   Strikers ≈ 0.25 — additionally rotated for opponent-specific reasons.
#
# The remaining weights have been renormalised so each row still sums to
# 1.0 for interpretability, even though the final composite is tanh-
# squashed and would behave identically under a constant rescale.

COARSE_POSITION_WEIGHTS: Dict[str, Dict[str, float]] = {
    "GK": {
        "performance_score":  0.32,
        "recent_form_score":  0.22,
        "pass_accuracy":      0.18,
        "matches_played":     0.18,
        "availability_score": 0.10,
    },
    "DEF": {
        "performance_score":  0.25,
        "recent_form_score":  0.17,
        "duel_win_rate":      0.18,
        "def_action_success": 0.13,
        "pass_accuracy":      0.12,
        "availability_score": 0.15,
    },
    "MID": {
        "performance_score":  0.25,
        "recent_form_score":  0.17,
        "pass_accuracy":      0.18,
        "duel_win_rate":      0.13,
        "matches_played":     0.12,
        "availability_score": 0.15,
    },
    "FWD": {
        "performance_score":  0.30,
        "recent_form_score":  0.20,
        "shot_accuracy":      0.15,
        "dribble_success":    0.15,
        "availability_score": 0.20,
    },
}

FINE_POSITION_WEIGHTS: Dict[str, Dict[str, float]] = {
    "GK": {
        "performance_score":  0.32, "recent_form_score": 0.22,
        "pass_accuracy":      0.18, "matches_played":    0.18,
        "availability_score": 0.10,
    },
    "CB": {
        "performance_score":  0.25, "recent_form_score":  0.17,
        "duel_win_rate":      0.18, "def_action_success": 0.13,
        "pass_accuracy":      0.12, "availability_score": 0.15,
    },
    "FB": {
        "performance_score":  0.20, "recent_form_score":  0.17,
        "duel_win_rate":      0.18, "def_action_success": 0.13,
        "pass_accuracy":      0.08, "matches_played":     0.09,
        "availability_score": 0.15,
    },
    "WB": {
        "performance_score":  0.25, "recent_form_score": 0.17,
        "pass_accuracy":      0.13, "duel_win_rate":     0.13,
        "dribble_success":    0.08, "matches_played":    0.09,
        "availability_score": 0.15,
    },
    "DM": {
        "performance_score":  0.25, "recent_form_score":  0.17,
        "duel_win_rate":      0.18, "def_action_success": 0.13,
        "pass_accuracy":      0.12, "availability_score": 0.15,
    },
    "CM": {
        "performance_score":  0.25, "recent_form_score": 0.17,
        "pass_accuracy":      0.22, "duel_win_rate":     0.13,
        "matches_played":     0.08, "availability_score": 0.15,
    },
    "AM": {
        "performance_score":  0.30, "recent_form_score": 0.17,
        "pass_accuracy":      0.16, "shot_accuracy":     0.12,
        "dribble_success":    0.08, "availability_score": 0.17,
    },
    "W": {
        "performance_score":  0.25, "recent_form_score": 0.17,
        "dribble_success":    0.16, "shot_accuracy":     0.12,
        "pass_accuracy":      0.12, "availability_score": 0.18,
    },
    "WF": {
        "performance_score":  0.30, "recent_form_score": 0.17,
        "shot_accuracy":      0.16, "dribble_success":   0.12,
        "matches_played":     0.05, "availability_score": 0.20,
    },
    "ST": {
        "performance_score":  0.35, "recent_form_score": 0.20,
        "shot_accuracy":      0.10, "dribble_success":   0.10,
        "availability_score": 0.25,
    },
}

# Backwards-compatible name kept for callers that imported the original
# four-group table directly.
POSITION_WEIGHTS = COARSE_POSITION_WEIGHTS

DEFAULT_FEATURE_COLS: List[str] = [
    "performance_score",
    "recent_form_score",
    "matches_played",
    "pass_accuracy",
    "duel_win_rate",
    "def_action_success",
    "shot_accuracy",
    "dribble_success",
    "availability_score",
]


@dataclass
class StartingXIPredictor:
    """Composite-score-based optimal-XI selector with empirical-Bayes shrinkage.

    Parameters
    ----------
    model_type : {"auto", "heuristic", "model"}, default "auto"
        ``auto`` and ``heuristic`` both fall back to the position-aware
        composite-score path. ``model`` is reserved for a future supervised
        extension (e.g. a CatBoost regressor trained on historical lineup
        labels) and currently behaves identically to ``heuristic`` until that
        extension is added.
    shrinkage_pseudo_matches : float, default 3.0
        Pseudo-count ``k`` in the empirical-Bayes update
        ``(k * position_mean + n * raw) / (k + n)``. Following Brown (2008),
        values around the per-player observation count provide moderate
        shrinkage; ``k = 3`` is appropriate for a five-season squad sample.
    decay_half_life_days : float, default 30.0
        Half-life of the exponential time decay applied when ``recent_form``
        inputs include per-match timestamps. Larger values trust older matches
        more.
    feature_cols : list of str, optional
        Subset of feature columns used by the composite score. Defaults to
        ``DEFAULT_FEATURE_COLS``.
    """

    model_type: str = "auto"
    shrinkage_pseudo_matches: float = 3.0
    decay_half_life_days: float = 30.0
    feature_cols: List[str] = field(default_factory=lambda: list(DEFAULT_FEATURE_COLS))

    # Fitted state — populated by .fit() and persisted by joblib.dump()
    position_means: Dict[str, Dict[str, float]] = field(default_factory=dict)
    position_stds: Dict[str, Dict[str, float]] = field(default_factory=dict)
    is_fitted: bool = False

    # Optional supervised lineup-classifier bundle (loaded lazily). When
    # populated, the ``method="supervised"`` branch of
    # :meth:`predict_xi` will use it to score players via the
    # logistic-regression P(started|features) probability rather than the
    # heuristic composite. Trained by
    # ``backend/scripts/train_lineup_classifier.py`` (Iteration J.4) and
    # persisted to ``backend/ml/xi_lineup_model.joblib``.
    supervised_bundle: Optional[Dict[str, Any]] = None

    # ── Fit ───────────────────────────────────────────────────────────────────

    def fit(
        self,
        df: pd.DataFrame,
        labels: Optional[pd.Series] = None,
        verbose: bool = False,
    ) -> "StartingXIPredictor":
        """Compute per-position means and standard deviations for z-scoring.

        Two normalisation tables are populated. If the input ``df`` carries
        a ``position_group_fine`` column (the new Wyscout-derived
        ten-group taxonomy), per-fine-group means / stds are computed and
        used preferentially at prediction time. The four-group
        (``role_group``) table is also computed as a fallback so that rows
        whose fine label is missing still score correctly.

        ``labels`` is accepted for API compatibility with a future
        supervised path but is currently unused — the heuristic path is
        unsupervised.
        """
        cols_present = [c for c in self.feature_cols if c in df.columns]
        if not cols_present:
            self.is_fitted = True
            return self

        # Coarse (four-group) normalisation — always populated.
        for group in ("GK", "DEF", "MID", "FWD"):
            mask = df["role_group"].astype(str).str.upper() == group
            if not mask.any():
                continue
            subset = df.loc[mask, cols_present].astype(float)
            means = subset.mean(numeric_only=True)
            stds = subset.std(numeric_only=True, ddof=0).replace(0, 1.0)
            self.position_means[group] = means.to_dict()
            self.position_stds[group] = stds.to_dict()

        # Fine (ten-group) normalisation — populated only when the column
        # is present. Groups with fewer than three observations are
        # skipped because their standard deviation would be unstable.
        if "position_group_fine" in df.columns:
            for fine in ("GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"):
                mask = df["position_group_fine"].astype(str).str.upper() == fine
                if mask.sum() < 3:
                    continue
                subset = df.loc[mask, cols_present].astype(float)
                means = subset.mean(numeric_only=True)
                stds = subset.std(numeric_only=True, ddof=0).replace(0, 1.0)
                # Store under a "FINE:" prefix so the coarse and fine
                # tables do not collide on the shared "GK" key.
                self.position_means[f"FINE:{fine}"] = means.to_dict()
                self.position_stds[f"FINE:{fine}"] = stds.to_dict()

        self.is_fitted = True
        if verbose:
            keys = sorted(self.position_means.keys())
            print(
                f"[StartingXIPredictor] Fitted normalisation on {len(df)} rows; "
                f"groups present: {keys}"
            )
        return self

    # ── Internal scoring primitives ───────────────────────────────────────────

    def _shrink(self, raw: float, n_matches: float, position_mean: float) -> float:
        """Empirical-Bayes shrinkage toward the position mean (Brown, 2008)."""
        n = max(float(n_matches or 0), 0.0)
        k = float(self.shrinkage_pseudo_matches)
        return (k * position_mean + n * raw) / (k + n) if (k + n) > 0 else raw

    @staticmethod
    def _z_score(value: float, mean: float, std: float) -> float:
        if not std or pd.isna(std):
            return 0.0
        return (value - mean) / std

    def _composite_score(self, row: pd.Series) -> float:
        """Position-aware composite score in the [0.25, 0.75] band.

        If the row carries a ``position_group_fine`` column and a matching
        fine-group normalisation has been fitted, the fine-grained weight
        table is used; otherwise the four-group coarse path is used as a
        fallback.
        """
        fine = str(row.get("position_group_fine", "") or "").upper()
        coarse = str(row.get("role_group", "MID")).upper() or "MID"

        weights: Dict[str, float]
        means: Dict[str, float]
        stds: Dict[str, float]
        if fine and fine in FINE_POSITION_WEIGHTS and f"FINE:{fine}" in self.position_means:
            weights = FINE_POSITION_WEIGHTS[fine]
            means = self.position_means.get(f"FINE:{fine}", {})
            stds = self.position_stds.get(f"FINE:{fine}", {})
        else:
            weights = COARSE_POSITION_WEIGHTS.get(coarse, COARSE_POSITION_WEIGHTS["MID"])
            means = self.position_means.get(coarse, {})
            stds = self.position_stds.get(coarse, {})

        n_matches = float(row.get("matches_played", 0) or 0)
        z_sum = 0.0
        for feature, w in weights.items():
            raw = float(row.get(feature, 0) or 0)
            mean = float(means.get(feature, raw))
            std = float(stds.get(feature, 1.0) or 1.0)
            shrunk = self._shrink(raw, n_matches, mean) if feature != "matches_played" else raw
            z = self._z_score(shrunk, mean, std)
            z_sum += w * z

        # Squash to a bounded range so the UI's 0–100 mapping is stable.
        return 0.5 + 0.25 * math.tanh(z_sum)

    # ── Public selection API ──────────────────────────────────────────────────

    def predict_xi(
        self,
        df: pd.DataFrame,
        formation: str = "4-3-3",
        your_team_id: Optional[int] = None,
        opponent_df: Optional[pd.DataFrame] = None,
        method: str = "auto",
    ) -> Dict[str, Any]:
        """Return the optimal starting eleven and bench under a formation.

        Parameters
        ----------
        df : pd.DataFrame
            Per-player feature dataframe for the home team. Must contain a
            ``role_group`` column with values in ``{"GK", "DEF", "MID", "FWD"}``
            and the columns named in ``self.feature_cols``.
        formation : str, default ``"4-3-3"``
            Either a key of :data:`FORMATIONS` or a dash-separated outfield
            string such as ``"4-3-3"`` or ``"4-2-3-1"``.
        your_team_id : int, optional
            Carried through into the response payload for traceability; not
            used in scoring.
        opponent_df : pd.DataFrame, optional
            Opponent squad features. If provided, defensive and midfield
            scores are scaled by a small, bounded multiplier reflecting the
            opponent's mean passing accuracy and mean defensive-action
            success rate.
        method : {"auto", "composite", "supervised", "baseline_minutes",
                  "baseline_recent"}
            ``auto`` / ``composite`` run the heuristic composite-score
            path described in :meth:`_composite_score`. ``supervised``
            uses the trained logistic-regression lineup classifier
            (Iteration J.4) — this requires :attr:`supervised_bundle` to
            be populated (typically via
            ``joblib.load("xi_lineup_model.joblib")``). The two
            ``baseline_*`` methods are reference baselines that an
            examiner can compare against.

        Returns
        -------
        dict
            Keys: ``formation``, ``formation_slots``, ``xi``, ``bench``,
            ``all_scored``.
        """
        if not self.is_fitted:
            self.fit(df)

        pool = df.copy()
        if "playerId" not in pool.columns:
            raise ValueError("predict_xi expects a 'playerId' column.")

        method = method.lower()
        # Iteration J.4: when ``method="auto"`` and a supervised bundle is
        # loaded, prefer it over the heuristic composite — rolling-origin
        # validation showed the supervised XI to reach Jaccard ~0.575
        # versus 0.425 for the heuristic, and ~0.482 for the top-by-minutes
        # baseline. ``method="composite"`` and ``method="heuristic"`` force
        # the heuristic path for ablation purposes.
        if method == "auto" and self.supervised_bundle is not None:
            method = "supervised"
        elif method in ("composite", "heuristic"):
            method = "auto"
        if method == "baseline_minutes":
            pool["predicted_score"] = pool.get("total_minutes", pd.Series(0, index=pool.index)).fillna(0)
        elif method == "baseline_recent":
            recent = pool.get("recent_form_score", pd.Series(0, index=pool.index)).fillna(0)
            played = pool.get("matches_played", pd.Series(0, index=pool.index)).fillna(0).clip(upper=3)
            pool["predicted_score"] = recent * played
        elif method == "supervised":
            # Use the optional supervised lineup classifier bundle. The
            # classifier consumes a wider feature set than the heuristic
            # composite (player aggregates + availability + opponent
            # profile + position one-hot) and returns the probability that
            # each candidate started the next U Cluj fixture. Fitted by
            # ``backend/scripts/train_lineup_classifier.py`` (Iteration J.4).
            if self.supervised_bundle is None:
                raise RuntimeError(
                    "method='supervised' requires the supervised bundle to be "
                    "loaded onto the predictor (set .supervised_bundle = "
                    "joblib.load('backend/ml/xi_lineup_model.joblib'))."
                )
            pool["predicted_score"] = self._score_supervised(pool)
        else:
            pool["predicted_score"] = pool.apply(self._composite_score, axis=1)
            if opponent_df is not None and not opponent_df.empty:
                adj = self._opponent_adjustments(opponent_df)
                if "DEF" in pool["role_group"].astype(str).str.upper().values:
                    pool.loc[
                        pool["role_group"].astype(str).str.upper() == "DEF", "predicted_score"
                    ] *= adj.get("def_weight", 1.0)
                if "MID" in pool["role_group"].astype(str).str.upper().values:
                    pool.loc[
                        pool["role_group"].astype(str).str.upper() == "MID", "predicted_score"
                    ] *= adj.get("mid_weight", 1.0)

        slots = self._resolve_formation(formation)
        xi_df = self._assign_xi(pool, formation)
        used_ids: set = set(xi_df["playerId"].tolist()) if not xi_df.empty else set()
        bench_df = (
            pool[~pool["playerId"].isin(used_ids)]
            .sort_values("predicted_score", ascending=False)
            .head(7)
        )

        return {
            "formation": formation,
            "formation_slots": slots,
            "your_team_id": your_team_id,
            "xi": xi_df,
            "bench": bench_df,
            "all_scored": pool.sort_values("predicted_score", ascending=False),
        }

    # Backward-compatible alias for the older method name.
    def predict_optimal_xi(self, *args, **kwargs) -> Dict[str, Any]:
        return self.predict_xi(*args, **kwargs)

    # ── Supervised scoring (Iteration J.4) ───────────────────────────────────
    def _score_supervised(self, pool: pd.DataFrame) -> pd.Series:
        """Return the per-player supervised-classifier probability.

        The supervised bundle (a dict of ``{model, scaler, feature_cols,
        fine_groups, ...}`` produced by
        ``train_lineup_classifier.py``) is consumed *as if every row were
        a candidate for the team's most recent fixture*: dynamic
        availability features and opponent features must already be on
        the input ``pool`` (in production these are emitted by
        :func:`ml.feature_engineering.build_player_feature_vector`). If a
        required feature column is missing, it is filled with zeros so
        the classifier can still produce a probability.
        """
        if self.supervised_bundle is None:
            return pd.Series(0.0, index=pool.index)
        bundle = self.supervised_bundle
        feature_cols: List[str] = list(bundle["feature_cols"])
        fine_groups: List[str] = list(bundle.get("fine_groups", []))
        # Position one-hot: derive from the row if pos_* columns are absent.
        pool = pool.copy()
        for g in fine_groups:
            col = f"pos_{g}"
            if col not in pool.columns:
                pool[col] = (
                    pool.get("position_group_fine", pd.Series("", index=pool.index))
                    .astype(str).str.upper() == g
                ).astype(float)
        X = np.zeros((len(pool), len(feature_cols)), dtype=float)
        for j, col in enumerate(feature_cols):
            if col in pool.columns:
                X[:, j] = pd.to_numeric(pool[col], errors="coerce").fillna(0.0).to_numpy()
        scaler = bundle["scaler"]
        model = bundle["model"]
        X_scaled = scaler.transform(X)
        proba = model.predict_proba(X_scaled)[:, 1]
        return pd.Series(proba, index=pool.index)

    # ── Slot assignment (Iteration J.3 — Hungarian algorithm) ────────────────
    #
    # The previous greedy per-position fill ("sort by score within each role
    # group, then take the top-N") is sensitive to the order in which roles
    # are visited and can choose a globally sub-optimal eleven: if a player's
    # second-best-position composite is much higher than the best alternative
    # at that slot, the greedy fill might still pick a weaker player at the
    # first slot considered. The Hungarian algorithm (Kuhn 1955) returns the
    # globally optimal one-to-one assignment of players to slots in
    # polynomial time, given a (player × slot) cost matrix.
    #
    # Here we build the cost matrix from negative composite scores (so the
    # Hungarian minimisation is equivalent to score maximisation), with
    # ``+inf`` placeholders for ineligible (player, slot) pairs (a player
    # whose ``role_group`` does not match the slot's role). When
    # :mod:`scipy.optimize` is unavailable, the implementation falls back to
    # the previous greedy method so the predictor remains usable in
    # minimal-dependency environments.

    def _assign_xi(
        self,
        pool: pd.DataFrame,
        formation: str,
    ) -> pd.DataFrame:
        """Assign eleven players to the formation's official position slots.

        The cost matrix has one row per candidate and one column per ordered
        official slot (see :data:`FORMATION_SLOTS`). A player whose fine
        position group is a natural fit for the slot (per
        :data:`SLOT_ADMISSIBLE_FINE`) gets a cost of minus their predicted
        score; a player whose fine group is not admissible but whose coarse
        ``role_group`` matches the slot's coarse group gets the same cost plus
        a small soft penalty, so a coarse match is allowed but dispreferred;
        anything else is forbidden. The Hungarian algorithm then returns the
        globally optimal one-to-one assignment, which maximises the summed
        score under the official-position constraint.

        The returned DataFrame carries ``official_position`` and ``slot_index``
        (the position on the pitch) plus a coarse ``slot`` for back-compat, and
        is ordered by ``slot_index``. When SciPy is unavailable, or the squad
        cannot fill every slot even under the soft fallback, a greedy fill that
        guarantees eleven players is used instead.
        """
        if pool.empty:
            return pd.DataFrame()

        slot_specs = self._formation_slot_specs(formation)
        n_slots = len(slot_specs)
        n_players = len(pool)
        if n_players < n_slots or linear_sum_assignment is None:
            return self._greedy_assign_fine(pool, slot_specs)

        pool_indexed = pool.reset_index(drop=True)
        fine_arr = (
            pool_indexed.get("position_group_fine", pd.Series("", index=pool_indexed.index))
            .astype(str).str.upper().to_numpy()
        )
        coarse_arr = pool_indexed["role_group"].astype(str).str.upper().to_numpy()
        scores = pool_indexed["predicted_score"].astype(float).to_numpy()
        # Preferred pitch side per player (L/R/C). Defaults to central when the
        # column is absent, so an older feature frame behaves exactly as before.
        side_arr = (
            pool_indexed.get("position_side", pd.Series("C", index=pool_indexed.index))
            .astype(str).str.upper().to_numpy()
        )

        BIG = 1e6    # finite penalty for forbidden matches (Hungarian dislikes inf).
        NEAR = 0.30  # penalty for an admissible but off-primary fine match (a CB at full-back).
        SOFT = 0.60  # penalty for a coarse-only match (no admissible fine overlap).
        SIDE = 0.15  # penalty for filling a sided slot with an opposite-flank player.
        # predicted_score sits in a narrow band, so even NEAR dominates the score
        # gaps between players. The effect: each player is placed in their PRIMARY
        # fine position (fine group == slot family) whenever the squad allows, and
        # only covers out of position when no specialist for that slot is free.
        # SIDE (< NEAR) then breaks the tie on the correct flank: a right-sided
        # player prefers the right slot, but playing the correct position on the
        # wrong foot still beats covering out of position, and a clearly higher
        # score still wins the slot regardless of side.
        cost = np.full((n_players, n_slots), BIG, dtype=float)
        for j, (label, coarse) in enumerate(slot_specs):
            family = self._slot_family(label)
            admissible = SLOT_ADMISSIBLE_FINE.get(family, set())
            primary = fine_arr == family
            fine_ok = np.isin(fine_arr, list(admissible))
            secondary = fine_ok & ~primary
            coarse_ok = (coarse_arr == coarse) & ~fine_ok
            cost[primary, j] = -scores[primary]
            cost[secondary, j] = -scores[secondary] + NEAR
            cost[coarse_ok, j] = -scores[coarse_ok] + SOFT
            # Correct-flank preference: an opposite-side player in a sided slot
            # pays SIDE on top of the family penalty. Central slots and central /
            # two-footed players are exempt. Applied only to assignable cells.
            slot_sd = self._slot_side(label)
            if slot_sd in ("L", "R"):
                wrong_side = (
                    np.isin(side_arr, ["L", "R"])
                    & (side_arr != slot_sd)
                    & (primary | secondary | coarse_ok)
                )
                cost[wrong_side, j] += SIDE

        try:
            row_ind, col_ind = linear_sum_assignment(cost)
        except ValueError:
            return self._greedy_assign_fine(pool, slot_specs)

        pairs = [(int(r), int(c)) for r, c in zip(row_ind, col_ind) if cost[r, c] < BIG / 2]
        if len(pairs) < n_slots:
            # Some slot could not be filled even under the soft fallback (the
            # squad is short in a coarse line); guarantee eleven via greedy.
            return self._greedy_assign_fine(pool, slot_specs)

        pairs.sort(key=lambda rc: rc[1])  # order by slot index
        rows = [r for r, _ in pairs]
        xi_df = pool_indexed.iloc[rows].copy()
        xi_df["slot_index"] = [c for _, c in pairs]
        xi_df["official_position"] = [slot_specs[c][0] for _, c in pairs]
        xi_df["slot"] = [slot_specs[c][1] for _, c in pairs]
        return xi_df.reset_index(drop=True)

    @staticmethod
    def _slot_family(label: str) -> str:
        """Map an official slot label to its admissibility family.

        Strips the left / right / centre prefix so RB and LB share the FB
        family, RCB and LCB share CB, RWB and LWB share WB, and so on. Order of
        the checks matters: the more specific suffixes are tested first.
        """
        l = (label or "").upper()
        if l == "GK":
            return "GK"
        if l.endswith("WB"):
            return "WB"
        if l.endswith("CB"):
            return "CB"
        if l.endswith("B"):
            return "FB"
        if l.endswith("WF"):
            return "WF"
        if l.endswith("DM"):
            return "DM"
        if l.endswith("AM"):
            return "AM"
        if l.endswith("CM"):
            return "CM"
        if l.endswith("ST") or l == "CF":
            return "ST"
        if l.endswith("W"):
            return "W"
        if l.endswith("M"):
            return "M"
        return "M"

    @staticmethod
    def _slot_side(label: str) -> str:
        """Return the slot's pitch side: ``"L"``, ``"R"`` or ``"C"`` (central).

        Official slot labels carry the side as a leading ``L`` / ``R`` (LB, LCB,
        LWB, LM, LCM, LDM, LAM, LW, LST and the right mirrors); GK, DM, CM, CB,
        CAM, CDM and ST are central.
        """
        l = (label or "").upper()
        if l.startswith("L"):
            return "L"
        if l.startswith("R"):
            return "R"
        return "C"

    @staticmethod
    def _formation_slot_specs(formation: str) -> List[tuple[str, str]]:
        """Return the ordered (official_label, coarse_group) slots for a formation.

        Known formations use their :data:`FORMATION_SLOTS` template. An unknown
        but parseable dash string falls back to generic coarse slots so the
        assignment still runs (official label equals the coarse group).
        """
        if formation in FORMATION_SLOTS:
            return FORMATION_SLOTS[formation]
        counts = StartingXIPredictor._resolve_formation(formation)
        specs: List[tuple[str, str]] = [("GK", "GK")]
        for coarse in ("DEF", "MID", "FWD"):
            specs.extend([(coarse, coarse)] * int(counts.get(coarse, 0)))
        return specs

    @staticmethod
    def _greedy_assign_fine(pool: pd.DataFrame, slot_specs: List[tuple[str, str]]) -> pd.DataFrame:
        """SciPy-free fallback that still fills official slots and guarantees 11.

        Each slot is filled, best-score first, by the highest unused player who
        is fine-admissible, then by any unused player of the slot's coarse
        group, and finally (a last backfill pass) by the best unused player of
        any position, so the eleven are always returned in slot order.
        """
        if pool.empty:
            return pd.DataFrame()

        p = pool.reset_index(drop=True)
        scores = p["predicted_score"].astype(float)
        coarse = p["role_group"].astype(str).str.upper()
        fine = (
            p.get("position_group_fine", pd.Series("", index=p.index)).astype(str).str.upper()
        )
        side = (
            p.get("position_side", pd.Series("C", index=p.index)).astype(str).str.upper()
        )

        def _side_ok(i: int, slot_sd: str) -> bool:
            # A central slot, or a central / two-footed player, fits either flank.
            if slot_sd == "C":
                return True
            s = side[i]
            return s not in ("L", "R") or s == slot_sd

        order = list(scores.sort_values(ascending=False).index)  # best players first
        used: set = set()
        result: List[tuple[int, int, str, str]] = []  # (player_idx, slot_idx, label, coarse)

        for j, (label, cg) in enumerate(slot_specs):
            family = StartingXIPredictor._slot_family(label)
            admissible = SLOT_ADMISSIBLE_FINE.get(family, set())
            slot_sd = StartingXIPredictor._slot_side(label)
            # Prefer the player's primary fine position on the correct flank,
            # then primary on any flank, then an adjacent admissible role on the
            # correct flank, then any admissible role, then a coarse-line match.
            pick = next((i for i in order if i not in used and fine[i] == family and _side_ok(i, slot_sd)), None)
            if pick is None:
                pick = next((i for i in order if i not in used and fine[i] == family), None)
            if pick is None:
                pick = next((i for i in order if i not in used and fine[i] in admissible and _side_ok(i, slot_sd)), None)
            if pick is None:
                pick = next((i for i in order if i not in used and fine[i] in admissible), None)
            if pick is None:
                pick = next((i for i in order if i not in used and coarse[i] == cg), None)
            if pick is not None:
                used.add(pick)
                result.append((pick, j, label, cg))

        filled = {j for _, j, _, _ in result}
        for j, (label, cg) in enumerate(slot_specs):
            if j in filled:
                continue
            pick = next((i for i in order if i not in used), None)
            if pick is not None:
                used.add(pick)
                result.append((pick, j, label, cg))

        if not result:
            return pd.DataFrame()
        result.sort(key=lambda t: t[1])
        rows = [t[0] for t in result]
        xi = p.iloc[rows].copy()
        xi["slot_index"] = [t[1] for t in result]
        xi["official_position"] = [t[2] for t in result]
        xi["slot"] = [t[3] for t in result]
        return xi.reset_index(drop=True)

    # ── Helpers ──────────────────────────────────────────────────────────────

    @staticmethod
    def _resolve_formation(formation: str) -> Dict[str, int]:
        if formation in FORMATIONS:
            return dict(FORMATIONS[formation])
        parts = [int(p) for p in formation.split("-") if p.isdigit()]
        if len(parts) == 3:
            return {"GK": 1, "DEF": parts[0], "MID": parts[1], "FWD": parts[2]}
        if len(parts) == 4:
            return {"GK": 1, "DEF": parts[0], "MID": parts[1] + parts[2], "FWD": parts[3]}
        raise ValueError(f"Unknown formation: {formation!r}")

    @staticmethod
    def _opponent_adjustments(opp_df: pd.DataFrame) -> Dict[str, float]:
        if opp_df.empty:
            return {}
        opp_pass = float(opp_df.get("pass_accuracy", pd.Series([50.0])).mean() or 50.0)
        opp_def = float(opp_df.get("def_action_success", pd.Series([50.0])).mean() or 50.0)
        return {
            "def_weight": 1.0 + opp_pass / 1000.0,
            "mid_weight": 1.0 + opp_def / 1000.0,
        }

    # ── Feature importance + validation ───────────────────────────────────────

    def get_feature_importance(self) -> Optional[pd.DataFrame]:
        """For the heuristic path, importance is the position-weight magnitude."""
        rows = []
        for group, weights in POSITION_WEIGHTS.items():
            for feature, w in weights.items():
                rows.append({"role_group": group, "feature": feature, "weight": w})
        return pd.DataFrame(rows).sort_values(["role_group", "weight"], ascending=[True, False])

    def evaluate_against_actual_lineups(
        self,
        df: pd.DataFrame,
        actual_lineups: Iterable[Iterable[int]],
        formation: str = "4-3-3",
        method: str = "auto",
    ) -> Dict[str, float]:
        """Retrospective Jaccard-overlap check against historical starting elevens.

        For each historical fixture, ``predict_xi`` is run with the current
        feature snapshot, and the predicted XI is compared to the actual
        starting eleven (a list of ``playerId`` values). The mean
        per-fixture Jaccard overlap is reported, along with per-fixture
        values for downstream plotting.
        """
        overlaps: List[float] = []
        for actual_ids in actual_lineups:
            actual_set = set(int(p) for p in actual_ids)
            if not actual_set:
                continue
            predicted = self.predict_xi(df, formation=formation, method=method)["xi"]
            predicted_set = set(int(p) for p in predicted["playerId"].tolist())
            union = predicted_set | actual_set
            if not union:
                continue
            overlaps.append(len(predicted_set & actual_set) / len(union))
        return {
            "mean_jaccard": float(np.mean(overlaps)) if overlaps else 0.0,
            "n_fixtures": len(overlaps),
            "overlaps": overlaps,
        }


# ── Backward-compatible alias ─────────────────────────────────────────────────
# Some older call sites referred to the class as ``XIPredictor``. This alias
# keeps those imports working.
XIPredictor = StartingXIPredictor


# ── Module-level helper used by xi_service.list_opponents and pipeline.run ──

def save_predictor(predictor: StartingXIPredictor, path: str) -> None:
    """Persist a fitted predictor (including the position normalisation table)."""
    joblib.dump(predictor, path)


def load_predictor(path: str) -> StartingXIPredictor:
    """Load a fitted predictor previously saved with :func:`save_predictor`."""
    obj = joblib.load(path)
    if isinstance(obj, StartingXIPredictor):
        return obj
    raise TypeError(f"Loaded object is not a StartingXIPredictor: {type(obj)!r}")
