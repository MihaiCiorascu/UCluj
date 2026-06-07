from __future__ import annotations

from typing import Mapping

import numpy as np
import pandas as pd

from ml.feature_config import OPTIMIZABLE_FEATURES

# Column names of the four controllable levers, pinned here so the sampler does
# not depend on the ordering of OPTIMIZABLE_FEATURES.
_POSS = "Home_Poss_5"
_SHOTS = "Home_Shots_5"
_SOT = "Home_SoT_5"
_CORNERS = "Home_Corners_5"


def _lever_range(
    base_val: float,
    marginal: Mapping[str, float] | None,
    trust_frac: float,
) -> tuple[float, float]:
    """Intersect a lever's data-driven percentile band with its trust region.

    The trust region is ``[base*(1-trust_frac), base*(1+trust_frac)]`` (so a
    recommendation never moves more than +/-trust_frac off the team's current
    form). The marginal band is the per-feature training percentile bound from
    the joblib bundle. The feasible range is their intersection; when the bundle
    has no bound for this feature we fall back to the trust region alone.
    """
    trust_lo = base_val * (1.0 - trust_frac)
    trust_hi = base_val * (1.0 + trust_frac)
    if base_val < 0:  # defensive: a negative baseline would invert the trust box
        trust_lo, trust_hi = trust_hi, trust_lo
    if marginal:
        lo = max(float(marginal.get("low", trust_lo)), trust_lo)
        hi = min(float(marginal.get("high", trust_hi)), trust_hi)
    else:
        lo, hi = trust_lo, trust_hi
    return lo, hi


def sample_feasible(
    base_row: Mapping[str, float],
    marginal_bounds: Mapping[str, Mapping[str, float]],
    ratio_bounds: Mapping[str, Mapping[str, float]],
    trust_frac: float,
    n: int,
    rng: np.random.Generator,
) -> pd.DataFrame:
    """Draw ``n`` feasible tactical-lever candidates by conditional sampling.

    Returns a ``pd.DataFrame`` with one column per ``OPTIMIZABLE_FEATURES``
    lever (Possession, Shots, SoT, Corners), where *every* row already
    satisfies both the trust region and the empirical SoT/Shots and
    Corners/Shots coupling bounds. The sampling is sequential rather than
    rejection-based, so no draw is wasted:

      1. Possession and Shots are drawn uniformly in the intersection of their
         percentile band and trust region.
      2. SoT is drawn uniformly in
         ``[max(sot_lo, r_sot_lo * shots), min(sot_hi, r_sot_hi * shots)]``.
      3. Corners likewise with the Corners/Shots ratio band.

    Degenerate ranges (high <= low) keep the baseline value for that lever on
    the affected rows, mirroring the optimiser's old "continue" behaviour
    without discarding the whole candidate. Shared by both the optimiser and the
    prescription services so the two never diverge.
    """
    n = int(n)

    base_poss = float(base_row.get(_POSS, 0.0) or 0.0)
    base_shots = float(base_row.get(_SHOTS, 0.0) or 0.0)
    base_sot = float(base_row.get(_SOT, 0.0) or 0.0)
    base_corners = float(base_row.get(_CORNERS, 0.0) or 0.0)

    # 1. Independent levers: Possession and Shots.
    poss_lo, poss_hi = _lever_range(base_poss, marginal_bounds.get(_POSS), trust_frac)
    poss = (
        rng.uniform(poss_lo, poss_hi, size=n)
        if poss_hi > poss_lo
        else np.full(n, base_poss, dtype=float)
    )

    shots_lo, shots_hi = _lever_range(base_shots, marginal_bounds.get(_SHOTS), trust_frac)
    shots = (
        rng.uniform(shots_lo, shots_hi, size=n)
        if shots_hi > shots_lo
        else np.full(n, base_shots, dtype=float)
    )

    # 2. SoT, coupled to per-row shots through the empirical SoT/Shots band and
    #    its own marginal+trust range.
    sot_marg_lo, sot_marg_hi = _lever_range(base_sot, marginal_bounds.get(_SOT), trust_frac)
    r_sot = ratio_bounds.get("sot_per_shots", {})
    r_sot_lo = float(r_sot.get("low", 0.0))
    r_sot_hi = float(r_sot.get("high", 1.0))
    sot_lo = np.maximum(sot_marg_lo, r_sot_lo * shots)
    sot_hi = np.minimum(sot_marg_hi, r_sot_hi * shots)
    sot = _conditional_draw(sot_lo, sot_hi, base_sot, rng)

    # 3. Corners, coupled to per-row shots through the empirical Corners/Shots band.
    corn_marg_lo, corn_marg_hi = _lever_range(
        base_corners, marginal_bounds.get(_CORNERS), trust_frac
    )
    r_corn = ratio_bounds.get("corners_per_shots", {})
    r_corn_lo = float(r_corn.get("low", 0.0))
    r_corn_hi = float(r_corn.get("high", 1.0))
    corn_lo = np.maximum(corn_marg_lo, r_corn_lo * shots)
    corn_hi = np.minimum(corn_marg_hi, r_corn_hi * shots)
    corners = _conditional_draw(corn_lo, corn_hi, base_corners, rng)

    return pd.DataFrame(
        {
            _POSS: poss,
            _SHOTS: shots,
            _SOT: sot,
            _CORNERS: corners,
        },
        columns=OPTIMIZABLE_FEATURES,
    )


def _conditional_draw(
    lo: np.ndarray,
    hi: np.ndarray,
    base_val: float,
    rng: np.random.Generator,
) -> np.ndarray:
    """Uniform draw inside per-row ``[lo, hi]``, baseline where it degenerates.

    Rows whose feasible range has collapsed (``hi <= lo``) keep ``base_val``
    rather than being rejected, so the candidate row remains usable for the
    other levers. The uniform draw is computed for all rows then overwritten on
    the degenerate ones, which keeps the operation vectorised.
    """
    lo = np.asarray(lo, dtype=float)
    hi = np.asarray(hi, dtype=float)
    valid = hi > lo
    # Draw with a safe span on degenerate rows (lo == hi) to avoid a backend
    # error, then overwrite those rows with the baseline value below.
    safe_hi = np.where(valid, hi, lo + 1.0)
    out = rng.uniform(lo, safe_hi)
    out[~valid] = base_val
    return out
