"""Extract the post-Iter-Q metrics from data/TheNotebook.executed.ipynb so
Chunk D can reconcile Table 3.2 / 3.3 against the freshly-computed
numbers without re-running the notebook.

Prints a compact text report:

    * Multi-seed mu +/- sigma table (CatBoost / RF / XGB / MLP / LR / NB / SVC)
    * Holdout base rate (AlwaysHomeWin)
    * Elo-only LR holdout accuracy
    * Calibrated CatBoost + Calibrated LR Brier + ECE (post sigmoid+tscv)
    * Rolling-origin CV mean accuracy / log-loss / Brier
    * Top-15 SHAP features by mean(|value|)
    * Deployment-bundle provenance keys (imputer_fit_scope, bounds_source,
      calibration_method, schema_version)

Run from the worktree root:
    python -X utf8 scripts/harvest_iter_q_metrics.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NB_PATH = ROOT / "data" / "TheNotebook.executed.ipynb"


def _cell_text_outputs(cell: dict) -> str:
    """Concatenate every text/plain or text/stream output of a code cell."""
    chunks: list[str] = []
    for o in cell.get("outputs", []):
        if o.get("output_type") == "stream":
            chunks.append("".join(o.get("text", [])))
        elif o.get("output_type") in ("execute_result", "display_data"):
            data = o.get("data", {})
            text = data.get("text/plain")
            if isinstance(text, list):
                chunks.append("".join(text))
            elif isinstance(text, str):
                chunks.append(text)
    return "\n".join(chunks)


def _find_cell(nb: dict, src_substr: str) -> dict | None:
    for c in nb.get("cells", []):
        if c.get("cell_type") != "code":
            continue
        src = "".join(c.get("source", []))
        if src_substr in src:
            return c
    return None


def main() -> int:
    if not NB_PATH.exists():
        print(f"ERROR: {NB_PATH} does not exist. Run the notebook first:")
        print('       python -X utf8 -m jupyter nbconvert --to notebook \\')
        print('         --execute data/TheNotebook.ipynb \\')
        print('         --output TheNotebook.executed.ipynb')
        return 1

    nb = json.loads(NB_PATH.read_text(encoding="utf-8"))
    print(f"Loaded {NB_PATH.relative_to(ROOT)} ({len(nb['cells'])} cells)\n")

    # --- Multi-seed cell (Q.2.c + Q.2.d) ---
    multi_cell = _find_cell(nb, "Multi-seed model comparison + trivial baselines")
    print("=" * 70)
    print("MULTI-SEED COMPARISON + BASELINES  (Q.2.c + Q.2.d)")
    print("=" * 70)
    if multi_cell is not None:
        print(_cell_text_outputs(multi_cell).strip() or "(no output)")
    else:
        print("(multi-seed cell not found)")
    print()

    # --- Calibration cell (Q.2.a) ---
    cal_cell = _find_cell(nb, "CHRONOLOGICAL-HOLDOUT calibration")
    print("=" * 70)
    print("CALIBRATION  (Cell 13 — Q.2.a, Platt sigmoid + tscv for BOTH)")
    print("=" * 70)
    if cal_cell is not None:
        # Strip any matplotlib display garbage (only keep print() output)
        out = _cell_text_outputs(cal_cell)
        out = re.sub(r"<Figure size [^>]+>", "", out)
        print(out.strip() or "(no output)")
    else:
        print("(calibration cell not found)")
    print()

    # --- Rolling-origin CV cell (Cell 15) ---
    cv_cell = _find_cell(nb, "ROLLING-ORIGIN CV")
    print("=" * 70)
    print("ROLLING-ORIGIN CV  (Cell 15 — Q.2.b)")
    print("=" * 70)
    if cv_cell is not None:
        print(_cell_text_outputs(cv_cell).strip() or "(no output)")
    else:
        print("(rolling-origin CV cell not found)")
    print()

    # --- SHAP cell (Q.2.f) ---
    shap_cell = _find_cell(nb, "Real SHAP attributions via shap.TreeExplainer")
    print("=" * 70)
    print("SHAP (Q.2.f) — top 15 features by mean(|SHAP value|)")
    print("=" * 70)
    if shap_cell is not None:
        out = _cell_text_outputs(shap_cell)
        out = re.sub(r"<Figure size [^>]+>", "", out)
        print(out.strip() or "(no output)")
    else:
        print("(SHAP cell not found)")
    print()

    # --- Deployment cell (Q.1 + Q.2.e) ---
    dep_cell = _find_cell(nb, "Deployment bundle — fitted with TRAIN-FOLD-ONLY")
    print("=" * 70)
    print("DEPLOYMENT BUNDLE PROVENANCE  (Q.1 + Q.2.e)")
    print("=" * 70)
    if dep_cell is not None:
        print(_cell_text_outputs(dep_cell).strip() or "(no output)")
        # Try to also dump the bundle's provenance keys from disk if it
        # was written during execution.
        bundle = ROOT / "data" / "artifacts" / "umbraro_catboost_bundle.joblib"
        if bundle.exists():
            try:
                import joblib
                art = joblib.load(bundle)
                prov = {
                    "schema_version": art.get("schema_version"),
                    "preprocessing_provenance": art.get("preprocessing_provenance"),
                    "optimizer_config.bounds_source": art.get("optimizer_config", {}).get("bounds_source"),
                    "bounds_for_app keys": list(art.get("bounds", {}).keys()),
                    "medians_for_app keys": list(art.get("medians", {}).keys()),
                }
                print()
                print("Bundle keys (loaded from disk):")
                for k, v in prov.items():
                    print(f"  {k}: {v}")
            except Exception as e:
                print(f"(bundle load skipped: {e})")
        else:
            print(f"(no bundle artefact at {bundle.relative_to(ROOT)})")
    else:
        print("(deployment cell not found)")
    print()

    # --- Other notable cells: Cell 10 (confusion matrix / ROC-AUC) ---
    conf_cell = _find_cell(nb, "CHRONOLOGICAL HOLDOUT — confusion matrix")
    print("=" * 70)
    print("CONFUSION MATRIX + ROC-AUC + LOG-LOSS  (Cell 11)")
    print("=" * 70)
    if conf_cell is not None:
        out = _cell_text_outputs(conf_cell)
        out = re.sub(r"<Figure size [^>]+>", "", out)
        print(out.strip() or "(no output)")
    print()

    # --- Cell 6 single-seed comparison (for backward comparison) ---
    cell6 = _find_cell(nb, "CHRONOLOGICAL HOLDOUT (single chronological cut at split_date)")
    print("=" * 70)
    print("CELL 6 — SINGLE-SEED REFERENCE NUMBERS")
    print("=" * 70)
    if cell6 is not None:
        out = _cell_text_outputs(cell6)
        out = re.sub(r"<Figure size [^>]+>", "", out)
        print(out.strip() or "(no output)")
    print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
