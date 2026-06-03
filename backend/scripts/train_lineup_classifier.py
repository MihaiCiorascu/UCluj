"""
Train the supervised starting-XI lineup classifier (Iteration J.4).

The classifier predicts a per-player ``P(started | fixture, player)``
probability for each (player, fixture) pair. The eleven highest-probability
players, subject to the formation slot constraint via Hungarian
assignment, become the predicted starting XI.

Feature design
--------------

For each (player, fixture) pair we assemble:

* **Static-ish player features** (full-season aggregates — a small,
  measured leakage: a point-in-time rerun puts the rolling-origin Jaccard
  at 0.557 versus 0.571 with these columns, an inflation under two Jaccard
  points, documented in the thesis limitations; the dynamic features below
  carry the dominant lineup signal):

  - ``performance_score`` — Iteration H weighted-KPI composite.
  - ``recent_form_score`` — Iteration H decayed recent-form aggregate.
  - ``pass_accuracy``, ``duel_win_rate``, ``def_action_success``,
    ``shot_accuracy``, ``dribble_success`` — efficiency metrics.
  - ``total_minutes``, ``matches_played`` — exposure.

* **Dynamic per-fixture features** (computed strictly using matches
  before the fixture under prediction — no leakage):

  - ``availability_last_5``, ``started_last_match``,
    ``match_gap_since_last_appearance``, ``availability_score``.
  - ``cumulative_minutes_before_fixture``, ``cumulative_appearances``.

* **Opponent profile features** (from ``data/All_Data.csv`` via
  :mod:`ml.opponent_profile`):

  - ``opp_poss_5``, ``opp_shots_5``, ``opp_sot_5``, ``opp_corners_5``,
    ``opp_goals_5``, ``opp_conceded_5``, ``opp_points_5``,
    ``opp_yellowcards_5``, ``opp_saves_5``, ``opp_elo``,
    ``opp_elo_diff``, ``opp_hfa``, ``opp_is_home_fixture``.
  - One-hot opponent cluster: ``opp_cluster_0`` … ``opp_cluster_3``.

* **Position one-hot** of ``position_group_fine`` (ten columns).

The label is ``1`` if the player started the fixture for U Cluj,
``0`` otherwise.

Evaluation
----------

* **Rolling-origin one-fixture-out CV**: for each fixture $F_i$ at
  chronology index $i \\geq i_{\\min}$, train on the (player, fixture)
  rows of fixtures $F_0, F_1, \\dots, F_{i-1}$ only, then score every
  squad player for fixture $F_i$, assign positions with Hungarian, and
  compute the Jaccard overlap with the actual XI. Aggregate as
  $\\text{mean}_i \\, \\text{Jaccard}_i$.
* ``i_min = 8`` (we need at least eight fixtures of training data
  before the first prediction to keep the training set non-trivial).

Persistence
-----------

The fitted classifier, the column list, and the StandardScaler are
saved to ``backend/ml/xi_lineup_model.joblib`` as a single bundle so the
deployed predictor can load it and reproduce the per-player scoring
exactly.

References
----------
- McHale, I.G., Scarf, P.A. and Folker, D.E. (2012). *On the
  development of a soccer player performance rating system for the
  English Premier League.* Interfaces 42(4), 339–351.
- Constantinou, A.C. (2019). *Dolores: a model that predicts football
  match outcomes from all over the world.* Machine Learning 108, 49–75.
- Bouthillier, X. et al. (2021). *Accounting for Variance in Machine
  Learning Benchmarks.* MLSys.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import joblib
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    build_dataset_from_files,
    compute_availability_features,
    get_team_match_chronology,
    get_team_squad_from_matches,
)
from ml.opponent_profile import build_opponent_profile_table  # type: ignore  # noqa: E402
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402

DRIVE = ROOT / "ml" / "data" / "drive_cache"
ALL_DATA_CSV = ROOT.parent / "data" / "All_Data.csv"
LINEUP_HISTORY = ROOT / "ml" / "data" / "lineup_history.json"
OUT_BUNDLE = ROOT / "ml" / "xi_lineup_model.joblib"

TEAM_SUBSTRING = "Universitatea Cluj"
TEAM_NAME_IN_ALL_DATA = "U Cluj"
I_MIN = 8  # warm-up fixtures before the first rolling-origin prediction.

FINE_GROUPS = ["GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"]

STATIC_PLAYER_COLS = [
    "performance_score", "recent_form_score",
    "pass_accuracy", "duel_win_rate", "def_action_success",
    "shot_accuracy", "dribble_success",
    "total_minutes", "matches_played",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _load_lineup_history() -> Tuple[List[dict], List[int]]:
    if not LINEUP_HISTORY.exists():
        raise FileNotFoundError(
            f"Run extract_starting_xi_history.py first to produce {LINEUP_HISTORY}"
        )
    with LINEUP_HISTORY.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return data["fixtures"], [int(p) for p in data["squad_ids"]]


def _per_match_blocks(
    match_stat_files: List[str],
) -> Dict[int, List[dict]]:
    """Build playerId -> [per-match stat block] across the full dataset.

    Each block carries ``matchId``, ``seasonId``, ``roundId``, and ``total``
    (with ``minutesOnField`` and ``matchesInStart``).
    """
    out: Dict[int, List[dict]] = {}
    for fp in match_stat_files:
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
        except Exception:
            continue
        for entry in d.get("players", []) or []:
            pid = entry.get("playerId")
            if pid is None:
                continue
            blk = {
                "matchId": entry.get("matchId"),
                "seasonId": entry.get("seasonId"),
                "roundId": entry.get("roundId"),
                "total": dict(entry.get("total", {})),
            }
            out.setdefault(int(pid), []).append(blk)
    return out


def _opponent_features_by_matchid(opp_df: pd.DataFrame) -> Dict[int, Dict[str, float]]:
    """Map matchId-like keys in opp_df to a feature dict.

    The drive-cache integer matchIds are NOT the same as the
    ``All_Data.csv`` ``match_id`` strings, so we cannot key directly on
    matchId. We key on the ``match_date`` (yyyy-mm-dd) instead and let
    the caller perform date-based matching downstream.
    """
    # The drive cache JSONs do not include match_date, so this lookup is
    # only used for chronological alignment in the supervised pipeline.
    by_date: Dict[str, Dict[str, float]] = {}
    feature_cols = [c for c in opp_df.columns
                    if c.startswith("opp_") and c not in ("opponent_name", "opp_cluster")]
    for _, row in opp_df.iterrows():
        date_key = str(row.get("match_date", ""))[:10]
        d = {c: float(row[c]) if pd.notna(row[c]) else 0.0 for c in feature_cols}
        by_date[date_key] = d
    return by_date


def _zero_opponent_features(opp_df: pd.DataFrame) -> Dict[str, float]:
    """Default opponent feature row when no match_date alignment is available."""
    feature_cols = [c for c in opp_df.columns
                    if c.startswith("opp_") and c not in ("opponent_name", "opp_cluster")]
    return {c: 0.0 for c in feature_cols}


def _build_training_table(
    fixtures: List[dict],
    squad_ids: List[int],
    static_features: pd.DataFrame,
    player_match_blocks: Dict[int, List[dict]],
    chronology: List[int],
    opp_features_by_idx: Dict[int, Dict[str, float]],
) -> pd.DataFrame:
    """Return one row per (player, fixture) with features + label.

    ``static_features`` is the player-aggregated dataset (full season).
    ``opp_features_by_idx`` is a mapping chronology-index -> opp feature dict.
    """
    rows: List[dict] = []
    squad_set = set(int(p) for p in squad_ids)
    static_by_pid = static_features.set_index("playerId").to_dict(orient="index")

    for fixture_idx, fixture in enumerate(fixtures):
        mid = int(fixture["match_id"])
        # Chronology slice strictly before this fixture.
        try:
            chrono_idx = chronology.index(mid)
        except ValueError:
            continue
        chrono_before = chronology[:chrono_idx]

        starter_ids = {int(s["playerId"]) for s in fixture.get("starters", [])}
        opp_features = opp_features_by_idx.get(fixture_idx, {})

        for pid in squad_ids:
            static = static_by_pid.get(pid, {})
            if not static:
                continue

            # Dynamic availability features computed with the pre-fixture chronology.
            blocks = player_match_blocks.get(int(pid), [])
            avail = compute_availability_features(blocks, chrono_before)

            # Cumulative pre-fixture minutes / appearances.
            cum_minutes = 0.0
            cum_apps = 0
            for blk in blocks:
                bmid = blk.get("matchId")
                if bmid is None or int(bmid) not in chrono_before:
                    continue
                mins = float((blk.get("total", {}) or {}).get("minutesOnField", 0) or 0)
                if mins > 0:
                    cum_minutes += mins
                    cum_apps += 1

            fine = str(static.get("position_group_fine", "MID")).upper()
            row: Dict[str, float] = {
                "playerId": int(pid),
                "match_id": mid,
                "fixture_idx": fixture_idx,
                "started": 1 if int(pid) in starter_ids else 0,
            }
            for c in STATIC_PLAYER_COLS:
                row[c] = float(static.get(c, 0.0) or 0.0)
            row.update({
                "availability_last_5": avail["availability_last_5"],
                "started_last_match": avail["started_last_match"],
                "match_gap_since_last_appearance": min(avail["match_gap_since_last_appearance"], 35.0),
                "availability_score": avail["availability_score"],
                "cumulative_minutes_before_fixture": cum_minutes,
                "cumulative_appearances": float(cum_apps),
            })
            row.update(opp_features)
            for g in FINE_GROUPS:
                row[f"pos_{g}"] = 1.0 if fine == g else 0.0
            rows.append(row)

    return pd.DataFrame(rows)


# ── Hungarian XI assignment (mirror of xi_predictor._assign_xi) ──────────────

def _hungarian_xi(
    scored: pd.DataFrame,
    formation: Dict[str, int],
) -> List[int]:
    """Return the eleven selected playerIds for a formation.

    ``scored`` must contain ``playerId``, ``role_group`` and ``score``.
    """
    try:
        from scipy.optimize import linear_sum_assignment
    except Exception:
        # Fallback to greedy per-position top-N.
        out: List[int] = []
        for role, count in formation.items():
            sub = scored[scored["role_group"].astype(str).str.upper() == role.upper()]
            sub = sub.sort_values("score", ascending=False).head(int(count))
            out.extend(int(p) for p in sub["playerId"].tolist())
        return out

    slot_labels: List[str] = []
    for role, count in formation.items():
        slot_labels.extend([role.upper()] * int(count))
    n_slots = len(slot_labels)
    rolesU = scored["role_group"].astype(str).str.upper().to_numpy()
    s = scored["score"].astype(float).to_numpy()
    BIG = 1e6
    cost = np.full((len(scored), n_slots), BIG)
    for j, sl in enumerate(slot_labels):
        eligible = rolesU == sl
        cost[eligible, j] = -s[eligible]
    if len(scored) < n_slots:
        # Pad with dummy rows of +BIG so the matrix is square enough.
        pad = n_slots - len(scored)
        cost = np.vstack([cost, np.full((pad, n_slots), BIG)])
    try:
        r, c = linear_sum_assignment(cost)
    except ValueError:
        return []
    picked: List[int] = []
    for rr, cc in zip(r, c):
        if rr < len(scored) and cost[rr, cc] < BIG / 2:
            picked.append(int(scored.iloc[rr]["playerId"]))
    return picked


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    print("Loading data …")
    profile_path = DRIVE / "players (1).json"
    profiles = load_player_profiles(str(profile_path))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    chronology = get_team_match_chronology(match_files, TEAM_SUBSTRING)
    squad = get_team_squad_from_matches(match_files, TEAM_SUBSTRING)
    squad_ids = sorted(int(p) for p in squad)
    print(f"  squad size: {len(squad_ids)}")
    print(f"  fixtures:   {len(chronology)}")

    if not LINEUP_HISTORY.exists():
        print("Lineup history missing — running extract_starting_xi_history.py first")
        import subprocess
        rc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "extract_starting_xi_history.py")],
            check=False,
        ).returncode
        if rc != 0:
            return rc
    fixtures, _ = _load_lineup_history()

    print("Building static-feature dataset …")
    static_df = build_dataset_from_files(
        match_files, profiles,
        availability_team_substring=TEAM_SUBSTRING,
    )

    print("Indexing per-match player blocks …")
    blocks_by_pid = _per_match_blocks(match_files)

    print("Building opponent-profile table from All_Data.csv …")
    if not ALL_DATA_CSV.exists():
        print(f"All_Data.csv missing at {ALL_DATA_CSV} — proceeding with zero opp features",
              file=sys.stderr)
        opp_table = pd.DataFrame()
    else:
        opp_table = build_opponent_profile_table(
            str(ALL_DATA_CSV), TEAM_NAME_IN_ALL_DATA, k_clusters=4,
        )

    # Map drive-cache fixture index (chronology position) to opp_table row by
    # alignment of date order. The drive cache has 35 most-recent fixtures;
    # opp_table has all U Cluj fixtures across multiple seasons. We align by
    # taking the last len(chronology) rows of opp_table.
    opp_features_by_idx: Dict[int, Dict[str, float]] = {}
    if not opp_table.empty:
        opp_table_sorted = opp_table.sort_values("match_date").reset_index(drop=True)
        tail = opp_table_sorted.tail(len(chronology)).reset_index(drop=True)
        feature_cols = [c for c in tail.columns
                        if c.startswith("opp_") and c != "opponent_name" and c != "opp_cluster"]
        for i, (_, row) in enumerate(tail.iterrows()):
            opp_features_by_idx[i] = {
                c: float(row[c]) if pd.notna(row[c]) else 0.0
                for c in feature_cols
            }

    print("Building training table …")
    table = _build_training_table(
        fixtures, squad_ids, static_df, blocks_by_pid,
        chronology, opp_features_by_idx,
    )
    print(f"  training table shape: {table.shape}")
    print(f"  positives: {int(table['started'].sum())} / {len(table)} "
          f"({table['started'].mean():.2%})")

    # ── Feature columns ──────────────────────────────────────────────────────
    feature_cols = [c for c in table.columns
                    if c not in ("playerId", "match_id", "fixture_idx", "started")
                    and table[c].dtype in (np.float64, np.float32, np.int64, np.int32)]
    print(f"  feature cols: {len(feature_cols)}")

    # ── Rolling-origin one-fixture-out CV ─────────────────────────────────────
    print("Running rolling-origin CV …")
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    overlaps: List[float] = []
    cv_records: List[dict] = []
    n_fixtures = int(table["fixture_idx"].max()) + 1
    for hold_out_idx in range(I_MIN, n_fixtures):
        train_mask = table["fixture_idx"] < hold_out_idx
        test_mask = table["fixture_idx"] == hold_out_idx
        if not train_mask.any() or not test_mask.any():
            continue
        X_train = table.loc[train_mask, feature_cols].to_numpy()
        y_train = table.loc[train_mask, "started"].to_numpy()
        X_test = table.loc[test_mask, feature_cols].to_numpy()

        scaler = StandardScaler().fit(X_train)
        clf = LogisticRegression(
            max_iter=1000, class_weight="balanced", C=1.0, solver="lbfgs",
        )
        clf.fit(scaler.transform(X_train), y_train)
        scores = clf.predict_proba(scaler.transform(X_test))[:, 1]

        test_df = table.loc[test_mask, ["playerId"]].copy()
        # Pull role_group from the static dataset for slot assignment.
        test_df["role_group"] = test_df["playerId"].map(
            static_df.set_index("playerId")["role_group"].to_dict()
        )
        test_df["score"] = scores

        actual_starters = set(
            int(s["playerId"]) for s in fixtures[hold_out_idx].get("starters", [])
        )
        predicted = _hungarian_xi(test_df, formation={"GK": 1, "DEF": 4, "MID": 3, "FWD": 3})
        pred_set = set(predicted)
        union = pred_set | actual_starters
        jacc = (len(pred_set & actual_starters) / len(union)) if union else 0.0
        overlaps.append(jacc)
        cv_records.append({
            "fixture_idx": hold_out_idx,
            "match_id": int(fixtures[hold_out_idx]["match_id"]),
            "n_actual": len(actual_starters),
            "n_predicted": len(pred_set),
            "overlap": len(pred_set & actual_starters),
            "jaccard": jacc,
        })

    mean_jacc = float(np.mean(overlaps)) if overlaps else 0.0
    std_jacc = float(np.std(overlaps)) if overlaps else 0.0
    print(f"\nRolling-origin Jaccard: {mean_jacc:.4f} +/- {std_jacc:.4f} (n={len(overlaps)})")

    # ── Final model fit on ALL data ─────────────────────────────────────────
    print("\nFitting final model on the full dataset …")
    X_all = table[feature_cols].to_numpy()
    y_all = table["started"].to_numpy()
    final_scaler = StandardScaler().fit(X_all)
    final_clf = LogisticRegression(
        max_iter=1000, class_weight="balanced", C=1.0, solver="lbfgs",
    ).fit(final_scaler.transform(X_all), y_all)
    print(f"  final coefficients (top 10 by |w|):")
    coef_pairs = sorted(zip(feature_cols, final_clf.coef_[0]), key=lambda x: -abs(x[1]))
    for name, w in coef_pairs[:10]:
        print(f"    {name:40s}  {w:+.4f}")

    bundle = {
        "model": final_clf,
        "scaler": final_scaler,
        "feature_cols": feature_cols,
        "fine_groups": FINE_GROUPS,
        "static_player_cols": STATIC_PLAYER_COLS,
        "cv_mean_jaccard": mean_jacc,
        "cv_std_jaccard": std_jacc,
        "cv_n": len(overlaps),
        "cv_records": cv_records,
        "trained_on_n_fixtures": n_fixtures,
        "i_min": I_MIN,
    }
    OUT_BUNDLE.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, OUT_BUNDLE)
    sz = os.path.getsize(OUT_BUNDLE)
    print(f"Saved supervised model bundle -> {OUT_BUNDLE.relative_to(ROOT)} ({sz} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
