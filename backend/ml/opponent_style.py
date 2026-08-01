"""Opponent style archetypes for opponent-aware XI selection.

The lineup model ranks candidates within a fixture, so a raw opponent stat
(constant across candidates) cannot shift the pick; opponent context matters
only when crossed with a player attribute. This module supplies the opponent
half: the style archetype the opponent club belongs to.

Each Superliga club is summarised by its latest rolling-5 profile and Elo from
``data/All_Data.csv`` and clustered into ``k`` archetypes by k-means (fixed seed,
so train and serve agree). The 2025-26 lineup fixtures are not in All_Data, so
the profile is the club's latest five-match form, not a point-in-time value. The
archetype is crossed with each candidate's fine position group (``oppcl{c}_pos{g}``)
at train and serve, following Lago-Peñas [LPML+10] and Bornn et al. [BCF18].
"""

from __future__ import annotations

import csv
from typing import Dict, List, Optional

# Rolling-5 style dimensions (mirrors the thesis opponent profile), plus Elo as
# the quality axis. Order is fixed so the saved imputer/scaler/k-means align.
STYLE_DIMS: List[str] = [
    "Poss_5", "Shots_5", "SoT_5", "Corners_5", "Goals_5",
    "Conceded_5", "Points_5", "YellowCards_5", "Saves_5",
]
STYLE_FEATURES: List[str] = STYLE_DIMS + ["elo"]
DEFAULT_K = 4
DEFAULT_SEED = 42


def _to_float(v) -> Optional[float]:
    try:
        if v is None or v == "":
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def team_style_vectors(all_data_csv: str) -> Dict[str, List[Optional[float]]]:
    """Return ``{registry_short: [rolling-5..., elo]}`` using each club's most
    recent All_Data fixture (the side that club played). Rows are read in file
    order and overwritten, and All_Data is chronological, so the last write per
    club is its latest profile.
    """
    from sportradar.team_registry import team_by_alias  # local: avoid import cycle

    latest: Dict[str, List[Optional[float]]] = {}
    with open(all_data_csv, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            for side, team in (("Home", row.get("home_team")),
                               ("Away", row.get("away_team"))):
                ref = team_by_alias(str(team or ""))
                if ref is None:
                    continue
                vec = [_to_float(row.get(f"{side}_{d}")) for d in STYLE_DIMS]
                vec.append(_to_float(row.get(f"Computed_{side}_Elo")))
                latest[ref.short] = vec
    return latest


def fit_team_clusters(
    vectors: Dict[str, List[Optional[float]]],
    k: int = DEFAULT_K,
    seed: int = DEFAULT_SEED,
) -> dict:
    """Fit k-means over the club style vectors. Returns a self-contained bundle
    (imputer, scaler, k-means, the resolved ``team_cluster`` map, and metadata)
    that :func:`cluster_for_team` and inference can reuse deterministically.
    """
    import numpy as np
    from sklearn.cluster import KMeans
    from sklearn.impute import SimpleImputer
    from sklearn.preprocessing import StandardScaler

    teams = sorted(vectors)
    X = np.array([[ (v if v is not None else np.nan) for v in vectors[t]]
                  for t in teams], dtype=float)
    imputer = SimpleImputer(strategy="mean")
    Xi = imputer.fit_transform(X)
    scaler = StandardScaler()
    Xs = scaler.fit_transform(Xi)
    k_eff = min(k, max(2, len(teams)))
    km = KMeans(n_clusters=k_eff, random_state=seed, n_init=10)
    labels = km.fit_predict(Xs)
    return {
        "features": STYLE_FEATURES,
        "k": k_eff,
        "imputer": imputer,
        "scaler": scaler,
        "kmeans": km,
        "team_cluster": {t: int(labels[i]) for i, t in enumerate(teams)},
        "seed": seed,
    }


def cluster_for_team(bundle: dict, team_short: Optional[str]) -> Optional[int]:
    """Archetype id for a club (by registry short), or None if unknown."""
    if not team_short or not bundle:
        return None
    return bundle.get("team_cluster", {}).get(team_short)


# Player STYLE attributes crossed with the opponent archetype. Unlike a position
# one-hot (constant within a position group), these vary per player, so the model
# can re-rank candidates within a position by opponent, changing the picked XI.
INTERACTION_ATTRS: List[str] = [
    "pass_accuracy", "duel_win_rate", "def_action_success",
    "shot_accuracy", "dribble_success",
]


def interaction_columns(k: int, attrs: Optional[List[str]] = None) -> List[str]:
    """Stable ordered list of the ``oppcl{c}_x_{attr}`` interaction columns."""
    attrs = attrs or INTERACTION_ATTRS
    return [f"oppcl{c}_x_{a}" for c in range(k) for a in attrs]


def interaction_row(
    opp_cluster: Optional[int],
    attr_values: Dict[str, float],
    k: int,
    attrs: Optional[List[str]] = None,
) -> Dict[str, float]:
    """Opponent-archetype x player-attribute features for one player: the player's
    style attributes, gated to the opponent's archetype block (the other blocks
    stay zero). All zero when the archetype is unknown -> graceful no-op.
    """
    attrs = attrs or INTERACTION_ATTRS
    out = {col: 0.0 for col in interaction_columns(k, attrs)}
    if opp_cluster is None:
        return out
    for a in attrs:
        out[f"oppcl{opp_cluster}_x_{a}"] = float(attr_values.get(a) or 0.0)
    return out
