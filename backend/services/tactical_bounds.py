from __future__ import annotations

import logging
from functools import lru_cache

import pandas as pd

from app.config import settings

logger = logging.getLogger(__name__)

# Hardcoded fallbacks. These are the magic ratios the optimiser used before the
# data-derived bands were introduced; they are retained only so the optimiser
# never breaks if ``All_Data.csv`` is missing or the ratios cannot be computed.
_FALLBACK_RATIO_BOUNDS: dict[str, dict[str, float]] = {
    "sot_per_shots": {"low": 0.20, "high": 0.70},
    "corners_per_shots": {"low": 0.15, "high": 0.80},
}

# Empirical band: 2.5th-97.5th percentile, i.e. the central 95% of observed
# Romanian Superliga rolling-5 ratios. Tighter than the old hand-picked
# extremes, so the optimiser stays on the realistic football manifold instead
# of inflating uplift at implausible shot-conversion rates.
_LOW_Q = 0.025
_HIGH_Q = 0.975


@lru_cache(maxsize=1)
def get_ratio_bounds() -> dict[str, dict[str, float]]:
    """Data-driven coupling bounds for the controllable tactical levers.

    Reads ``All_Data.csv`` (same path the data layer uses,
    ``settings.resolved_data_path``) once at startup, derives the empirical
    distribution of two football-domain ratios over the rolling-5 features,

      * ``sot_per_shots``     = ``Home_SoT_5 / Home_Shots_5``
      * ``corners_per_shots`` = ``Home_Corners_5 / Home_Shots_5``

    (only where ``Home_Shots_5 > 0``), and returns the 2.5th/97.5th percentile
    of each as ``{"low": ..., "high": ...}``. Cached for the process lifetime,
    so the CSV is parsed once. Falls back to the historical hardcoded ratios if
    the CSV is unavailable or a ratio cannot be computed, so the optimiser never
    breaks.
    """
    path = settings.resolved_data_path
    if not path.exists():
        logger.warning(
            "All_Data.csv not found at %s; using fallback ratio bounds", path
        )
        return _fallback_copy()

    try:
        df = pd.read_csv(path, usecols=["Home_Shots_5", "Home_SoT_5", "Home_Corners_5"])
    except Exception as exc:  # noqa: BLE001 -- never break the optimiser on a bad CSV
        logger.warning(
            "Failed to read ratio columns from %s (%s: %s); using fallback ratio bounds",
            path,
            type(exc).__name__,
            exc,
        )
        return _fallback_copy()

    shots = pd.to_numeric(df["Home_Shots_5"], errors="coerce")
    sot = pd.to_numeric(df["Home_SoT_5"], errors="coerce")
    corners = pd.to_numeric(df["Home_Corners_5"], errors="coerce")

    valid = shots > 0
    bounds = _fallback_copy()

    sot_ratio = (sot[valid] / shots[valid]).dropna()
    if not sot_ratio.empty:
        bounds["sot_per_shots"] = {
            "low": float(sot_ratio.quantile(_LOW_Q)),
            "high": float(sot_ratio.quantile(_HIGH_Q)),
        }

    corners_ratio = (corners[valid] / shots[valid]).dropna()
    if not corners_ratio.empty:
        bounds["corners_per_shots"] = {
            "low": float(corners_ratio.quantile(_LOW_Q)),
            "high": float(corners_ratio.quantile(_HIGH_Q)),
        }

    logger.info(
        "Tactical ratio bounds (P%.1f-P%.1f): SoT/Shots=[%.3f, %.3f], Corners/Shots=[%.3f, %.3f]",
        _LOW_Q * 100,
        _HIGH_Q * 100,
        bounds["sot_per_shots"]["low"],
        bounds["sot_per_shots"]["high"],
        bounds["corners_per_shots"]["low"],
        bounds["corners_per_shots"]["high"],
    )
    return bounds


def _fallback_copy() -> dict[str, dict[str, float]]:
    return {k: dict(v) for k, v in _FALLBACK_RATIO_BOUNDS.items()}
