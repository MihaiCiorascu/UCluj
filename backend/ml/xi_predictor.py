"""
Starting-XI Predictor for UmbraRo.

Scores every available player by a position-aware composite of per-90 KPIs,
z-scored within the player's positional group and shrunk toward the position
mean for low-sample players via an empirical-Bayes update. The eleven players
are then assigned to formation slots under a one-to-one slot constraint.
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


# Maximum number of players placed on the bench, sized to a realistic matchday squad.
MAX_BENCH = 12


# Formation library
# Maps each positional group to its slot count. Mirrors the Flutter
# ``kSupportedFormations`` list so every pickable option has a backend layout.
FORMATIONS: Dict[str, Dict[str, int]] = {
    "4-4-2":   {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-3-3":   {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3},
    "4-2-3-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-5-1":   {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-1-4-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-3-2-1": {"GK": 1, "DEF": 4, "MID": 5, "FWD": 1},
    "4-2-2-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-4-1-1": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-3-1-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "4-1-2-1-2": {"GK": 1, "DEF": 4, "MID": 4, "FWD": 2},
    "3-1-4-2": {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-5-2":   {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-4-3":   {"GK": 1, "DEF": 3, "MID": 4, "FWD": 3},
    "3-4-2-1": {"GK": 1, "DEF": 3, "MID": 6, "FWD": 1},
    "3-4-1-2": {"GK": 1, "DEF": 3, "MID": 5, "FWD": 2},
    "3-6-1":   {"GK": 1, "DEF": 3, "MID": 6, "FWD": 1},
    "5-3-2":   {"GK": 1, "DEF": 5, "MID": 3, "FWD": 2},
    "5-4-1":   {"GK": 1, "DEF": 5, "MID": 4, "FWD": 1},
}

# Official-position slot templates: ordered (official_label, coarse_group)
# tuples per formation. The order is the slot_index: GK at 0, then lines run
# back to front (defence, midfield, attack), left to right within each line.
# lib/core/constants/formation_slots.dart mirrors this order; keep the two in sync.
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
    "4-4-1-1": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RM", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LM", "MID"),
        ("SS", "FWD"), ("ST", "FWD"),
    ],
    "4-3-1-2": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("RCM", "MID"), ("CM", "MID"), ("LCM", "MID"),
        ("CAM", "MID"),
        ("SS", "FWD"), ("ST", "FWD"),
    ],
    "4-1-2-1-2": [
        ("GK", "GK"),
        ("RB", "DEF"), ("RCB", "DEF"), ("LCB", "DEF"), ("LB", "DEF"),
        ("DM", "MID"),
        ("RCM", "MID"), ("LCM", "MID"),
        ("CAM", "MID"),
        ("SS", "FWD"), ("ST", "FWD"),
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
    "3-4-2-1": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("RWB", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LWB", "MID"),
        ("RAM", "MID"), ("LAM", "MID"),
        ("ST", "FWD"),
    ],
    "3-4-1-2": [
        ("GK", "GK"),
        ("RCB", "DEF"), ("CB", "DEF"), ("LCB", "DEF"),
        ("RWB", "MID"), ("RCM", "MID"), ("LCM", "MID"), ("LWB", "MID"),
        ("CAM", "MID"),
        ("RST", "FWD"), ("LST", "FWD"),
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

# Formations offered to the coach and searched by the auto-best routine. The
# full :data:`FORMATION_SLOTS` library is kept whole so concluded matches can
# still render their real Sportradar shapes, which may fall outside this set.
CURATED_FORMATIONS: List[str] = [
    "4-3-3",
    "4-2-3-1",
    "4-4-2",
    "3-5-2",
    "3-4-3",
    "5-3-2",
    "4-1-4-1",
    "4-3-1-2",
    "3-4-2-1",
    "4-1-2-1-2",
    "4-4-1-1",
    "5-4-1",
    "3-1-4-2",
    "4-3-2-1",
    "3-4-1-2",
]

# Which fine-position groups (ten-group Wyscout taxonomy: GK, CB, FB, WB, DM,
# CM, AM, W, WF, ST) may fill a slot family (the official label stripped of its
# left/right/centre prefix, see ``_slot_family``). First group is the natural
# fit; the rest are adjacent roles so assignment never fails for lack of a specialist.
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
    # Second striker / withdrawn forward: a forward, so ST is the natural fit,
    # but often a wide-forward or advanced playmaker dropping in, hence AM and WF too.
    "SS": {"ST", "WF", "AM", "W"},
}


def _validate_formation_slots() -> None:
    """Fail fast at import if a slot template is inconsistent: exactly eleven
    slots, GK at index 0, coarse counts matching ``FORMATIONS``."""
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

# Position-specific composite-score weights. Each weight applies to a z-scored,
# shrinkage-corrected feature; the linear combination is tanh-squashed to stay
# in [0.25, 0.75] for the UI. COARSE_POSITION_WEIGHTS keeps the four-group
# GK / DEF / MID / FWD path; FINE_POSITION_WEIGHTS covers the ten Wyscout-derived
# fine groups (CB, FB, WB, DM, CM, AM, W, WF, ST, GK) and is preferred whenever a
# ``position_group_fine`` column is present (from
# :func:`ml.feature_engineering.derive_primary_fine_position`).

# The ``availability_score`` weight aggregates: (i) minutes share over the last
# five fixtures, (ii) whether the player started the most recent fixture, and
# (iii) a long-gap penalty (see
# :func:`ml.feature_engineering.compute_availability_features`). It restores the
# participation signal that per-90 KPI normalisation discards.
#
# Per-position availability weights:
#   GK ~ 0.10: goalkeepers rotate rarely, so per-90 KPIs stay informative alone.
#   Outfield ~ 0.20: rotated on fitness and match-ups, so availability matters.
#   Strikers ~ 0.25: additionally rotated for opponent-specific reasons.
#
# Remaining weights are renormalised so each row sums to 1.0 for interpretability;
# the tanh squash would behave identically under a constant rescale.

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
        ``auto`` and ``heuristic`` use the position-aware composite-score path.
        ``model`` is reserved for a future supervised extension and currently
        behaves identically to ``heuristic``.
    shrinkage_pseudo_matches : float, default 3.0
        Pseudo-count ``k`` in the empirical-Bayes update
        ``(k * position_mean + n * raw) / (k + n)``. Following Brown (2008),
        ``k = 3`` gives moderate shrinkage for a five-season squad sample.
    decay_half_life_days : float, default 30.0
        Half-life of the exponential time decay applied when ``recent_form``
        inputs include per-match timestamps. Larger values trust older matches more.
    feature_cols : list of str, optional
        Feature columns used by the composite score. Defaults to
        ``DEFAULT_FEATURE_COLS``.
    """

    model_type: str = "auto"
    shrinkage_pseudo_matches: float = 3.0
    decay_half_life_days: float = 30.0
    feature_cols: List[str] = field(default_factory=lambda: list(DEFAULT_FEATURE_COLS))

    # Fitted state: populated by .fit() and persisted by joblib.dump()
    position_means: Dict[str, Dict[str, float]] = field(default_factory=dict)
    position_stds: Dict[str, Dict[str, float]] = field(default_factory=dict)
    is_fitted: bool = False

    # Optional supervised lineup-classifier bundle (loaded lazily). When set, the
    # ``method="supervised"`` branch of :meth:`predict_xi` scores players via the
    # logistic-regression P(started|features) probability instead of the heuristic
    # composite. Trained by ``backend/scripts/train_lineup_classifier.py`` and
    # persisted to ``backend/ml/xi_lineup_model.joblib``.
    supervised_bundle: Optional[Dict[str, Any]] = None

    # Fit

    def fit(
        self,
        df: pd.DataFrame,
        labels: Optional[pd.Series] = None,
        verbose: bool = False,
    ) -> "StartingXIPredictor":
        """Compute per-position means and standard deviations for z-scoring.

        Populates two tables. When ``df`` carries a ``position_group_fine``
        column, per-fine-group means/stds are computed and preferred at
        prediction time; the four-group ``role_group`` table is always computed
        as a fallback for rows whose fine label is missing.

        ``labels`` is accepted for API compatibility with a future supervised
        path but is currently unused.
        """
        cols_present = [c for c in self.feature_cols if c in df.columns]
        if not cols_present:
            self.is_fitted = True
            return self

        # Coarse (four-group) normalisation: always populated.
        for group in ("GK", "DEF", "MID", "FWD"):
            mask = df["role_group"].astype(str).str.upper() == group
            if not mask.any():
                continue
            subset = df.loc[mask, cols_present].astype(float)
            means = subset.mean(numeric_only=True)
            stds = subset.std(numeric_only=True, ddof=0).replace(0, 1.0)
            self.position_means[group] = means.to_dict()
            self.position_stds[group] = stds.to_dict()

        # Fine (ten-group) normalisation: only when the column is present.
        # Groups with fewer than three observations are skipped (unstable std).
        if "position_group_fine" in df.columns:
            for fine in ("GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"):
                mask = df["position_group_fine"].astype(str).str.upper() == fine
                if mask.sum() < 3:
                    continue
                subset = df.loc[mask, cols_present].astype(float)
                means = subset.mean(numeric_only=True)
                stds = subset.std(numeric_only=True, ddof=0).replace(0, 1.0)
                # "FINE:" prefix so coarse and fine tables do not collide on "GK".
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

    # Internal scoring primitives

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

        Uses the fine-grained weight table when the row has a
        ``position_group_fine`` column and a matching fine-group normalisation
        was fitted; otherwise falls back to the four-group coarse path.
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

        # Squash to a bounded range so the UI's 0 to 100 mapping is stable.
        return 0.5 + 0.25 * math.tanh(z_sum)

    # Public selection API

    def predict_xi(
        self,
        df: pd.DataFrame,
        formation: str = "auto",
        your_team_id: Optional[int] = None,
        opponent_df: Optional[pd.DataFrame] = None,
        method: str = "auto",
        locked: Optional[Dict[int, int]] = None,
        opponent_short: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Return the optimal starting eleven and bench under a formation.

        Parameters
        ----------
        df : pd.DataFrame
            Per-player feature dataframe for the home team. Must contain a
            ``role_group`` column with values in ``{"GK", "DEF", "MID", "FWD"}``
            and the columns named in ``self.feature_cols``.
        formation : str, default ``"auto"``
            Either ``"auto"`` (search :data:`CURATED_FORMATIONS` and pick the
            shape with the highest total assignment objective), a key of
            :data:`FORMATIONS` (use exactly that shape), or a dash-separated
            outfield string such as ``"4-3-3"`` or ``"4-2-3-1"``. The chosen
            shape is reported back in the response's ``formation`` field.
        locked : dict[int, int], optional
            Mapping of ``slot_index -> playerId`` pinned before assignment (see
            :meth:`_assign_xi`). With ``formation="auto"`` the best shape is
            chosen with these locks applied per formation; a formation whose slot
            count cannot host a locked slot index is skipped.
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
            uses the trained logistic-regression lineup classifier, which
            requires :attr:`supervised_bundle` to be populated (typically
            via ``joblib.load("xi_lineup_model.joblib")``). The two
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
        # When ``method="auto"`` and a supervised bundle is loaded, prefer it
        # over the heuristic composite: rolling-origin validation showed the
        # supervised XI reaching Jaccard ~0.575 versus 0.425 for the heuristic
        # and ~0.482 for the top-by-minutes baseline. ``method="composite"``
        # and ``method="heuristic"`` force the heuristic path for ablation.
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
            # Optional supervised lineup classifier: consumes a wider feature set
            # (player aggregates, availability, opponent profile, position one-hot)
            # and returns P(started next fixture). Fitted by
            # ``backend/scripts/train_lineup_classifier.py``.
            if self.supervised_bundle is None:
                raise RuntimeError(
                    "method='supervised' requires the supervised bundle to be "
                    "loaded onto the predictor (set .supervised_bundle = "
                    "joblib.load('backend/ml/xi_lineup_model.joblib'))."
                )
            pool["predicted_score"] = self._score_supervised(pool, opponent_short=opponent_short)
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

        # Resolve the formation. ``"auto"`` searches the curated set for the
        # highest total assignment objective on the already-scored pool (one
        # Hungarian solve per shape, scores not recomputed). An explicit
        # formation is used as given.
        formation_scores: Dict[str, float] = {}
        if str(formation).lower() == "auto":
            resolved_formation, xi_df, total_score, formation_scores = (
                self._best_formation(pool, locked=locked)
            )
        else:
            resolved_formation = formation
            xi_df, total_score = self._assign_xi(pool, formation, locked=locked)
            formation_scores = {resolved_formation: total_score}

        slots = self._resolve_formation(resolved_formation)
        used_ids: set = set(xi_df["playerId"].tolist()) if not xi_df.empty else set()
        bench_df = (
            pool[~pool["playerId"].isin(used_ids)]
            .sort_values("predicted_score", ascending=False)
            .head(MAX_BENCH)
        )

        return {
            "formation": resolved_formation,
            "formation_slots": slots,
            "formation_scores": formation_scores,
            "your_team_id": your_team_id,
            "xi": xi_df,
            "bench": bench_df,
            "all_scored": pool.sort_values("predicted_score", ascending=False),
        }

    # Auto-best-formation search
    def _best_formation(
        self,
        pool: pd.DataFrame,
        locked: Optional[Dict[int, int]] = None,
    ) -> tuple[str, pd.DataFrame, float, Dict[str, float]]:
        """Pick the curated formation that maximises the assignment objective.

        The pool already carries ``predicted_score``. Each
        :data:`CURATED_FORMATIONS` shape is solved with :meth:`_assign_xi` and
        the highest ``total_score`` wins; scores are never recomputed.

        With ``locked`` set, a formation is skipped when any locked
        ``slot_index`` falls outside its eleven slots. If every formation is
        skipped, the search retries with the locks dropped so an XI still results.

        Returns ``(formation, xi_df, total_score, formation_scores)`` where
        ``formation_scores`` maps every evaluated formation to its objective for
        a why-this-shape explainer.
        """
        best_name: Optional[str] = None
        best_xi: pd.DataFrame = pd.DataFrame()
        best_total = float("-inf")
        scores: Dict[str, float] = {}

        max_locked_slot = max(locked.keys()) if locked else -1

        for name in CURATED_FORMATIONS:
            n_slots = len(self._formation_slot_specs(name))
            use_locked = locked
            if locked and max_locked_slot >= n_slots:
                # A locked slot index does not exist in this shape: skip it.
                continue
            xi_df, total = self._assign_xi(pool, name, locked=use_locked)
            scores[name] = float(total)
            if total > best_total:
                best_total = float(total)
                best_name = name
                best_xi = xi_df

        if best_name is None:
            # Every shape was skipped by an out-of-range lock; retry without
            # locks so an XI still comes back.
            for name in CURATED_FORMATIONS:
                xi_df, total = self._assign_xi(pool, name, locked=None)
                scores[name] = float(total)
                if total > best_total:
                    best_total = float(total)
                    best_name = name
                    best_xi = xi_df

        if best_name is None:
            best_name = CURATED_FORMATIONS[0]
            best_xi, best_total = self._assign_xi(pool, best_name, locked=None)
            best_total = float(best_total)

        return best_name, best_xi, best_total, scores

    # Backward-compatible alias for the older method name.
    def predict_optimal_xi(self, *args, **kwargs) -> Dict[str, Any]:
        return self.predict_xi(*args, **kwargs)

    # Supervised scoring
    def _score_supervised(self, pool: pd.DataFrame, opponent_short: Optional[str] = None) -> pd.Series:
        """Return the per-player supervised-classifier probability.

        The bundle (``{model, scaler, feature_cols, fine_groups, ...}`` from
        ``train_lineup_classifier_league.py``) treats every row as a candidate
        for the team's most recent fixture. Availability features come upstream
        from :func:`ml.feature_engineering.build_player_feature_vector`; the
        position one-hot and opponent-archetype x position interactions are
        derived here from ``position_group_fine`` and ``opponent_short``. Missing
        feature columns are filled with zeros.
        """
        if self.supervised_bundle is None:
            return pd.Series(0.0, index=pool.index)
        bundle = self.supervised_bundle
        feature_cols: List[str] = list(bundle["feature_cols"])
        fine_groups: List[str] = list(bundle.get("fine_groups", []))
        # Position one-hot: derive from the row if pos_* columns are absent.
        pool = pool.copy()
        fine_upper = (
            pool.get("position_group_fine", pd.Series("", index=pool.index))
            .astype(str).str.upper()
        )
        for g in fine_groups:
            col = f"pos_{g}"
            if col not in pool.columns:
                pool[col] = (fine_upper == g).astype(float)
        # Opponent-archetype x position interaction: the one opponent signal that
        # varies across candidates within a fixture, so it shifts the picked XI by
        # opponent. All zero when the archetype is unknown (graceful no-op).
        inter_cols: List[str] = list(bundle.get("opp_interaction_cols") or [])
        if inter_cols:
            for col in inter_cols:
                pool[col] = 0.0
            cl = (bundle.get("opp_cluster_team_map") or {}).get(opponent_short)
            if cl is not None:
                inter_set = set(inter_cols)
                for a in bundle.get("opp_interaction_attrs", []):
                    col = f"oppcl{cl}_x_{a}"
                    if col in inter_set:
                        pool[col] = pd.to_numeric(
                            pool.get(a, 0.0), errors="coerce").fillna(0.0)
        X = np.zeros((len(pool), len(feature_cols)), dtype=float)
        for j, col in enumerate(feature_cols):
            if col in pool.columns:
                X[:, j] = pd.to_numeric(pool[col], errors="coerce").fillna(0.0).to_numpy()
        scaler = bundle["scaler"]
        model = bundle["model"]
        X_scaled = scaler.transform(X)
        proba = model.predict_proba(X_scaled)[:, 1]
        return pd.Series(proba, index=pool.index)

    # Slot assignment (Hungarian algorithm)
    #
    # A greedy per-position fill is order-sensitive and can pick a globally
    # sub-optimal eleven. The Hungarian algorithm (Kuhn 1955) returns the
    # globally optimal one-to-one player-to-slot assignment in polynomial time,
    # given a (player x slot) cost matrix. The cost matrix uses negative composite
    # scores (minimisation equals score maximisation), with finite penalties for
    # ineligible pairs. Falls back to greedy when :mod:`scipy.optimize` is absent.

    def _assign_xi(
        self,
        pool: pd.DataFrame,
        formation: str,
        locked: Optional[Dict[int, int]] = None,
    ) -> tuple[pd.DataFrame, float]:
        """Assign eleven players to the formation's official position slots.

        The cost matrix has one row per candidate and one column per ordered
        official slot (see :data:`FORMATION_SLOTS`). A fine-position natural fit
        (per :data:`SLOT_ADMISSIBLE_FINE`) costs minus the predicted score; a
        coarse-only ``role_group`` match adds a soft penalty; anything else is
        forbidden. The Hungarian solve then maximises the summed score under the
        official-position constraint.

        Parameters
        ----------
        pool : pd.DataFrame
            The scored player pool (carrying ``predicted_score``).
        formation : str
            A :data:`FORMATION_SLOTS` key (or a parseable dash string).
        locked : dict[int, int], optional
            Mapping of ``slot_index -> playerId``. Each valid entry pins that
            player to that slot: the player and slot are removed from the matrix,
            the remainder is solved optimally, and the two are merged. Invalid
            locks are ignored: a ``playerId`` not in ``pool``, an out-of-range
            ``slot_index``, and duplicate pins (a player pinned twice keeps the first).

        Returns
        -------
        tuple[pd.DataFrame, float]
            ``(xi_df, total_score)``. ``xi_df`` carries ``official_position`` and
            ``slot_index`` plus a coarse ``slot`` for back-compat, ordered by
            ``slot_index``. ``total_score`` sums the assigned pairs' values
            (``predicted_score`` minus the NEAR / SOFT / SIDE penalty) and is the
            quantity the auto-best-formation routine maximises. When SciPy is
            absent, or the squad cannot fill every slot, a greedy fill guarantees
            eleven and its ``total_score`` is the summed raw predicted score (no
            penalty bookkeeping), sufficient because greedy is a degenerate fallback.
        """
        if pool.empty:
            return pd.DataFrame(), 0.0

        slot_specs = self._formation_slot_specs(formation)
        n_slots = len(slot_specs)

        # Normalise the lock map: keep only valid (slot_index, playerId) pairs
        # (slot in range, player present in pool). A player pinned to more than
        # one slot keeps the first seen, so no player is double-assigned.
        valid_locks: Dict[int, int] = {}
        if locked:
            pool_pids = set(int(p) for p in pool.get("playerId", pd.Series(dtype=int)).tolist())
            seen_pids: set = set()
            for slot_idx, pid in locked.items():
                try:
                    slot_idx = int(slot_idx)
                    pid = int(pid)
                except (TypeError, ValueError):
                    continue
                if slot_idx < 0 or slot_idx >= n_slots:
                    continue
                if pid not in pool_pids or pid in seen_pids:
                    continue
                valid_locks[slot_idx] = pid
                seen_pids.add(pid)

        pool_indexed = pool.reset_index(drop=True)
        n_players = len(pool_indexed)
        if n_players < n_slots or linear_sum_assignment is None:
            return self._greedy_assign_fine(pool_indexed, slot_specs, valid_locks)

        fine_arr = (
            pool_indexed.get("position_group_fine", pd.Series("", index=pool_indexed.index))
            .astype(str).str.upper().to_numpy()
        )
        coarse_arr = pool_indexed["role_group"].astype(str).str.upper().to_numpy()
        scores = pool_indexed["predicted_score"].astype(float).to_numpy()
        pid_arr = pool_indexed["playerId"].astype(int).to_numpy()
        # Preferred pitch side per player (L/R/C). Defaults to central when the
        # column is absent, so an older feature frame behaves as before.
        side_arr = (
            pool_indexed.get("position_side", pd.Series("C", index=pool_indexed.index))
            .astype(str).str.upper().to_numpy()
        )

        BIG = 1e6    # finite penalty for forbidden matches (Hungarian dislikes inf).
        NEAR = 0.30  # penalty for an admissible but off-primary fine match (a CB at full-back).
        SOFT = 0.60  # penalty for a coarse-only match (no admissible fine overlap).
        SIDE = 0.15  # penalty for filling a sided slot with an opposite-flank player.
        # predicted_score sits in a narrow band, so these penalties dominate the
        # score gaps: players take their primary fine position when available,
        # SIDE (< NEAR) breaks flank ties, and a clearly higher score still wins.
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
            # pays SIDE on top of the family penalty. Central slots and central,
            # two-footed players are exempt. Applied only to assignable cells.
            slot_sd = self._slot_side(label)
            if slot_sd in ("L", "R"):
                wrong_side = (
                    np.isin(side_arr, ["L", "R"])
                    & (side_arr != slot_sd)
                    & (primary | secondary | coarse_ok)
                )
                cost[wrong_side, j] += SIDE

        # Pre-pin the locked pairs and solve the open remainder. A lock costs its
        # cell in the full matrix (so an out-of-position lock still contributes the
        # right penalty to ``total_score``), unless the cell is forbidden (>= BIG/2),
        # where it contributes the bare ``-predicted_score``: the coach's explicit
        # choice overrides the position-eligibility rule.
        pid_to_row = {int(p): i for i, p in enumerate(pid_arr)}
        locked_rows = {pid_to_row[pid] for pid in valid_locks.values()}
        locked_slots = set(valid_locks.keys())

        locked_pairs: List[tuple[int, int]] = []
        locked_total = 0.0
        for slot_idx, pid in valid_locks.items():
            r = pid_to_row[pid]
            cell = cost[r, slot_idx]
            value = -scores[r] if cell >= BIG / 2 else cell
            locked_total += -value  # value is a (possibly penalised) negative score
            locked_pairs.append((r, slot_idx))

        open_rows = [i for i in range(n_players) if i not in locked_rows]
        open_cols = [j for j in range(n_slots) if j not in locked_slots]

        open_pairs: List[tuple[int, int]] = []
        open_total = 0.0
        if open_cols:
            sub = cost[np.ix_(open_rows, open_cols)]
            try:
                sub_r, sub_c = linear_sum_assignment(sub)
            except ValueError:
                return self._greedy_assign_fine(pool_indexed, slot_specs, valid_locks)
            for sr, sc in zip(sub_r, sub_c):
                if sub[sr, sc] >= BIG / 2:
                    continue
                r = open_rows[int(sr)]
                c = open_cols[int(sc)]
                open_pairs.append((r, c))
                open_total += -sub[sr, sc]

        pairs = locked_pairs + open_pairs
        if len(pairs) < n_slots:
            # Some slot could not be filled even under the soft fallback (the
            # squad is short in a coarse line); guarantee eleven via greedy.
            return self._greedy_assign_fine(pool_indexed, slot_specs, valid_locks)

        total_score = locked_total + open_total
        pairs.sort(key=lambda rc: rc[1])  # order by slot index
        rows = [r for r, _ in pairs]
        xi_df = pool_indexed.iloc[rows].copy()
        xi_df["slot_index"] = [c for _, c in pairs]
        xi_df["official_position"] = [slot_specs[c][0] for _, c in pairs]
        xi_df["slot"] = [slot_specs[c][1] for _, c in pairs]
        return xi_df.reset_index(drop=True), float(total_score)

    @staticmethod
    def _slot_family(label: str) -> str:
        """Map an official slot label to its admissibility family.

        Strips the left/right/centre prefix so RB and LB share FB, RCB and LCB
        share CB, and so on. Check order matters: more specific suffixes first.
        SS maps to its own family (admits ST, WF, AM); CF stays in ST.
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
        if l == "SS":
            return "SS"
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

        Side is the leading ``L``/``R`` of the label (LB, LCB, LWB, and the right
        mirrors); GK, DM, CM, CB, CAM, CDM and ST are central.
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

        Known formations use their :data:`FORMATION_SLOTS` template; an unknown
        but parseable dash string falls back to generic coarse slots (official
        label equals the coarse group).
        """
        if formation in FORMATION_SLOTS:
            return FORMATION_SLOTS[formation]
        counts = StartingXIPredictor._resolve_formation(formation)
        specs: List[tuple[str, str]] = [("GK", "GK")]
        for coarse in ("DEF", "MID", "FWD"):
            specs.extend([(coarse, coarse)] * int(counts.get(coarse, 0)))
        return specs

    @staticmethod
    def _greedy_assign_fine(
        pool: pd.DataFrame,
        slot_specs: List[tuple[str, str]],
        locked: Optional[Dict[int, int]] = None,
    ) -> tuple[pd.DataFrame, float]:
        """SciPy-free fallback that fills official slots and guarantees eleven.

        Each slot is filled best-score first: highest unused fine-admissible
        player, then any unused coarse-group player, then a final backfill by
        best unused player of any position. Valid locks (``slot_index ->
        playerId``) are pinned first and excluded from the open fill. Returns
        ``(xi_df, total_score)`` with ``total_score`` the summed raw predicted
        score (no Hungarian penalty bookkeeping).
        """
        if pool.empty:
            return pd.DataFrame(), 0.0

        p = pool.reset_index(drop=True)
        scores = p["predicted_score"].astype(float)
        coarse = p["role_group"].astype(str).str.upper()
        fine = (
            p.get("position_group_fine", pd.Series("", index=p.index)).astype(str).str.upper()
        )
        side = (
            p.get("position_side", pd.Series("C", index=p.index)).astype(str).str.upper()
        )

        n_slots = len(slot_specs)
        # Validate the locks against this (already index-reset) pool.
        valid_locks: Dict[int, int] = {}
        if locked:
            pid_to_idx = {int(pid): i for i, pid in enumerate(p["playerId"].astype(int).tolist())}
            seen: set = set()
            for slot_idx, pid in locked.items():
                try:
                    slot_idx = int(slot_idx)
                    pid = int(pid)
                except (TypeError, ValueError):
                    continue
                if slot_idx < 0 or slot_idx >= n_slots or pid not in pid_to_idx or pid in seen:
                    continue
                valid_locks[slot_idx] = pid
                seen.add(pid)

        def _side_ok(i: int, slot_sd: str) -> bool:
            # A central slot, or a central, two-footed player, fits either flank.
            if slot_sd == "C":
                return True
            s = side[i]
            return s not in ("L", "R") or s == slot_sd

        order = list(scores.sort_values(ascending=False).index)  # best players first
        used: set = set()
        result: List[tuple[int, int, str, str]] = []  # (player_idx, slot_idx, label, coarse)

        # Pin the locked players first.
        pid_to_idx = {int(pid): i for i, pid in enumerate(p["playerId"].astype(int).tolist())}
        for slot_idx, pid in valid_locks.items():
            i = pid_to_idx[pid]
            used.add(i)
            label, cg = slot_specs[slot_idx]
            result.append((i, slot_idx, label, cg))

        locked_slots = set(valid_locks.keys())
        for j, (label, cg) in enumerate(slot_specs):
            if j in locked_slots:
                continue
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
            return pd.DataFrame(), 0.0
        result.sort(key=lambda t: t[1])
        rows = [t[0] for t in result]
        xi = p.iloc[rows].copy()
        xi["slot_index"] = [t[1] for t in result]
        xi["official_position"] = [t[2] for t in result]
        xi["slot"] = [t[3] for t in result]
        total_score = float(scores.iloc[rows].sum())
        return xi.reset_index(drop=True), total_score

    # Helpers

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

    # Feature importance and validation

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

        Runs ``predict_xi`` per fixture and compares the predicted XI to the
        actual starting eleven (``playerId`` values). Reports the mean
        per-fixture Jaccard overlap plus the per-fixture values for plotting.
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


# Backward-compatible alias for older call sites that used ``XIPredictor``.
XIPredictor = StartingXIPredictor


# Module-level helpers used by xi_service.list_opponents and pipeline.run

def save_predictor(predictor: StartingXIPredictor, path: str) -> None:
    """Persist a fitted predictor (including the position normalisation table)."""
    joblib.dump(predictor, path)


def load_predictor(path: str) -> StartingXIPredictor:
    """Load a fitted predictor previously saved with :func:`save_predictor`."""
    obj = joblib.load(path)
    if isinstance(obj, StartingXIPredictor):
        return obj
    raise TypeError(f"Loaded object is not a StartingXIPredictor: {type(obj)!r}")
