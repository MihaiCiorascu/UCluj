from __future__ import annotations

import logging
from typing import Any

import numpy as np
import pandas as pd
from catboost import Pool

logger = logging.getLogger(__name__)


class ModelService:
    """Wraps the CatBoost bundle loaded from the notebook's joblib artifact."""

    def __init__(self, bundle: dict[str, Any] | None):
        if bundle is None:
            self._ready = False
            self._model = None
            self._raw_model = None
            self._imputer = None
            self._feature_cols: list[str] = []
            self._bounds: dict = {}
            self._medians: dict = {}
            return

        self._ready = True
        self._model = bundle["model"]
        self._raw_model = bundle.get("raw_model")
        self._imputer = bundle.get("imputer")
        self._feature_cols = list(bundle["feature_cols"])
        self._bounds = bundle.get("bounds", {})
        self._medians = bundle.get("medians", {})

    @property
    def is_ready(self) -> bool:
        return self._ready

    @property
    def feature_cols(self) -> list[str]:
        return self._feature_cols

    @property
    def bounds(self) -> dict:
        return self._bounds

    @property
    def medians(self) -> dict:
        return self._medians

    def predict_proba(self, features: pd.DataFrame) -> float:
        """Return P(Home Win) for a single-row feature DataFrame.

        The model is a binary home-win classifier, so the returned value is
        the probability that whichever team occupies the HOME slot of the
        feature vector wins. ``FeatureService.win_prob`` exploits this by
        building the vector with a chosen subject team in the home slot, which
        turns a single binary call into a direct P(subject wins). Two such
        calls (one per team) give a per-team split without a 3-way classifier.
        """
        if not self._ready:
            raise RuntimeError("Model bundle not loaded")

        X = features[self._feature_cols].copy()
        if self._imputer is not None:
            X = pd.DataFrame(
                self._imputer.transform(X),
                columns=self._feature_cols,
            )
        proba = self._model.predict_proba(X)
        return float(proba[0, 1])

    def predict_proba_batch(self, features: pd.DataFrame) -> np.ndarray:
        """Return P(Home Win) for multiple rows. Used by the optimizer."""
        if not self._ready:
            raise RuntimeError("Model bundle not loaded")

        X = features[self._feature_cols].copy()
        if self._imputer is not None:
            X = pd.DataFrame(
                self._imputer.transform(X),
                columns=self._feature_cols,
            )
        return self._model.predict_proba(X)[:, 1]

    def feature_importances(self) -> dict[str, float]:
        """Return native CatBoost feature importances as {name: importance}."""
        if not self._ready:
            return {}

        model = self._raw_model or self._model
        if hasattr(model, "feature_importances_"):
            imp = model.feature_importances_
        elif hasattr(model, "calibrated_classifiers_"):
            all_imp = []
            for clf in model.calibrated_classifiers_:
                base = getattr(clf, "estimator", None) or getattr(clf, "base_estimator", None)
                if base is not None and hasattr(base, "feature_importances_"):
                    all_imp.append(base.feature_importances_)
            imp = np.mean(all_imp, axis=0) if all_imp else np.zeros(len(self._feature_cols))
        else:
            return {}

        return dict(zip(self._feature_cols, map(float, imp)))

    def local_contributions(self, features: pd.DataFrame) -> dict[str, float]:
        """Return per-row signed SHAP contributions for the first row."""
        if not self._ready:
            return {}

        X = features[self._feature_cols].copy()
        if self._imputer is not None:
            X = pd.DataFrame(
                self._imputer.transform(X),
                columns=self._feature_cols,
            )

        model = self._raw_model or self._model
        if not hasattr(model, "get_feature_importance"):
            return {}

        try:
            shap = model.get_feature_importance(
                Pool(X, feature_names=self._feature_cols),
                type="ShapValues",
            )
            if shap is None or len(shap) == 0:
                return {}
            row = np.array(shap[0], dtype=float)
            if row.size == len(self._feature_cols) + 1:
                row = row[:-1]  # drop expected value term
            if row.size != len(self._feature_cols):
                return {}
            return dict(zip(self._feature_cols, map(float, row)))
        except Exception:
            logger.exception("Failed to compute local SHAP contributions")
            return {}
