"""
Opponent style-profile features for the Starting-XI predictor (Iteration J).

A coach's lineup decisions are not just a function of their own players'
form — they also reflect the opponent's recent tactical profile. Against a
team that presses high, the coach favours composed centre-backs and
ball-retentive midfielders; against a low block, they favour progressive
midfielders and wide creators. The previous version of the XI predictor
ignored this context entirely; this module restores it.

The profile is computed from the team-level dataset ``data/All_Data.csv``,
which carries rolling five-match averages of each team's possession,
shots, shots-on-target, corners, goals scored / conceded, points,
yellow cards, and goalkeeper saves at the moment of each fixture
(:func:`Home_*_5` and :func:`Away_*_5` columns). For a given fixture, the
*opponent profile* is simply the opponent's rolling-5 vector.

References
----------
- Lago-Peñas, C. (2009). *The influence of match location, quality of
  opposition, and match status on possession strategies in professional
  association football.* Journal of Sports Sciences 27(13), 1463–1467.
  Establishes that opponent quality conditions team behaviour.
- Bornn, L., Cervone, D. and Fernández, J. (2018). *Soccer Analytics:
  Unravelling the complexity of `the beautiful game'.* Significance 15(3),
  26–29. Motivates context-aware analytics in association football.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np
import pandas as pd


# ── Style profile columns ────────────────────────────────────────────────────
# These are the rolling-5 features available in ``All_Data.csv``. The
# profile is computed by selecting the opponent's side of the fixture
# (home or away), which is determined by whether the home-team substring
# matches the home- or away-team column.

OPPONENT_STYLE_COLUMNS_RAW: List[str] = [
    "Poss_5",        # rolling possession share, %
    "Shots_5",       # rolling shots per match
    "SoT_5",         # rolling shots on target per match
    "Corners_5",     # rolling corners per match
    "Goals_5",       # rolling goals scored per match
    "Conceded_5",    # rolling goals conceded per match
    "Points_5",      # rolling points per match (∈ [0, 3])
    "YellowCards_5", # rolling yellow cards
    "Saves_5",       # rolling goalkeeper saves
]

# When the home team is U Cluj, the opponent's rolling stats are in the
# ``Away_*`` columns; when U Cluj is the away team, the opponent's stats
# are in the ``Home_*`` columns. The opponent's Elo is always the
# Elo column on the opposite side of U Cluj.


@dataclass
class OpponentProfile:
    """One match's worth of opponent-side rolling-5 features and Elo."""

    match_id: str
    match_date: str
    opponent_name: str
    is_home_fixture: bool
    style: Dict[str, float]
    opponent_elo: float
    elo_diff: float            # home_elo - away_elo, from U Cluj's perspective
    hfa: float                 # home-field advantage at the time of the match

    def to_feature_dict(self, prefix: str = "opp_") -> Dict[str, float]:
        """Flatten into a ``{prefix + key: float}`` dict for ML input."""
        out: Dict[str, float] = {}
        for k, v in self.style.items():
            out[f"{prefix}{k}"] = float(v) if pd.notna(v) else 0.0
        out[f"{prefix}elo"] = float(self.opponent_elo) if pd.notna(self.opponent_elo) else 1200.0
        out[f"{prefix}elo_diff"] = float(self.elo_diff) if pd.notna(self.elo_diff) else 0.0
        out[f"{prefix}hfa"] = float(self.hfa) if pd.notna(self.hfa) else 50.0
        out[f"{prefix}is_home_fixture"] = 1.0 if self.is_home_fixture else 0.0
        return out


def load_all_data(csv_path: str) -> pd.DataFrame:
    """Load and lightly normalise the team-level fixture dataset."""
    df = pd.read_csv(csv_path)
    if "match_date" in df.columns:
        df["match_date"] = pd.to_datetime(df["match_date"], errors="coerce")
    return df


