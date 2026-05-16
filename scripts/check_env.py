"""Check the notebook's runtime dependencies are installed."""
import importlib

MODS = [
    "pandas", "numpy", "sklearn", "xgboost", "lightgbm",
    "catboost", "matplotlib", "seaborn", "shap",
    "jupyter", "nbformat", "nbconvert",
]
for m in MODS:
    try:
        v = importlib.import_module(m).__version__
        print(f"  OK   {m:12s} {v}")
    except Exception as e:
        print(f"  MISS {m:12s} {e}")
