"""
[M-10] availability_last_5 ablation + Heuristic Composite fresh measurement.

Three arms, single-pass rolling-origin CV on the same 428 cells the Iter-S
comparison used (commit 4c79005):

  Arm A — LR-full:           the deployed model; all 51 features
  Arm B — LR-no-availability: same model class + hyperparameters; AVAILABILITY
                              features dropped (availability_last_5, started_last_match,
                              match_gap_since_last_appearance, cumulative_minutes_before_fixture,
                              cumulative_appearances)
  Arm C — Heuristic Composite: re-implements the per-position weighted-KPI scorer
                               from backend/ml/xi_predictor.py using FINE_POSITION_WEIGHTS;
                               replaces the stale 0.425 historical reference

Closes:
  - M-10 (originally "availability_last_5 ablation"; now expanded to also
    address Iter-S limitation #1 by measuring the heuristic on the L-iteration
    dataset)
  - Iter-S limitation #1 (Heuristic Composite was not measured in Iter-S)
  - Iter-S limitation #4 (availability_last_5 not ablated)

Cite for the leakage framing: Kaufman, Rosset, Perlich & Stitelman (2012),
"Leakage in Data Mining: Formulation, Detection, and Avoidance", ACM TKDD 6(4):15.

Run:
    cd backend
    python -X utf8 scripts/ablate_xi.py

Output:
    Stdout: per-arm aggregate Jaccard@11 + NDCG@11 + decision interpretation
    JSON: backend/scripts/_m10_results.json (gitignored)

Estimated runtime: ~30-60 minutes (3 arms × 428 cells; LR is fast,
Heuristic Composite has no fit cost).
"""
from __future__ import annotations

import glob
import json
import sys
import time
import warnings
from pathlib import Path
from typing import Any, Dict, List, Set

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

from train_lineup_classifier_league import (  # type: ignore  # noqa: E402
    DRIVE,
    I_MIN,
    LINEUP_HISTORY,
    _build_opp_xi_lookup,
    _build_static_df_per_team,
    _build_training_rows,
    _hungarian_xi,
    _per_match_blocks,
)
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402
from ml.xi_predictor import FINE_POSITION_WEIGHTS  # type: ignore  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402
from sklearn.metrics import ndcg_score  # noqa: E402
from sklearn.pipeline import make_pipeline  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402
from sportradar.team_registry import SUPERLIGA_TEAMS  # type: ignore  # noqa: E402

FORMATION = {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3}
OUT_PATH = Path(__file__).resolve().parent / "_m10_results.json"

# Columns that are functions of past selection (the leak surface).
# Dropped in Arm B and not used in Arm C's heuristic scorer.
AVAILABILITY_LEAK_COLS = {
    "availability_score",
    "availability_last_5",
    "started_last_match",
    "match_gap_since_last_appearance",
    "cumulative_minutes_before_fixture",
    "cumulative_appearances",
}

# Coarse → fine position mapping for the heuristic's fine-group fallback.
COARSE_FROM_FINE = {
    "GK": "GK",
    "CB": "DEF", "FB": "DEF", "WB": "DEF",
    "DM": "MID", "CM": "MID", "AM": "MID",
    "W": "FWD", "WF": "FWD", "ST": "FWD",
}


# ── Metrics ─────────────────────────────────────────────────────────────────


def _jaccard_at_11(pred_set: set, actual: set) -> float:
    union = pred_set | actual
    return (len(pred_set & actual) / len(union)) if union else 0.0


def _ndcg_at_11(y_true: np.ndarray, y_score: np.ndarray) -> float:
    if len(y_true) < 2 or y_true.sum() == 0:
        return float("nan")
    try:
        return float(ndcg_score(y_true.reshape(1, -1), y_score.reshape(1, -1), k=11))
    except Exception:
        return float("nan")


def _score_to_xi_set(scores: np.ndarray, role_groups: pd.Series, player_ids: pd.Series) -> set:
    test_df = pd.DataFrame({
        "playerId": player_ids.values,
        "role_group": role_groups.values,
        "score": scores,
    })
    return set(_hungarian_xi(test_df, formation=FORMATION))


# ── Arm C: Heuristic Composite scorer ──────────────────────────────────────