def extract_team_fixtures(
    all_data: pd.DataFrame,
    team_name_substring: str,
) -> pd.DataFrame:
    """Return the subset of ``all_data`` involving the given team.

    The ``team_name_substring`` is matched case-insensitively against the
    ``home_team`` and ``away_team`` columns; both home and away fixtures
    are returned, in chronological order.
    """
    needle = team_name_substring.lower()
    mask = (
        all_data["home_team"].astype(str).str.lower().str.contains(needle)
        | all_data["away_team"].astype(str).str.lower().str.contains(needle)
    )
    df = all_data.loc[mask].copy()
    if "match_date" in df.columns:
        df = df.sort_values("match_date").reset_index(drop=True)
    return df


def opponent_profile_for_row(
    row: pd.Series,
    team_name_substring: str,
) -> OpponentProfile:
    """Build an :class:`OpponentProfile` from one row of the fixtures table.

    The function detects whether the team-of-interest played at home or
    away in this row, then pulls the opponent-side rolling-5 columns.
    """
    needle = team_name_substring.lower()
    home_team = str(row.get("home_team", ""))
    away_team = str(row.get("away_team", ""))
    is_home = needle in home_team.lower()

    style: Dict[str, float] = {}
    side = "Away" if is_home else "Home"
    for key in OPPONENT_STYLE_COLUMNS_RAW:
        col = f"{side}_{key}"
        style[key.lower()] = float(row.get(col, np.nan))

    opp_elo_col = "Computed_Away_Elo" if is_home else "Computed_Home_Elo"
    opp_elo = float(row.get(opp_elo_col, 1200.0) or 1200.0)
    elo_diff = float(row.get("Computed_Elo_Diff", 0.0) or 0.0)
    if not is_home:
        elo_diff = -elo_diff  # flip so it's always from U Cluj's perspective

    return OpponentProfile(
        match_id=str(row.get("match_id", "")),
        match_date=str(row.get("match_date", "")),
        opponent_name=away_team if is_home else home_team,
        is_home_fixture=is_home,
        style=style,
        opponent_elo=opp_elo,
        elo_diff=elo_diff,
        hfa=float(row.get("Computed_HFA", 50.0) or 50.0),
    )


