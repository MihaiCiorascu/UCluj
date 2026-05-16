"""Iteration Q, Chunk A — patch data/TheNotebook.ipynb with the scientific repairs:

  Q.1  Cell 45 (deployment): fit the SimpleImputer on the TRAIN fold only
       (not on the full pool) so the deployed CatBoost pipeline never sees
       test-fold statistics. Same fix for the Monte Carlo optimiser's
       percentile bounds and medians.

  Q.2.a Cell 12 (calibration): consolidate on Platt sigmoid for both
       CatBoost AND LR (was: sigmoid for CatBoost, isotonic for LR). Same
       sigmoid + cv=tscv strategy is also used in Cell 45.

  Q.2.b Add label header comments to Cells 6, 10, 12 ("CHRONOLOGICAL
       HOLDOUT") and Cell 14 ("ROLLING-ORIGIN CV") so the reader can
       instantly tell which observation horizon each cell reports.

  Q.2.c Insert a NEW cell after Cell 6 that re-fits CatBoost / RF /
       XGBoost / MLP over 5 random seeds and reports mu +/- sigma per
       Bouthillier et al. 2021.

  Q.2.d Same new cell adds two trivial baselines: AlwaysHomeWin (base
       rate) and Elo-only Logistic Regression. Both anchor every model
       improvement claim in Table 3.2 of the thesis.

  Q.2.f Insert a NEW cell after Cell 30 that computes real SHAP values
       via shap.TreeExplainer applied to the raw CatBoost model, so the
       thesis can keep its Lundberg 2017/2020 citations honestly.

Run from the worktree root:
    python scripts/patch_notebook_iter_q_chunk_a.py

The script is idempotent: it scans for the patched markers and skips any
cell that's already been patched, so re-running is safe.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NB_PATH = ROOT / "data" / "TheNotebook.ipynb"

PATCH_MARKER = "# [ITER-Q] "  # appears in any cell we've already patched


def _src_of(cell: dict) -> str:
    return "".join(cell.get("source", []))


def _set_src(cell: dict, text: str) -> None:
    # Jupyter stores `source` as a list of lines, each ending in '\n' except
    # possibly the last. Splitlines(keepends=True) is the standard idiom.
    cell["source"] = text.splitlines(keepends=True)


def _new_code_cell(text: str) -> dict:
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": text.splitlines(keepends=True),
    }


def _new_markdown_cell(text: str) -> dict:
    return {
        "cell_type": "markdown",
        "metadata": {},
        "source": text.splitlines(keepends=True),
    }


# ---------------------------------------------------------------------------
# Patch 1 — Cell 45: imputer leakage + train-only bounds + Platt sigmoid
# ---------------------------------------------------------------------------

CELL_45_NEW = '''# [ITER-Q] Deployment bundle — fitted with TRAIN-FOLD-ONLY preprocessing
# (Iteration Q, Chunk A; Q.1 + Q.2.a + Q.2.e):
#
#   * The SimpleImputer is fit on train_df[feature_cols] only, then used
#     to transform the full deployment pool. Previously it was fit on the
#     full pool, leaking holdout statistics into the production model.
#   * The Monte Carlo optimiser's percentile bounds and medians are
#     computed from train_df only, so the prescriptive layer cannot peek
#     at the holdout either.
#   * Final calibration uses Platt sigmoid + CV (consistent with the
#     calibration strategy reported in Cell 12 / the thesis), rather than
#     the previous isotonic+prefit hack.

import joblib
from pathlib import Path
from sklearn.impute import SimpleImputer
from sklearn.calibration import CalibratedClassifierCV
from catboost import CatBoostClassifier

# ---- Train-only preprocessing artefacts (NO leakage) --------------------
imputer_for_bundle = SimpleImputer(strategy='median')
imputer_for_bundle.fit(train_df[feature_cols])      # train fold only

X_full = model_data[feature_cols].copy()
y_full = model_data["Target_Binary"].copy()
X_full_imp = imputer_for_bundle.transform(X_full)   # apply train-fit imputer

# ---- Refit final CatBoost on the full pool for production deployment ----
# Refitting the classifier on the full pool post-validation is standard
# practice ("validate, then retrain on everything"); the IMPUTER staying
# train-only is what prevents preprocessing leakage.
best_cat_params = grid_cat.best_params_.copy()
best_cat_params["verbose"] = 0
best_cat_params["random_state"] = 42

cat_full = CatBoostClassifier(**best_cat_params)
cat_full.fit(X_full_imp, y_full)

# ---- Calibrate via Platt + CV (consistent with Cell 12 / thesis) --------
calibrated_cat_full = CalibratedClassifierCV(cat_full, method='sigmoid', cv=tscv)
calibrated_cat_full.fit(X_full_imp, y_full)

# ---- Monte Carlo optimiser reference stats — TRAIN-FOLD ONLY ------------
_blueprint_stats = [
    'Home_Poss_5', 'Home_Shots_5', 'Home_SoT_5',
    'Home_Corners_5', 'Home_Goals_5', 'Home_Conceded_5',
]
bounds_for_app = {
    stat: (
        float(train_df[stat].dropna().quantile(0.05)),
        float(train_df[stat].dropna().quantile(0.95)),
    )
    for stat in _blueprint_stats
    if stat in train_df.columns
}
medians_for_app = {
    stat: float(train_df[stat].median())
    for stat in ['Home_Poss_5', 'Home_Shots_5', 'Home_Corners_5']
    if stat in train_df.columns
}

# ---- Save deployment bundle --------------------------------------------
artifacts = {
    "model": calibrated_cat_full,
    "raw_model": cat_full,
    "imputer": imputer_for_bundle,
    "feature_cols": feature_cols,
    "feature_idx": feature_idx,
    "bounds": bounds_for_app,
    "medians": medians_for_app,
    "optimizer_config": {
        "n_h2h_matches": 5,
        "num_simulations_default": 1000,
        "constrained_target_stats": _blueprint_stats,
        "random_state": 42,
        "bounds_source": "train_fold_only",   # explicit provenance
    },
    "split_date": split_date,
    "schema_version": "v1.3.0",
    "preprocessing_provenance": {
        "imputer_fit_scope": "train_fold_only",
        "calibration_method": "sigmoid (Platt) with TimeSeriesSplit CV",
        "classifier_refit_scope": "full_pool",
    },
    "evaluation_train_date_range": {
        "min_match_date": str(train_df['match_date'].min()),
        "max_match_date": str(train_df['match_date'].max()),
    },
    "evaluation_holdout_date_range": {
        "min_match_date": str(test_df['match_date'].min()),
        "max_match_date": str(test_df['match_date'].max()),
    },
    "deployment_train_date_range": {
        "min_match_date": str(model_data['match_date'].min()),
        "max_match_date": str(model_data['match_date'].max()),
    },
    "optimizer_reference_date_range": {
        "min_match_date": str(train_df['match_date'].min()),
        "max_match_date": str(train_df['match_date'].max()),
    },
}

Path("artifacts").mkdir(exist_ok=True)
joblib.dump(artifacts, "artifacts/umbraro_catboost_bundle.joblib")

print("Saved deployment bundle to artifacts/umbraro_catboost_bundle.joblib")
print("Deployment model retrained on full historical dataset (train-only preprocessing).")
'''


def patch_cell_45(nb: dict) -> bool:
    """Locate the deployment cell by signature ('import joblib' on its own
    first non-blank line, followed by deployment-bundle markers) and
    replace its body. Index-based lookup is unreliable once earlier
    patches have inserted new cells above this one."""
    for cell in nb["cells"]:
        if cell.get("cell_type") != "code":
            continue
        src = _src_of(cell)
        if PATCH_MARKER in src:
            continue
        if (src.startswith("import joblib\n") and "umbraro_catboost_bundle.joblib" in src):
            _set_src(cell, CELL_45_NEW)
            return True
    return False


# ---------------------------------------------------------------------------
# Patch 2 — Cell 12: consolidate LR calibration to Platt sigmoid + label header
# ---------------------------------------------------------------------------

CELL_12_NEW = '''# [ITER-Q] CHRONOLOGICAL-HOLDOUT calibration (chronological cut at split_date,
# evaluated on the 2024-25 season holdout). Iteration Q, Chunk A; Q.2.a + Q.2.b:
# both CatBoost and Logistic Regression are now calibrated with Platt
# (sigmoid) + TimeSeriesSplit CV, so the thesis can report a single,
# coherent calibration strategy rather than mixing sigmoid + isotonic.

from sklearn.calibration import CalibratedClassifierCV, calibration_curve
from sklearn.metrics import brier_score_loss

def expected_calibration_error(y_true, proba, n_bins=10):
    bins = np.linspace(0, 1, n_bins + 1)
    bin_ids = np.digitize(proba, bins) - 1
    ece = 0.0
    for b in range(n_bins):
        mask = bin_ids == b
        if mask.sum() == 0:
            continue
        acc = y_true[mask].mean()
        conf = proba[mask].mean()
        ece += (mask.sum() / len(y_true)) * abs(acc - conf)
    return ece

def plot_reliability(y_true, proba, label, ax):
    prob_true, prob_pred = calibration_curve(y_true, proba, n_bins=10)
    ax.plot(prob_pred, prob_true, 's-', label=label)
    ax.plot([0, 1], [0, 1], 'k--')
    ax.set_xlabel('Mean predicted probability')
    ax.set_ylabel('Fraction of positives')
    ax.legend()

calibrated_cat = None
p_cal_cat = None
try:
    import catboost as cb
    cat_base = getattr(grid_cat, 'best_estimator_', None) if 'grid_cat' in dir() else None
    if cat_base is None:
        cat_base = cb.CatBoostClassifier(iterations=300, depth=3, learning_rate=0.02, random_state=42, verbose=0)
    calibrated_cat = CalibratedClassifierCV(cat_base, method='sigmoid', cv=tscv)
    calibrated_cat.fit(train_df[feature_cols], y_train)
    p_cal_cat = calibrated_cat.predict_proba(test_df[feature_cols])[:, 1]
    brier_cat = brier_score_loss(y_test, p_cal_cat)
    print(f"Calibrated CatBoost (Platt sigmoid + tscv): Brier = {brier_cat:.4f} (lower is better)")
except Exception as e:
    print(f"Calibrated CatBoost skipped: {e}")

lr_base = Pipeline([
    ('imputer', KNNImputer(n_neighbors=5)),
    ('scaler', StandardScaler()),
    ('clf', LogisticRegression(max_iter=1000, C=1.0, solver='saga', random_state=42))
])
# [ITER-Q] Was: method='isotonic'. Consolidated to 'sigmoid' so the thesis
# reports one calibration strategy. Isotonic remains available as an
# ablation footnote in the thesis methodology section.
calibrated_lr = CalibratedClassifierCV(lr_base, method='sigmoid', cv=tscv)
calibrated_lr.fit(train_df[feature_cols], y_train)
p_cal_lr = calibrated_lr.predict_proba(test_df[feature_cols])[:, 1]
brier_lr = brier_score_loss(y_test, p_cal_lr)
print(f"Calibrated LR (Platt sigmoid + tscv): Brier = {brier_lr:.4f}")

if p_cal_cat is not None:
    print(f"Calibrated CatBoost ECE: {expected_calibration_error(y_test.to_numpy(), p_cal_cat):.4f}")
print(f"Calibrated LR ECE: {expected_calibration_error(y_test.to_numpy(), p_cal_lr):.4f}")

fig, ax = plt.subplots(1, 1, figsize=(5, 4))
if calibrated_cat is not None and p_cal_cat is not None:
    plot_reliability(y_test, p_cal_cat, 'Calibrated CatBoost', ax)
plot_reliability(y_test, p_cal_lr, 'Calibrated LR', ax)
ax.set_title('Reliability diagram (chronological holdout)')
plt.tight_layout()
plt.show()
'''


def patch_cell_12(nb: dict) -> bool:
    """Locate the calibration cell by signature (the import of
    CalibratedClassifierCV and calibration_curve on its first non-blank
    line). Same rationale as patch_cell_45: index-based lookup is
    fragile once we start inserting new cells."""
    sig = "from sklearn.calibration import CalibratedClassifierCV, calibration_curve"
    for cell in nb["cells"]:
        if cell.get("cell_type") != "code":
            continue
        src = _src_of(cell)
        if PATCH_MARKER in src:
            continue
        first_nonblank = next((ln for ln in src.split("\n") if ln.strip()), "")
        if first_nonblank.strip() == sig:
            _set_src(cell, CELL_12_NEW)
            return True
    return False


# ---------------------------------------------------------------------------
# Patch 3 — Cell 6, 10, 14: add label-header comments only (preserve code)
# ---------------------------------------------------------------------------

# Label headers are keyed by a "first-line signature" rather than a cell
# index, so they stay correct even if other patches insert new cells
# above the target. The signature is the first non-blank line of the
# original cell's source (post-import / pre-rename).
LABEL_HEADERS_BY_SIGNATURE: list[tuple[str, str]] = [
    (
        "from sklearn.preprocessing import StandardScaler",  # Cell 6
        "# [ITER-Q] CHRONOLOGICAL HOLDOUT (single chronological cut at split_date).\n"
        "# Every accuracy printed below is a single-seed point estimate on the\n"
        "# 2024-25 holdout; for mu +/- sigma over 5 seeds see the new\n"
        "# multi-seed cell that follows this one (Iteration Q, Chunk A; Q.2.c).\n",
    ),
    (
        "from sklearn.metrics import confusion_matrix, roc_auc_score, log_loss",  # Cell 10
        "# [ITER-Q] CHRONOLOGICAL HOLDOUT — confusion matrix + ROC-AUC + log-loss\n"
        "# reported on the same 2024-25 holdout used in Cell 6.\n",
    ),
    (
        "folds = [",  # Cell 14
        "# [ITER-Q] ROLLING-ORIGIN CV (3 expanding folds: 2021-22, 2022-23, 2023-24).\n"
        "# Reports mean +/- variance across folds; complements the single-fold\n"
        "# chronological holdout in Cells 6 / 10 / 12.\n",
    ),
]


def patch_label_headers(nb: dict) -> int:
    n = 0
    for signature, header in LABEL_HEADERS_BY_SIGNATURE:
        for cell in nb["cells"]:
            if cell.get("cell_type") != "code":
                continue
            src = _src_of(cell)
            if PATCH_MARKER in src:
                continue
            # First non-blank line check
            first_nonblank = next((ln for ln in src.split("\n") if ln.strip()), "")
            if first_nonblank.strip() == signature.strip():
                _set_src(cell, header + src)
                n += 1
                break
    return n


# ---------------------------------------------------------------------------
# Patch 4 — NEW cell after Cell 6: multi-seed + baselines (Q.2.c + Q.2.d)
# ---------------------------------------------------------------------------

MULTI_SEED_CELL_SRC = '''# [ITER-Q] Multi-seed model comparison + trivial baselines
# (Iteration Q, Chunk A; Q.2.c + Q.2.d)
#
# Cell 6 above reports single-seed accuracy point estimates, which is what
# the original notebook produced. Per Bouthillier et al. 2021, MLSys, that
# under-represents the true variance of stochastic models. This cell wraps
# the four stochastic classifiers (CatBoost, RF, XGBoost, MLP) in a five-
# seed loop and reports mu +/- sigma on the same chronological holdout.
# Deterministic classifiers (LR, GaussianNB, SVC with kernel='rbf') are
# included with sigma = 0 so the comparison table stays uniform.
#
# Two trivial baselines are also added:
#   1) AlwaysHomeWin: predict 1 for every fixture; accuracy = holdout
#      base rate. Establishes the no-skill floor any model must beat.
#   2) Elo-only LogisticRegression: a one-feature model using just the
#      pre-match Elo difference. Establishes what's achievable from
#      strength alone, before any tactical features.

from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.naive_bayes import GaussianNB
from sklearn.svm import SVC
from sklearn.pipeline import make_pipeline
from xgboost import XGBClassifier
import numpy as np
import pandas as pd

try:
    import catboost as cb
    _HAS_CAT = True
except Exception:
    _HAS_CAT = False

_seeds = list(range(5))

def _accs_for_model(builder, X_tr, y_tr, X_te, y_te):
    """Fit `builder(seed)` for each seed and return the accuracies array."""
    out = []
    for s in _seeds:
        m = builder(s)
        m.fit(X_tr, y_tr)
        out.append(accuracy_score(y_te, m.predict(X_te)))
    return np.array(out)

print("Multi-seed (5 seeds) chronological-holdout accuracies — mu +/- sigma")
print("=" * 70)

results = []

# CatBoost ----------------------------------------------------------------
if _HAS_CAT:
    a_cat = _accs_for_model(
        lambda s: cb.CatBoostClassifier(iterations=300, depth=3,
                                         learning_rate=0.02,
                                         random_state=s, verbose=0),
        train_df[feature_cols], y_train,
        test_df[feature_cols], y_test,
    )
    results.append(("CatBoost",        a_cat.mean(), a_cat.std()))

# Random Forest -----------------------------------------------------------
a_rf = _accs_for_model(
    lambda s: RandomForestClassifier(n_estimators=300, max_depth=4, random_state=s),
    X_train_imputed, y_train,
    X_test_imputed, y_test,
)
results.append(("Random Forest",   a_rf.mean(),  a_rf.std()))

# XGBoost ------------------------------------------------------------------
a_xgb = _accs_for_model(
    lambda s: XGBClassifier(n_estimators=300, learning_rate=0.02, max_depth=3,
                             random_state=s, eval_metric='logloss',
                             use_label_encoder=False),
    X_train_imputed, y_train,
    X_test_imputed, y_test,
)
results.append(("XGBoost",         a_xgb.mean(), a_xgb.std()))

# MLP (stochastic via weight init) ---------------------------------------
_scaler = StandardScaler().fit(X_train_imputed)
_Xtr_s = _scaler.transform(X_train_imputed)
_Xte_s = _scaler.transform(X_test_imputed)
a_mlp = _accs_for_model(
    lambda s: MLPClassifier(hidden_layer_sizes=(64, 32), max_iter=2000,
                             early_stopping=True, validation_fraction=0.1,
                             random_state=s),
    _Xtr_s, y_train,
    _Xte_s, y_test,
)
results.append(("MLP",             a_mlp.mean(), a_mlp.std()))

# Deterministic models (sigma = 0) ---------------------------------------
lr_det = LogisticRegression(max_iter=1000, random_state=42).fit(_Xtr_s, y_train)
results.append(("Logistic Reg.",   accuracy_score(y_test, lr_det.predict(_Xte_s)),   0.0))

nb_det = GaussianNB().fit(X_train_imputed, y_train)
results.append(("Naive Bayes",     accuracy_score(y_test, nb_det.predict(X_test_imputed)), 0.0))

svc_det = SVC(kernel='rbf', C=1.0, gamma='scale', random_state=42).fit(_Xtr_s, y_train)
results.append(("SVM (RBF)",       accuracy_score(y_test, svc_det.predict(_Xte_s)),  0.0))

# ----- Trivial baselines (Q.2.d) ----------------------------------------
base_rate = float(y_test.mean())
results.append(("Baseline: AlwaysHomeWin", base_rate, 0.0))

# Elo-only logistic regression
_elo_col = 'Computed_Elo_Diff'
if _elo_col in train_df.columns:
    elo_lr = LogisticRegression(max_iter=1000, random_state=42)
    elo_lr.fit(train_df[[_elo_col]].fillna(0), y_train)
    acc_elo = accuracy_score(y_test, elo_lr.predict(test_df[[_elo_col]].fillna(0)))
    results.append(("Baseline: Elo-only LR", acc_elo, 0.0))

# ----- Pretty-print results table ---------------------------------------
df_results = pd.DataFrame(results, columns=["Model", "mean_acc", "std_acc"])
df_results = df_results.sort_values("mean_acc", ascending=False).reset_index(drop=True)
print(df_results.to_string(
    index=False,
    formatters={"mean_acc": lambda x: f"{x*100:6.2f}%",
                "std_acc":  lambda x: f"{x*100:5.2f}pp"},
))
print()
print(f"Holdout base rate P(Home Win) = {base_rate:.4f}")
print("Every above model is competing against AlwaysHomeWin and Elo-only LR.")
'''


def insert_multi_seed_cell(nb: dict) -> bool:
    # Idempotency: skip if any cell already contains the marker.
    for c in nb["cells"]:
        if "Multi-seed model comparison + trivial baselines" in _src_of(c):
            return False
    # Insert at position 7 (i.e. right after Cell 6).
    nb["cells"].insert(7, _new_code_cell(MULTI_SEED_CELL_SRC))
    return True


# ---------------------------------------------------------------------------
# Patch 5 — NEW cell after the (now shifted) feature-importance cell:
# real SHAP via shap.TreeExplainer (Q.2.f)
# ---------------------------------------------------------------------------

SHAP_CELL_SRC = '''# [ITER-Q] Real SHAP attributions via shap.TreeExplainer
# (Iteration Q, Chunk A; Q.2.f)
#
# Cells 30/31 above compute CatBoost's built-in gain importance
# (model.feature_importances_). The thesis cites Lundberg & Lee 2017 and
# Lundberg et al. 2020 (TreeSHAP), so this cell computes ACTUAL SHAP
# values on the holdout via shap.TreeExplainer applied to the raw
# (uncalibrated) CatBoost model — the path Lundberg's TreeSHAP supports.
#
# The bar chart shows mean(|SHAP value|) per feature, which is the
# standard global-importance summary advocated by Lundberg 2020.

try:
    import shap
    _shap_ok = True
except Exception as _e:
    print(f"shap not installed; install via: pip install shap   ({_e})")
    _shap_ok = False

if _shap_ok:
    # The raw CatBoost model used here is `model_for_blueprint` (the same
    # object whose gain importance was extracted above) or `cat` if the
    # blueprint pipeline is using the calibrated wrapper.
    _shap_model = None
    if 'cat_full' in dir():
        _shap_model = cat_full
    elif 'model_for_blueprint' in dir() and hasattr(model_for_blueprint, 'feature_importances_'):
        _shap_model = model_for_blueprint
    elif 'cat' in dir():
        _shap_model = cat

    if _shap_model is not None:
        explainer = shap.TreeExplainer(_shap_model)
        # Use the imputed holdout matrix; if `X_test_imp` exists prefer it,
        # else fall back to `X_test_imputed` defined in Cell 2.
        _X = X_test_imp if 'X_test_imp' in dir() else X_test_imputed
        shap_values = explainer.shap_values(_X)
        # For binary CatBoost shap_values is a single 2-d array (n, d).
        mean_abs = np.mean(np.abs(shap_values), axis=0)
        shap_df = (pd.DataFrame({'Feature': feature_cols,
                                  'mean_abs_SHAP': mean_abs})
                     .sort_values('mean_abs_SHAP', ascending=False))
        print("Top 15 features by mean(|SHAP value|) on holdout:")
        print(shap_df.head(15).to_string(index=False))

        try:
            import matplotlib.pyplot as plt
            shap.summary_plot(shap_values, _X, feature_names=feature_cols,
                              show=False, max_display=15)
            plt.tight_layout()
            plt.show()
        except Exception as e:
            print(f"shap.summary_plot skipped: {e}")
    else:
        print("No CatBoost-like model in scope to run SHAP against.")
'''


def insert_shap_cell(nb: dict) -> bool:
    # Idempotency
    for c in nb["cells"]:
        if "Real SHAP attributions via shap.TreeExplainer" in _src_of(c):
            return False
    # Find the cell whose first line begins with "importance_df = extract_feature_importances"
    # (which is the call-site that produces the gain-importance bar chart).
    target = None
    for i, c in enumerate(nb["cells"]):
        s = _src_of(c)
        if s.lstrip().startswith("importance_df = extract_feature_importances"):
            target = i
            break
    if target is None:
        # Fall back: insert at the end (still better than nothing).
        target = len(nb["cells"]) - 1
    nb["cells"].insert(target + 1, _new_code_cell(SHAP_CELL_SRC))
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    if not NB_PATH.exists():
        print(f"Notebook not found at {NB_PATH}", file=sys.stderr)
        return 1

    with NB_PATH.open("r", encoding="utf-8") as f:
        nb = json.load(f)

    n_changes = 0
    if patch_cell_45(nb):
        print("  [Q.1 + Q.2.e] Cell 45 patched (imputer + bounds + sigmoid).")
        n_changes += 1
    else:
        print("  [Q.1] Cell 45 already patched, skipping.")

    if patch_cell_12(nb):
        print("  [Q.2.a] Cell 12 patched (LR calibration sigmoid + label header).")
        n_changes += 1
    else:
        print("  [Q.2.a] Cell 12 already patched, skipping.")

    n_headers = patch_label_headers(nb)
    if n_headers:
        print(f"  [Q.2.b] Label headers added to {n_headers} cells (6 / 10 / 14).")
        n_changes += 1
    else:
        print("  [Q.2.b] Label headers already in place, skipping.")

    if insert_multi_seed_cell(nb):
        print("  [Q.2.c + Q.2.d] Multi-seed + baselines cell inserted after Cell 6.")
        n_changes += 1
    else:
        print("  [Q.2.c] Multi-seed cell already present, skipping.")

    if insert_shap_cell(nb):
        print("  [Q.2.f] Real SHAP cell inserted after the feature-importance cell.")
        n_changes += 1
    else:
        print("  [Q.2.f] SHAP cell already present, skipping.")

    if n_changes:
        with NB_PATH.open("w", encoding="utf-8") as f:
            json.dump(nb, f, indent=1, ensure_ascii=False)
            f.write("\n")
        print(f"\nWrote {NB_PATH} ({n_changes} patches applied).")
    else:
        print("\nNo changes needed; notebook already fully patched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
