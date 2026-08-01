from __future__ import annotations

from pathlib import Path
from typing import Any
import sys

import joblib
import pandas as pd
from catboost import CatBoostClassifier
from sklearn.calibration import CalibratedClassifierCV
from sklearn.model_selection import TimeSeriesSplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ml.feature_config import BASE_FEATURES, OPTIONAL_FEATURES, OPTIMIZABLE_FEATURES, TARGET_COL


# Methodology constants. Keep aligned with data/TheNotebook.ipynb.

# Explicit chronological holdout split: train on pre-SPLIT_DATE fixtures,
# holdout = post-SPLIT_DATE. Same split the notebook reports Table 3.6
# metrics against.
SPLIT_DATE = "2024-07-01"

# Platt sigmoid + TimeSeriesSplit CV for both LR and tree models,
# consolidated to one calibration strategy across the thesis comparison.
CALIBRATION_METHOD = "sigmoid"
CALIBRATION_N_SPLITS = 3

# Train-fold-only preprocessing for bounds, medians, and calibration. The
# bundle carries a calibrated wrapper as `model` instead of a bare CatBoost
# classifier.
SCHEMA_VERSION = "uhack-catboost-v2-calibrated"


def _build_bounds(df: pd.DataFrame) -> dict[str, dict[str, float]]:
    """Compute 5th/95th percentile bounds per optimizable feature.

    The caller must pass ``train_df`` (not the full pool) so the bounds do
    not leak holdout statistics into the deployed optimizer.
    """
    bounds: dict[str, dict[str, float]] = {}
    for feat in OPTIMIZABLE_FEATURES:
        if feat not in df.columns:
            continue
        col = pd.to_numeric(df[feat], errors="coerce").dropna()
        if col.empty:
            continue
        lo = float(col.quantile(0.05))
        hi = float(col.quantile(0.95))
        if hi <= lo:
            hi = float(col.max())
            lo = float(col.min())
        bounds[feat] = {"low": round(lo, 4), "high": round(hi, 4)}
    return bounds


def build_bundle(data_csv: Path, output_joblib: Path) -> dict[str, Any]:
    """Build the deployment bundle that mirrors the notebook's research pipeline.

    The served bundle contains:
      * ``model``, a ``CalibratedClassifierCV`` wrapping CatBoost with Platt
        sigmoid + ``TimeSeriesSplit`` CV, fitted on the chronological train
        fold. ``ModelService.predict_proba`` consumes this unchanged
        (sklearn API identical to bare CatBoost).
      * ``raw_model``, a separately fitted ``CatBoostClassifier`` on the
        same train fold, used by ``ModelService.local_contributions`` for
        SHAP via ``shap.TreeExplainer`` (which needs the raw tree model,
        not the calibrated wrapper).
      * ``bounds`` and ``medians``, derived from the train fold only, so
        the optimizer's quantile bounds and imputation defaults do not
        leak holdout statistics.
      * ``provenance``, a small dict naming the split date, calibration
        method, CV scheme, and train/holdout sizes.
    """
    df = pd.read_csv(data_csv)

    if TARGET_COL not in df.columns:
        # Binary thesis target: Home Win (1) vs Not Home Win (0). Locked per
        # AGENTS.md §4 and the scope-reduction defence in scientific-validity.md.
        df[TARGET_COL] = (df["home_score"] > df["away_score"]).astype(int)

    # Chronological split
    df["match_date"] = pd.to_datetime(df["match_date"], errors="coerce")
    train_df = df[df["match_date"] < SPLIT_DATE].copy()
    holdout_df = df[df["match_date"] >= SPLIT_DATE].copy()

    if train_df.empty:
        raise RuntimeError(
            f"Chronological split at {SPLIT_DATE} produced an empty train fold. "
            "Check the match_date column and SPLIT_DATE constant."
        )

    feature_cols = [c for c in BASE_FEATURES + OPTIONAL_FEATURES if c in df.columns]
    if not feature_cols:
        raise RuntimeError("No expected model features found in dataset.")

    # Train-fold-only preprocessing
    X_train = train_df[feature_cols].apply(pd.to_numeric, errors="coerce")
    y_train = pd.to_numeric(train_df[TARGET_COL], errors="coerce").fillna(0).astype(int)

    medians = {c: float(v) for c, v in X_train.median(numeric_only=True).to_dict().items()}
    X_train = X_train.fillna(medians)

    # Calibrated model
    # CalibratedClassifierCV refits the base CatBoost inside each
    # TimeSeriesSplit fold and learns a sigmoid mapping from CV out-of-fold
    # scores to calibrated probabilities. The wrapper.predict_proba exposes
    # the same (n, 2) API as the bare CatBoost.
    base_model = CatBoostClassifier(
        iterations=300,
        depth=3,
        learning_rate=0.02,
        loss_function="Logloss",
        random_seed=42,
        verbose=False,
    )

    calibrated = CalibratedClassifierCV(
        estimator=base_model,
        method=CALIBRATION_METHOD,
        cv=TimeSeriesSplit(n_splits=CALIBRATION_N_SPLITS),
    )
    calibrated.fit(X_train, y_train)

    # Raw model for SHAP
    # shap.TreeExplainer (and CatBoost's own get_feature_importance with
    # type="ShapValues") need the underlying tree model, not the calibrated
    # wrapper. Fit a separate copy on the same train fold so
    # ExplanationService.local_contributions remains operational and the
    # SHAP values describe a CatBoost trained on the same data the
    # calibrated wrapper saw inside its CV folds.
    raw_model = CatBoostClassifier(
        iterations=300,
        depth=3,
        learning_rate=0.02,
        loss_function="Logloss",
        random_seed=42,
        verbose=False,
    )
    raw_model.fit(X_train, y_train)

    bundle: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "model": calibrated,                # API serves calibrated probabilities
        "raw_model": raw_model,             # SHAP via raw CatBoost
        "imputer": None,                    # medians applied at inference per-row
        "feature_cols": feature_cols,
        "bounds": _build_bounds(train_df),  # train-fold-only
        "medians": medians,                 # train-fold-only
        "provenance": {
            "split_date": SPLIT_DATE,
            "calibration_method": CALIBRATION_METHOD,
            "calibration_cv": f"TimeSeriesSplit(n_splits={CALIBRATION_N_SPLITS})",
            "train_n": int(len(train_df)),
            "holdout_n": int(len(holdout_df)),
            "feature_n": len(feature_cols),
        },
    }

    output_joblib.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, output_joblib)
    return bundle


if __name__ == "__main__":
    backend_root = Path(__file__).resolve().parents[1]
    data_csv = backend_root.parent / "data" / "All_Data.csv"
    output = backend_root / "ml" / "umbraro_catboost_bundle.joblib"
    bundle = build_bundle(data_csv, output)
    print(f"saved: {output}")
    print(f"schema: {bundle['schema_version']}")
    print(f"features: {len(bundle['feature_cols'])}")
    print("provenance:")
    for k, v in bundle["provenance"].items():
        print(f"  {k}: {v}")
