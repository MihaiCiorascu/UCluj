"""
[ITER-S] By-the-book multi-model XI scoring comparison.

Mirrors Iter-Q.3's methodology (used for the win-prob model choice) on the
XI scoring task: compares every viable model family on every applicable
metric across the same rolling-origin CV the deployed LR uses today,
producing a defensible empirical winner for the deploy decision.

Collapses three audit items into one rigorous iteration:
  - M-6 (per-position learned LR weights)
  - M-7 (LR vs LGBMRanker)
  - M-8 (Jaccard + NDCG@11)

Compared candidates (per ``design/scientific-validity.md`` §3.5.5):

  Classification objective (predict P(player started)):
    LogisticReg   - incumbent
    CatBoost
    XGBoost
    RandomForest
    MLP
    NaiveBayes
    SVC_RBF       - probability=True; slow

  Ranking objective (predict per-match player ranking within team):
    LGBMRanker    - lambdarank
    XGBRanker     - rank:pairwise

  Trivial baseline:
    TopByMinutes  - sort by total_minutes; no fitting

Per held-out (team, fixture_idx >= I_MIN) cell:
  1. Train rows = all rows with match_id strictly < mid (across all teams)
  2. Test rows  = candidate players for the held-out (team, fixture)
  3. For each candidate model:
       - Fit on train; score test
       - Hungarian assignment under 4-3-3 -> 11 predicted players
       - Jaccard@11 vs actual starters; NDCG@11 vs binary started/not
  4. Aggregate per-team mean/std; league aggregate

Composite ranking by rank-sum of:
  - mean Jaccard (higher better)
  - mean NDCG@11 (higher better)
  - std Jaccard (lower better)
  - per-team variance (lower better - smaller spread)

Output:
  - Stdout: ranked tables per metric + composite ranking + winner
  - JSON file: backend/scripts/_iter_s_results.json (gitignored)

Run:
  cd backend
  python -X utf8 scripts/compare_xi_models_iter_s.py

Estimated runtime: 2-6 hours (CatBoost + SVC are the slowest fits;
~350-400 CV cells x 10 models = ~3500-4000 model fits total).
"""
from __future__ import annotations

import glob
import json
import sys
import time
import warnings
from pathlib import Path
from typing import Any, Dict, List

import numpy as np
import pandas as pd

# Suppress sklearn/xgboost feature-name warnings that flood stderr in the loop.
warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

# Re-use helpers + constants from the existing training script so the
# Iter-S CV harness uses identical data prep, ensuring the comparison is
# apples-to-apples with the deployed LR pipeline.
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
from sportradar.team_registry import SUPERLIGA_TEAMS  # type: ignore  # noqa: E402

# Model builders. Hyperparameters mirror Iter-Q.3.0's MODEL_BUILDERS for
# internal consistency where applicable.

import catboost as cb  # noqa: E402
import lightgbm as lgb  # noqa: E402
from sklearn.ensemble import RandomForestClassifier  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402
from sklearn.metrics import ndcg_score  # noqa: E402
from sklearn.naive_bayes import GaussianNB  # noqa: E402
from sklearn.neural_network import MLPClassifier  # noqa: E402
from sklearn.pipeline import make_pipeline  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402
from sklearn.svm import SVC  # noqa: E402
from xgboost import XGBClassifier, XGBRanker  # noqa: E402

FORMATION = {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3}
OUT_PATH = Path(__file__).resolve().parent / "_iter_s_results.json"


# ── Model builders ──────────────────────────────────────────────────────────


def _build_classifiers() -> Dict[str, Any]:
    return {
        "LogisticReg":  make_pipeline(StandardScaler(),
                                       LogisticRegression(max_iter=1000,
                                                           class_weight="balanced",
                                                           C=1.0,
                                                           solver="lbfgs",
                                                           random_state=42)),
        "CatBoost":     cb.CatBoostClassifier(iterations=300, depth=3,
                                              learning_rate=0.02,
                                              random_state=42, verbose=0),
        "XGBoost":      XGBClassifier(n_estimators=300, learning_rate=0.02,
                                       max_depth=3, random_state=42,
                                       eval_metric="logloss"),
        "RandomForest": RandomForestClassifier(n_estimators=300, max_depth=4,
                                                class_weight="balanced",
                                                random_state=42),
        "MLP":          make_pipeline(StandardScaler(),
                                       MLPClassifier(hidden_layer_sizes=(64, 32),
                                                      max_iter=2000,
                                                      early_stopping=True,
                                                      validation_fraction=0.1,
                                                      random_state=42)),
        "NaiveBayes":   GaussianNB(),
        "SVC_RBF":      make_pipeline(StandardScaler(),
                                       SVC(kernel="rbf", C=1.0, gamma="scale",
                                            probability=True, random_state=42)),
    }