def cluster_opponent_styles(
    profiles: List[OpponentProfile],
    k: int = 4,
    random_state: int = 42,
) -> Dict[str, int]:
    """Cluster opponent style vectors with $k$-means into $k$ archetypes.

    Returns a dict mapping ``match_id`` to its assigned cluster label
    (an integer in :math:`\\{0, 1, \\dots, k-1\\}`). Style vectors with
    missing values are imputed to the column mean before clustering.

    The clustering is descriptive rather than predictive: it provides a
    compact one-hot encoding (``opp_cluster_0`` … ``opp_cluster_{k-1}``)
    that the supervised lineup classifier can consume in addition to the
    raw rolling-5 columns.
    """
    try:
        from sklearn.cluster import KMeans
        from sklearn.impute import SimpleImputer
    except Exception:
        # Without scikit-learn the cluster column is just zero for everyone.
        return {p.match_id: 0 for p in profiles}

    cols = list(OPPONENT_STYLE_COLUMNS_RAW)
    X = np.array([
        [p.style.get(c.lower(), np.nan) for c in cols]
        for p in profiles
    ], dtype=float)
    if X.size == 0:
        return {}
    imputer = SimpleImputer(strategy="mean")
    X = imputer.fit_transform(X)
    k_eff = min(k, max(2, len(profiles) // 2))
    km = KMeans(n_clusters=k_eff, random_state=random_state, n_init=10)
    labels = km.fit_predict(X)
    return {p.match_id: int(labels[i]) for i, p in enumerate(profiles)}


def build_opponent_profile_table(
    csv_path: str,
    team_name_substring: str,
    k_clusters: int = 4,
) -> pd.DataFrame:
    """Return one row per fixture with opponent-side features + cluster.

    Columns: ``match_id``, ``match_date``, ``opponent_name``,
    ``is_home_fixture``, ``opp_poss_5``, ``opp_shots_5``, ``opp_sot_5``,
    ``opp_corners_5``, ``opp_goals_5``, ``opp_conceded_5``,
    ``opp_points_5``, ``opp_yellowcards_5``, ``opp_saves_5``, ``opp_elo``,
    ``opp_elo_diff``, ``opp_hfa``, and one-hot columns
    ``opp_cluster_0`` … ``opp_cluster_{k-1}``.

    The cluster IDs are assigned by k-means over the rolling-5 columns of
    all of the team's fixtures, so the same opponent appearing twice
    (once at each ground) is clustered separately by their *form at that
    time* rather than by their identity.
    """
    all_data = load_all_data(csv_path)
    fixtures = extract_team_fixtures(all_data, team_name_substring)
    if fixtures.empty:
        return pd.DataFrame()

    profiles: List[OpponentProfile] = [
        opponent_profile_for_row(row, team_name_substring)
        for _, row in fixtures.iterrows()
    ]
    cluster_map = cluster_opponent_styles(profiles, k=k_clusters)

    rows = []
    for prof in profiles:
        d = prof.to_feature_dict(prefix="opp_")
        d["match_id"] = prof.match_id
        d["match_date"] = prof.match_date
        d["opponent_name"] = prof.opponent_name
        d["opp_cluster"] = cluster_map.get(prof.match_id, 0)
        rows.append(d)
    out = pd.DataFrame(rows)

    # Add one-hot encoding of the cluster column.
    if "opp_cluster" in out.columns:
        for c in range(k_clusters):
            out[f"opp_cluster_{c}"] = (out["opp_cluster"] == c).astype(int)
    return out


# ── Heuristic-composite perturbations (optional plug-in) ──────────────────────
#
# When the heuristic composite is used (i.e. the supervised classifier is
# disabled), the opponent cluster can still drive small perturbations to
# the per-position composite weights. The perturbation table below is
# author-set rather than learned, in the spirit of McHale, Scarf & Folker
# (2012). It encodes football conventions:
#
# - Against a high-press / aggressive opponent: reward composed CBs (more
#   pass_accuracy + def_action_success) and de-emphasise dribbling.
# - Against a low-block opponent: reward progressive passing and shot
#   accuracy for AM/W/WF (open-space exploitation).
# - Against a counter-attacking opponent: reward DM recoveries (kill the
#   transition).
# - Against a possession-based opponent: neutral baseline.
#
# The cluster names are not learned from the data; they are author
# annotations of what each k-means centroid tends to represent. Callers
# that want to use this table should inspect the centroids and re-label
# the clusters accordingly.

OPPONENT_CLUSTER_PERTURBATIONS: Dict[int, Dict[str, Dict[str, float]]] = {
    # Cluster 0 — "high-press attackers" (high shots + high possession + few cards)
    0: {
        "CB": {"pass_accuracy": +0.05, "def_action_success": +0.03, "dribble_success": -0.02},
        "DM": {"pass_accuracy": +0.03, "def_action_success": +0.03},
        "FB": {"pass_accuracy": +0.03, "duel_win_rate": -0.02},
    },
    # Cluster 1 — "low-block defenders" (low possession + low shots + low concession)
    1: {
        "AM": {"shot_accuracy": +0.04, "dribble_success": +0.03},
        "W":  {"dribble_success": +0.04, "successfulCrosses": +0.02},
        "WF": {"shot_accuracy": +0.03, "dribble_success": +0.03},
        "ST": {"shot_accuracy": +0.04, "dribble_success": +0.02},
    },
    # Cluster 2 — "counter-attackers" (low possession + many shots + few goals scored)
    2: {
        "DM": {"def_action_success": +0.05, "duel_win_rate": +0.03},
        "CB": {"def_action_success": +0.03, "duel_win_rate": +0.03},
        "FB": {"def_action_success": +0.03},
    },
    # Cluster 3 — "balanced / possession-based" — no perturbation (baseline).
    3: {},
}
