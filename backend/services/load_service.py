"""Prescriptive rotation / fatigue advisor.

A transparent, explainable layer (no black box) over the point-in-time load
features from ``ml.feature_engineering.compute_load_features``. For each squad
player it derives a fatigue-risk and a freshness score, a status band, a
``rested_and_ready`` flag, and a short note, so a coach can balance the
predicted-most-likely lineup against freshness, congestion, and age.

The fatigue model is built on the acute:chronic workload ratio (Gabbett, 2016,
the training-injury-prevention paradox): a recent spike in minutes relative to
the four-week baseline, short rest, and older age all raise risk, while an
established regular who has been rested reads as ``rested_and_ready`` rather than
"dropped". Every term is a plain, inspectable rule, which is what a club's sports
science staff and a thesis examiner both want.
"""
from __future__ import annotations

from typing import Dict


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


def assess_player(rec: Dict) -> Dict:
    """Return the advisor fields for one player record (computed in place safe).

    Reads the load features already attached to ``rec`` (acwr, acute_load,
    rest_days, minutes_last_14d, season_start_rate, age_at_fixture) and returns
    ``fatigue_risk``, ``freshness``, ``load_status``, ``rested_and_ready`` and a
    human ``load_note``.
    """
    age = float(rec.get("age_at_fixture") or rec.get("age") or 0)
    acwr = float(rec.get("acwr") or 0)
    acute = float(rec.get("acute_load") or 0)
    rest_days = float(rec.get("rest_days") if rec.get("rest_days") is not None else 7)
    min14 = float(rec.get("minutes_last_14d") or 0)
    start_rate = float(rec.get("season_start_rate") or 0)

    # Fatigue risk (0-100), a transparent additive model
    pts = 0.0
    # Acute:chronic workload spike. The danger zone is roughly above 1.5; the
    # "sweet spot" sits around 0.8-1.3 (Gabbett 2016).
    if acwr >= 1.5:
        pts += 40
    elif acwr >= 1.3:
        pts += 22
    elif acwr >= 1.1:
        pts += 8
    # Recent volume: minutes in the last 14 days (about four to five matches).
    pts += min(32.0, (min14 / 450.0) * 32.0)
    # Short rest since the last appearance.
    if rest_days <= 2:
        pts += 18
    elif rest_days <= 3:
        pts += 10
    elif rest_days <= 4:
        pts += 4
    # Age amplifies fatigue: older players recover more slowly, so the same load
    # carries more risk (35yo -> x1.20, 38yo -> x1.32).
    age_factor = 1.0 + max(0.0, age - 30.0) * 0.04
    fatigue_risk = round(_clamp(pts * age_factor), 1)
    freshness = round(_clamp(100.0 - fatigue_risk), 1)

    if fatigue_risk >= 60:
        status = "at_risk"
    elif fatigue_risk <= 25:
        status = "fresh"
    else:
        status = "ok"

    # A season regular who has been rested recently: an established starter
    # (high season start-rate) on low recent load and adequate rest. This is the
    # "do not write him off" signal for a rotated veteran.
    rested_and_ready = bool(
        start_rate >= 0.35 and (rest_days >= 5 or min14 <= 120) and acute <= 90
    )

    if rested_and_ready:
        note = "Regular, rested and ready"
    elif status == "at_risk":
        note = "Heavy recent load, rotation candidate"
    elif status == "fresh":
        note = "Fresh"
    else:
        note = "Match ready"

    return {
        "fatigue_risk": fatigue_risk,
        "freshness": freshness,
        "load_status": status,
        "rested_and_ready": rested_and_ready,
        "load_note": note,
    }