def _heuristic_score(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
    fine_position: pd.Series,
    feature_cols: List[str],
) -> np.ndarray:
    """Re-implement the xi_predictor.py heuristic composite scorer.

    Per-player score = sum over kpi of weight[fine_position, kpi] * z_score(kpi, fine_position)
    where z_score is computed on the train fold's KPI distribution within
    each fine position group. KPIs the position weight dict references that
    aren't in feature_cols are silently skipped (e.g., availability_score
    if the training table doesn't carry it directly).

    Used as Arm C — fresh measurement of the deployed heuristic on the
    L-iteration data, replacing the stale 0.425 historical comment.
    """
    n_test = len(test_df)
    scores = np.zeros(n_test, dtype=float)

    # Pre-compute z-score stats per fine position group on the TRAIN fold.
    # If a test player's fine_position is unknown or absent from train, we
    # fall back to the global mean/std for that KPI.
    train_pos_stats: Dict[str, Dict[str, Dict[str, float]]] = {}
    if "fine_position" in train_df.columns:
        for pos, sub in train_df.groupby("fine_position"):
            train_pos_stats[str(pos)] = {
                c: {"mean": float(sub[c].mean()), "std": float(sub[c].std() or 1.0)}
                for c in feature_cols
                if c in sub.columns
            }
    # Global fallback stats.
    global_stats: Dict[str, Dict[str, float]] = {
        c: {"mean": float(train_df[c].mean() if c in train_df.columns else 0.0),
            "std": float(train_df[c].std() if c in train_df.columns else 1.0) or 1.0}
        for c in feature_cols
    }

    for i in range(n_test):
        fp = str(fine_position.iloc[i]) if i < len(fine_position) else ""
        weights = FINE_POSITION_WEIGHTS.get(fp)
        if weights is None:
            # Map to coarse if fine group not in dict.
            coarse = COARSE_FROM_FINE.get(fp)
            from ml.xi_predictor import COARSE_POSITION_WEIGHTS
            weights = COARSE_POSITION_WEIGHTS.get(coarse or "MID", {})

        s = 0.0
        for kpi, w in weights.items():
            if kpi not in feature_cols:
                continue  # KPI not in training table (e.g., availability_score)
            stats = train_pos_stats.get(fp, {}).get(kpi) or global_stats.get(kpi)
            if not stats or stats["std"] == 0:
                continue
            raw = float(test_df.iloc[i].get(kpi, 0.0) or 0.0)
            z = (raw - stats["mean"]) / stats["std"]
            s += w * z
        scores[i] = s
    return scores


# ── Per-cell evaluator ─────────────────────────────────────────────────────


def _evaluate_lr(
    name: str,
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_test: np.ndarray,
    y_test: np.ndarray,
    test_role_groups: pd.Series,
    test_player_ids: pd.Series,
    actual_starters: set,
) -> Dict[str, float]:
    """Fit + score an LR arm; return Jaccard + NDCG for this cell."""
    try:
        clf = make_pipeline(
            StandardScaler(),
            LogisticRegression(max_iter=1000, class_weight="balanced",
                                C=1.0, solver="lbfgs", random_state=42),
        )
        clf.fit(X_train, y_train)
        scores = np.asarray(clf.predict_proba(X_test)[:, 1], dtype=float)
        pred = _score_to_xi_set(scores, test_role_groups, test_player_ids)
        return {
            "jaccard": _jaccard_at_11(pred, actual_starters),
            "ndcg":    _ndcg_at_11(y_test, scores),
            "ok":      True,
        }
    except Exception as exc:
        return {"jaccard": float("nan"), "ndcg": float("nan"),
                "ok": False, "err": f"{name}: {type(exc).__name__}: {exc}"}


def _evaluate_heuristic(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
    feature_cols: List[str],
    test_role_groups: pd.Series,
    test_player_ids: pd.Series,
    y_test: np.ndarray,
    actual_starters: set,
) -> Dict[str, float]:
    """Score test candidates via the heuristic composite; return Jaccard + NDCG."""
    try:
        fine = test_df["fine_position"] if "fine_position" in test_df.columns else test_df["role_group"]
        scores = _heuristic_score(train_df, test_df, fine, feature_cols)
        pred = _score_to_xi_set(scores, test_role_groups, test_player_ids)
        return {
            "jaccard": _jaccard_at_11(pred, actual_starters),
            "ndcg":    _ndcg_at_11(y_test, scores),
            "ok":      True,
        }
    except Exception as exc:
        return {"jaccard": float("nan"), "ndcg": float("nan"),
                "ok": False, "err": f"Heuristic: {type(exc).__name__}: {exc}"}


# ── Main CV loop ────────────────────────────────────────────────────────────