def _build_rankers() -> Dict[str, Any]:
    return {
        "LGBMRanker": lgb.LGBMRanker(n_estimators=200, max_depth=6,
                                      objective="lambdarank", random_state=42,
                                      verbose=-1),
        "XGBRanker":  XGBRanker(n_estimators=200, max_depth=6,
                                 objective="rank:pairwise", random_state=42),
    }


# ── Metric helpers ──────────────────────────────────────────────────────────


def _jaccard_at_11(pred_set: set, actual: set) -> float:
    union = pred_set | actual
    return (len(pred_set & actual) / len(union)) if union else 0.0


def _ndcg_at_11(y_true: np.ndarray, y_score: np.ndarray) -> float:
    """NDCG@11 — the player ranking quality, ignoring formation constraints.

    y_true: (n_candidates,) binary, 1 = started, 0 = bench/excluded.
    y_score: (n_candidates,) raw score (probability or ranker output).
    """
    if len(y_true) < 2 or y_true.sum() == 0:
        return float("nan")
    try:
        return float(ndcg_score(y_true.reshape(1, -1), y_score.reshape(1, -1), k=11))
    except Exception:
        return float("nan")


def _score_to_xi_set(scores: np.ndarray, role_groups: pd.Series, player_ids: pd.Series) -> set:
    """Run Hungarian assignment and return the predicted XI as a set of playerIds."""
    test_df = pd.DataFrame({
        "playerId": player_ids.values,
        "role_group": role_groups.values,
        "score": scores,
    })
    return set(_hungarian_xi(test_df, formation=FORMATION))


# ── Per-cell evaluation ─────────────────────────────────────────────────────


def _evaluate_cell(
    name: str,
    builder,
    X_train: np.ndarray,
    y_train: np.ndarray,
    train_group_sizes: List[int],
    X_test: np.ndarray,
    y_test: np.ndarray,
    test_role_groups: pd.Series,
    test_player_ids: pd.Series,
    actual_starters: set,
    is_ranker: bool,
) -> Dict[str, float]:
    """Fit one model on the train rows; score the test rows; return metrics."""
    try:
        model = builder() if callable(builder) else builder
        if is_ranker:
            model.fit(X_train, y_train, group=train_group_sizes)
            scores = np.asarray(model.predict(X_test), dtype=float)
        else:
            model.fit(X_train, y_train)
            if hasattr(model, "predict_proba"):
                scores = np.asarray(model.predict_proba(X_test)[:, 1], dtype=float)
            else:
                scores = np.asarray(model.decision_function(X_test), dtype=float)

        pred = _score_to_xi_set(scores, test_role_groups, test_player_ids)
        jacc = _jaccard_at_11(pred, actual_starters)
        ndcg = _ndcg_at_11(y_test, scores)
        return {"jaccard": jacc, "ndcg": ndcg, "ok": True}
    except Exception as exc:
        return {"jaccard": float("nan"), "ndcg": float("nan"),
                "ok": False, "err": f"{type(exc).__name__}: {exc}"}


def _evaluate_baseline_top_by_minutes(
    test_df_full: pd.DataFrame,
    test_role_groups: pd.Series,
    test_player_ids: pd.Series,
    y_test: np.ndarray,
    actual_starters: set,
) -> Dict[str, float]:
    """Trivial baseline: rank by total_minutes; Hungarian-assign top 11."""
    if "total_minutes" not in test_df_full.columns:
        return {"jaccard": float("nan"), "ndcg": float("nan"), "ok": False,
                "err": "no total_minutes column"}
    scores = np.asarray(test_df_full["total_minutes"].fillna(0.0).to_numpy(), dtype=float)
    pred = _score_to_xi_set(scores, test_role_groups, test_player_ids)
    jacc = _jaccard_at_11(pred, actual_starters)
    ndcg = _ndcg_at_11(y_test, scores)
    return {"jaccard": jacc, "ndcg": ndcg, "ok": True}


# ── Main CV loop ────────────────────────────────────────────────────────────


