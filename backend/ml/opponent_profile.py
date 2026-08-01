"""
Opponent style-profile features for the Starting-XI predictor.

The opponent profile for a fixture is the opponent's rolling-5 vector from
``data/All_Data.csv`` (possession, shots, SoT, corners, goals scored/conceded,
points, yellow cards, goalkeeper saves), taken from the opponent's side of the
fixture (:func:`Home_*_5` / :func:`Away_*_5`).

References: Lago-Peñas (2009), Journal of Sports Sciences 27(13), 1463-1467;
Bornn, Cervone & Fernández (2018), Significance 15(3), 26-29.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np
import pandas as pd


# Style profile columns
# Rolling-5 features in ``All_Data.csv``, taken from the opponent's side of the
# fixture (home or away, per the team-substring match against the team columns).

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

    Returns ``{match_id: cluster label}`` in :math:`\\{0, \\dots, k-1\\}`;
    missing values are mean-imputed first. Descriptive, not predictive: it
    yields a one-hot encoding (``opp_cluster_0`` .. ``opp_cluster_{k-1}``) the
    lineup classifier can use alongside the raw rolling-5 columns.
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
    ``is_home_fixture``, the ``opp_*`` rolling-5 features, ``opp_elo``,
    ``opp_elo_diff``, ``opp_hfa``, and one-hot columns
    ``opp_cluster_0`` .. ``opp_cluster_{k-1}``. Cluster IDs come from k-means
    over the rolling-5 columns, so the same opponent at each ground is
    clustered by its form at that time, not its identity.
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


# Heuristic-composite perturbations (optional plug-in)
# When the heuristic composite is used instead of the supervised classifier, the
# opponent cluster nudges the per-position composite weights. The table is
# author-set, not learned, per McHale, Scarf & Folker (2012). Cluster names are
# author annotations of what each centroid tends to represent, not learned
# labels; callers should inspect the centroids and re-label as needed.

OPPONENT_CLUSTER_PERTURBATIONS: Dict[int, Dict[str, Dict[str, float]]] = {
    # Cluster 0: "high-press attackers" (high shots + high possession + few cards)
    0: {
        "CB": {"pass_accuracy": +0.05, "def_action_success": +0.03, "dribble_success": -0.02},
        "DM": {"pass_accuracy": +0.03, "def_action_success": +0.03},
        "FB": {"pass_accuracy": +0.03, "duel_win_rate": -0.02},
    },
    # Cluster 1: "low-block defenders" (low possession + low shots + low concession)
    1: {
        "AM": {"shot_accuracy": +0.04, "dribble_success": +0.03},
        "W":  {"dribble_success": +0.04, "successfulCrosses": +0.02},
        "WF": {"shot_accuracy": +0.03, "dribble_success": +0.03},
        "ST": {"shot_accuracy": +0.04, "dribble_success": +0.02},
    },
    # Cluster 2: "counter-attackers" (low possession + many shots + few goals scored)
    2: {
        "DM": {"def_action_success": +0.05, "duel_win_rate": +0.03},
        "CB": {"def_action_success": +0.03, "duel_win_rate": +0.03},
        "FB": {"def_action_success": +0.03},
    },
    # Cluster 3: "balanced / possession-based", no perturbation (baseline).
    3: {},
}