def run_cv() -> dict:
    print("=" * 70)
    print("[M-10] availability_last_5 ablation + Heuristic Composite measurement")
    print("=" * 70)
    print()
    print("Loading data ...")
    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    print(f"  {len(match_files)} match files, {len(profiles)} player profiles.")

    if not LINEUP_HISTORY.exists():
        raise FileNotFoundError("Lineup history missing — run extract_starting_xi_history_league.py first.")
    with LINEUP_HISTORY.open("r", encoding="utf-8") as f:
        league_history = json.load(f)
    print(f"  league history: {league_history['n_teams']} teams.")

    print("\nBuilding per-team static DataFrames (slow) ...")
    static_by_team = _build_static_df_per_team(SUPERLIGA_TEAMS, profiles, match_files)
    print(f"  built {len(static_by_team)} static DataFrames.")

    print("\nIndexing per-match player blocks ...")
    blocks_by_pid = _per_match_blocks(match_files)
    print(f"  indexed {len(blocks_by_pid)} player histories.")

    print("\nBuilding opponent-XI lookup ...")
    opp_xi_lookup = _build_opp_xi_lookup(league_history, static_by_team)
    print(f"  populated opp_xi for {len(opp_xi_lookup)} (matchId, team) pairs.")

    print("\nAssembling training rows ...")
    table = _build_training_rows(league_history, static_by_team, blocks_by_pid, opp_xi_lookup)
    print(f"  training table shape: {table.shape}")

    # Identify feature columns.
    skip_cols = {"playerId", "team_short", "match_id", "fixture_idx",
                 "season_id", "round_id", "started"}
    full_feature_cols = [c for c in table.columns
                         if c not in skip_cols
                         and table[c].dtype in (np.float64, np.float32, np.int64, np.int32)]
    print(f"  full feature cols: {len(full_feature_cols)}")

    # Identify which "availability/recency" columns are actually present in the table.
    leak_cols_present = [c for c in full_feature_cols if c in AVAILABILITY_LEAK_COLS]
    no_avail_feature_cols = [c for c in full_feature_cols if c not in AVAILABILITY_LEAK_COLS]
    print(f"  availability-leak cols dropped from Arm B: {leak_cols_present}")
    print(f"  Arm B feature cols: {len(no_avail_feature_cols)}")

    # Add a fine_position column if not already present (for the heuristic scorer).
    if "fine_position" not in table.columns:
        # Map from role_group or other position info. Look in static_by_team for fine_position
        # info via the playerId mapping.
        fp_lookup: Dict[int, str] = {}
        for wy_substr, sdf in static_by_team.items():
            if "fine_position" in sdf.columns:
                for _, row in sdf[["playerId", "fine_position"]].iterrows():
                    pid = int(row["playerId"])
                    fp_lookup[pid] = str(row["fine_position"])
            elif "role_group" in sdf.columns:
                for _, row in sdf[["playerId", "role_group"]].iterrows():
                    pid = int(row["playerId"])
                    fp_lookup[pid] = str(row["role_group"])
        table["fine_position"] = table["playerId"].map(lambda p: fp_lookup.get(int(p), "MID"))
        print(f"  added fine_position column (lookup populated from static_by_team)")

    table_sorted = table.sort_values(["match_id"]).reset_index(drop=True)

    per_arm_records: Dict[str, List[dict]] = {arm: [] for arm in ("LR_full", "LR_no_avail", "Heuristic")}

    print("\n--- Running rolling-origin CV across 3 arms ---")
    cell_count = 0
    started = time.time()
    for team in SUPERLIGA_TEAMS:
        team_blob = next(
            (tb for tb in league_history["teams"] if tb["team_short"] == team.short),
            None,
        )
        if team_blob is None:
            continue
        for hold_out_idx, fixture in enumerate(team_blob["fixtures"]):
            if hold_out_idx < I_MIN:
                continue
            mid = int(fixture["match_id"])

            train_mask = table_sorted["match_id"] < mid
            test_mask = (
                (table_sorted["team_short"] == team.short)
                & (table_sorted["match_id"] == mid)
            )
            if not train_mask.any() or not test_mask.any():
                continue

            train_df_view = table_sorted.loc[train_mask]
            test_df_view = table_sorted.loc[test_mask].reset_index(drop=True)

            actual_starters = {int(s["playerId"]) for s in fixture["starters"]}
            if not actual_starters or len(test_df_view) < sum(FORMATION.values()):
                continue

            wy_substr = team.wy_substr
            static_df = static_by_team[wy_substr]
            test_role_groups = test_df_view["playerId"].map(
                static_df.set_index("playerId")["role_group"].to_dict()
            )
            test_player_ids = test_df_view["playerId"]
            y_test = test_df_view["started"].to_numpy()

            cell_count += 1

            # Arm A: LR-full
            X_train_full = train_df_view[full_feature_cols].to_numpy()
            y_train      = train_df_view["started"].to_numpy()
            X_test_full  = test_df_view[full_feature_cols].to_numpy()
            r_a = _evaluate_lr("LR_full",
                                X_train_full, y_train, X_test_full, y_test,
                                test_role_groups, test_player_ids, actual_starters)
            r_a.update({"team_short": team.short, "match_id": mid})
            per_arm_records["LR_full"].append(r_a)

            # Arm B: LR-no-availability
            X_train_noavail = train_df_view[no_avail_feature_cols].to_numpy()
            X_test_noavail  = test_df_view[no_avail_feature_cols].to_numpy()
            r_b = _evaluate_lr("LR_no_avail",
                                X_train_noavail, y_train, X_test_noavail, y_test,
                                test_role_groups, test_player_ids, actual_starters)
            r_b.update({"team_short": team.short, "match_id": mid})
            per_arm_records["LR_no_avail"].append(r_b)

            # Arm C: Heuristic Composite
            r_c = _evaluate_heuristic(train_df_view, test_df_view, full_feature_cols,
                                       test_role_groups, test_player_ids, y_test,
                                       actual_starters)
            r_c.update({"team_short": team.short, "match_id": mid})
            per_arm_records["Heuristic"].append(r_c)

            if cell_count % 20 == 0:
                elapsed = time.time() - started
                rate = cell_count / elapsed
                print(f"  cell {cell_count}: team={team.short}, fixture_idx={hold_out_idx}, "
                      f"elapsed={elapsed:.0f}s, rate={rate:.2f} cells/s")

    elapsed = time.time() - started
    print(f"\nCV done. {cell_count} cells, {elapsed:.0f}s.")

    return {
        "cell_count": cell_count,
        "elapsed_s": elapsed,
        "per_arm_records": per_arm_records,
        "leak_cols_dropped_in_arm_b": leak_cols_present,
        "full_feature_n": len(full_feature_cols),
        "no_avail_feature_n": len(no_avail_feature_cols),
    }