def run_cv() -> dict:
    print("=" * 70)
    print("[ITER-S] Multi-model XI scoring comparison")
    print("=" * 70)
    print()
    print("Loading data ...")
    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    print(f"  {len(match_files)} match files, {len(profiles)} player profiles.")

    if not LINEUP_HISTORY.exists():
        raise FileNotFoundError(
            "Lineup history missing — run extract_starting_xi_history_league.py first."
        )
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
    print(f"  positives: {int(table['started'].sum())}/{len(table)} "
          f"({table['started'].mean():.2%})")

    skip_cols = {"playerId", "team_short", "match_id", "fixture_idx",
                 "season_id", "round_id", "started"}
    feature_cols = [c for c in table.columns
                    if c not in skip_cols
                    and table[c].dtype in (np.float64, np.float32, np.int64, np.int32)]
    print(f"  feature cols: {len(feature_cols)}")

    table_sorted = table.sort_values(["match_id"]).reset_index(drop=True)

    classifiers = _build_classifiers()
    rankers = _build_rankers()

    # Per-model accumulators: list of (jaccard, ndcg) tuples + per-team Jaccard lists.
    per_model_records: Dict[str, List[dict]] = {
        name: [] for name in (list(classifiers) + list(rankers) + ["TopByMinutes"])
    }
    per_team_jaccards: Dict[str, Dict[str, List[float]]] = {
        name: {t.short: [] for t in SUPERLIGA_TEAMS}
        for name in (list(classifiers) + list(rankers) + ["TopByMinutes"])
    }

    print("\n--- Running rolling-origin CV ---")
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

            train_view = table_sorted.loc[train_mask]
            # Group sizes for rankers — sorted by (team_short, match_id) within train_view.
            # We re-sort a copy so group_sizes line up with X_train.
            train_view_sorted = train_view.sort_values(["team_short", "match_id", "playerId"]).reset_index(drop=True)
            X_train_r = train_view_sorted[feature_cols].to_numpy()
            y_train_r = train_view_sorted["started"].to_numpy()
            group_sizes = (
                train_view_sorted.groupby(["team_short", "match_id"], sort=False)
                .size()
                .to_list()
            )
            # Classifier order doesn't need group structure
            X_train_c = train_view[feature_cols].to_numpy()
            y_train_c = train_view["started"].to_numpy()

            test_view = table_sorted.loc[test_mask].reset_index(drop=True)
            X_test = test_view[feature_cols].to_numpy()
            y_test = test_view["started"].to_numpy()

            wy_substr = team.wy_substr
            static_df = static_by_team[wy_substr]
            test_role_groups = test_view["playerId"].map(
                static_df.set_index("playerId")["role_group"].to_dict()
            )
            test_player_ids = test_view["playerId"]

            actual_starters = {int(s["playerId"]) for s in fixture["starters"]}

            # Skip cells with no actual starters or fewer test rows than the formation needs
            if not actual_starters or len(test_view) < sum(FORMATION.values()):
                continue

            cell_count += 1

            # Classifiers
            for name, _ in classifiers.items():
                m = _evaluate_cell(
                    name, lambda n=name: _build_classifiers()[n],
                    X_train_c, y_train_c, [],
                    X_test, y_test,
                    test_role_groups, test_player_ids, actual_starters,
                    is_ranker=False,
                )
                m["team_short"] = team.short
                m["match_id"] = mid
                per_model_records[name].append(m)
                if m["ok"]:
                    per_team_jaccards[name][team.short].append(m["jaccard"])

            # Rankers
            for name, _ in rankers.items():
                m = _evaluate_cell(
                    name, lambda n=name: _build_rankers()[n],
                    X_train_r, y_train_r, group_sizes,
                    X_test, y_test,
                    test_role_groups, test_player_ids, actual_starters,
                    is_ranker=True,
                )
                m["team_short"] = team.short
                m["match_id"] = mid
                per_model_records[name].append(m)
                if m["ok"]:
                    per_team_jaccards[name][team.short].append(m["jaccard"])

            # Baseline
            tbm = _evaluate_baseline_top_by_minutes(
                test_view, test_role_groups, test_player_ids, y_test, actual_starters,
            )
            tbm["team_short"] = team.short
            tbm["match_id"] = mid
            per_model_records["TopByMinutes"].append(tbm)
            if tbm["ok"]:
                per_team_jaccards["TopByMinutes"][team.short].append(tbm["jaccard"])

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
        "per_model_records": per_model_records,
        "per_team_jaccards": per_team_jaccards,
        "model_names": list(classifiers) + list(rankers) + ["TopByMinutes"],
    }