def print_report(results: dict) -> None:
    print()
    print("=" * 80)
    print("[M-10] PER-ARM AGGREGATES")
    print("=" * 80)
    rows = []
    for arm, recs in results["per_arm_records"].items():
        ok = [r for r in recs if r.get("ok")]
        if not ok:
            print(f"  {arm}: no successful cells.")
            continue
        j = np.array([r["jaccard"] for r in ok])
        n = np.array([r["ndcg"] for r in ok if not np.isnan(r["ndcg"])])
        rows.append({
            "arm": arm,
            "n_ok": len(ok),
            "jaccard_mean": float(j.mean()),
            "jaccard_std":  float(j.std()),
            "ndcg_mean":    float(n.mean()) if len(n) else float("nan"),
        })
    agg = pd.DataFrame(rows)
    print(agg.to_string(index=False))

    # Compute the leakage delta.
    by_arm = {r["arm"]: r for r in rows}
    if "LR_full" in by_arm and "LR_no_avail" in by_arm:
        delta = by_arm["LR_full"]["jaccard_mean"] - by_arm["LR_no_avail"]["jaccard_mean"]
        print()
        print("=" * 80)
        print("[M-10] LEAKAGE DELTA (Arm A LR_full minus Arm B LR_no_avail)")
        print("=" * 80)
        print(f"  Jaccard delta: {delta:+.4f} ({delta*100:+.2f}pp)")
        if abs(delta) < 0.01:
            print("  Interpretation: leakage is ACADEMIC — feature contributes < 1pp.")
        elif abs(delta) < 0.03:
            print("  Interpretation: leakage is REAL BUT MODEST (1-3pp). Document; cite Kaufman et al. (2012).")
        else:
            print("  Interpretation: leakage is SUBSTANTIAL (>3pp). Re-cite Iter-S Jaccard with caveat.")

    if "Heuristic" in by_arm and "LR_full" in by_arm:
        h = by_arm["Heuristic"]["jaccard_mean"]
        lr = by_arm["LR_full"]["jaccard_mean"]
        print()
        print("=" * 80)
        print("[M-10] FRESH HEURISTIC COMPOSITE vs LR-FULL")
        print("=" * 80)
        print(f"  Heuristic Composite Jaccard: {h:.4f}")
        print(f"  LR_full Jaccard:             {lr:.4f}")
        print(f"  Supervised advantage:        {(lr - h)*100:+.2f}pp")
        if h < 0.50:
            print("  Interpretation: heuristic clearly weaker; supervised LR wins unambiguously.")
        elif h < 0.60:
            print("  Interpretation: heuristic is competitive; supervised edge is narrower than the historical narrative.")
        else:
            print("  Interpretation: heuristic essentially matches supervised LR — surprising; warrants deeper investigation.")


def save_results_json(results: dict, path: Path) -> None:
    payload = {
        "schema": "m10_v1",
        "cell_count": results["cell_count"],
        "elapsed_s": results["elapsed_s"],
        "leak_cols_dropped_in_arm_b": results["leak_cols_dropped_in_arm_b"],
        "full_feature_n": results["full_feature_n"],
        "no_avail_feature_n": results["no_avail_feature_n"],
        "per_arm_records": results["per_arm_records"],
    }
    path.write_text(json.dumps(payload, indent=2, default=float), encoding="utf-8")
    print(f"\n[M-10] Wrote results JSON: {path}")


def main() -> int:
    results = run_cv()
    print_report(results)
    save_results_json(results, OUT_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