# ── Reporting + composite ranking ───────────────────────────────────────────


def _aggregate_per_model(per_model_records: Dict[str, List[dict]]) -> pd.DataFrame:
    rows = []
    for name, recs in per_model_records.items():
        ok = [r for r in recs if r.get("ok")]
        n_ok = len(ok)
        n_total = len(recs)
        if not ok:
            rows.append({"model": name, "n_ok": 0, "n_total": n_total,
                         "jaccard_mean": float("nan"), "jaccard_std": float("nan"),
                         "ndcg_mean": float("nan"), "ndcg_std": float("nan")})
            continue
        j = np.array([r["jaccard"] for r in ok])
        n = np.array([r["ndcg"] for r in ok if not np.isnan(r["ndcg"])])
        rows.append({
            "model": name,
            "n_ok": n_ok,
            "n_total": n_total,
            "jaccard_mean": float(j.mean()),
            "jaccard_std":  float(j.std()),
            "ndcg_mean":    float(n.mean()) if len(n) else float("nan"),
            "ndcg_std":     float(n.std())  if len(n) else float("nan"),
        })
    return pd.DataFrame(rows)


def _aggregate_per_team(per_team_jaccards: Dict[str, Dict[str, List[float]]]) -> pd.DataFrame:
    rows = []
    for model, by_team in per_team_jaccards.items():
        means = [float(np.mean(v)) for v in by_team.values() if v]
        rows.append({
            "model": model,
            "team_mean_of_means": float(np.mean(means)) if means else float("nan"),
            "team_std_of_means":  float(np.std(means))  if means else float("nan"),
        })
    return pd.DataFrame(rows)


def _composite_rank(agg: pd.DataFrame, team_agg: pd.DataFrame) -> pd.DataFrame:
    merged = agg.merge(team_agg, on="model", how="outer")
    # Ranks: jaccard_mean / ndcg_mean higher better; jaccard_std / team_std_of_means lower better
    merged["rk_jacc"]      = merged["jaccard_mean"].rank(ascending=False, na_option="bottom")
    merged["rk_ndcg"]      = merged["ndcg_mean"].rank(ascending=False, na_option="bottom")
    merged["rk_jacc_std"]  = merged["jaccard_std"].rank(ascending=True, na_option="bottom")
    merged["rk_team_var"]  = merged["team_std_of_means"].rank(ascending=True, na_option="bottom")
    merged["rank_sum"]     = merged[["rk_jacc", "rk_ndcg", "rk_jacc_std", "rk_team_var"]].sum(axis=1)
    return merged.sort_values("rank_sum")


def print_report(results: dict) -> None:
    agg = _aggregate_per_model(results["per_model_records"])
    team_agg = _aggregate_per_team(results["per_team_jaccards"])

    print()
    print("=" * 80)
    print("[ITER-S] PER-MODEL AGGREGATES (sorted by Jaccard mean)")
    print("=" * 80)
    print(agg.sort_values("jaccard_mean", ascending=False).to_string(index=False))

    print()
    print("=" * 80)
    print("[ITER-S] PER-MODEL TEAM-LEVEL AGGREGATES (mean and std of per-team Jaccard)")
    print("=" * 80)
    print(team_agg.to_string(index=False))

    print()
    print("=" * 80)
    print("[ITER-S] COMPOSITE RANKING (rank-sum: jaccard_mean DESC, ndcg_mean DESC, "
          "jaccard_std ASC, team_var ASC; lower rank_sum = better)")
    print("=" * 80)
    composite = _composite_rank(agg, team_agg)
    print(composite.to_string(index=False))

    winner = composite.iloc[0]["model"]
    print()
    print(f"[ITER-S] Composite winner: {winner}")


def save_results_json(results: dict, path: Path) -> None:
    payload = {
        "schema": "iter_s_v1",
        "cell_count": results["cell_count"],
        "elapsed_s": results["elapsed_s"],
        "models": results["model_names"],
        "per_model_records": results["per_model_records"],
        "per_team_jaccards": {
            m: {t: list(map(float, v)) for t, v in by_team.items()}
            for m, by_team in results["per_team_jaccards"].items()
        },
    }
    path.write_text(json.dumps(payload, indent=2, default=float), encoding="utf-8")
    print(f"[ITER-S] Wrote results JSON: {path}")


def main() -> int:
    results = run_cv()
    print_report(results)
    save_results_json(results, OUT_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
