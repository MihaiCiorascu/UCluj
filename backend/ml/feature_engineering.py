"""
Feature Engineering for Football Starting XI Predictor
Transforms raw player stats + player profile data into ML-ready features.
"""

import json
import numpy as np
import pandas as pd
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from typing import List, Dict, Optional


# ─── Stat weights by position group ───────────────────────────────────────────
POSITION_STAT_WEIGHTS = {
    "GK": {
        "gkSaves": 3.0, "gkCleanSheets": 3.0, "gkShotsAgainst": -1.0,
        "gkSuccessfulExits": 2.0, "gkAerialDuelsWon": 2.0,
        "successfulPasses": 1.0, "losses": -1.0,
    },
    "DEF": {
        "interceptions": 2.5, "defensiveDuelsWon": 2.5, "aerialDuelsWon": 2.0,
        "clearances": 2.0, "successfulDefensiveAction": 2.0,
        "successfulPasses": 1.5, "losses": -1.5, "fouls": -1.0,
        "yellowCards": -2.0, "redCards": -5.0,
        "recoveries": 1.5, "shotsBlocked": 1.5,
    },
    "MID": {
        "successfulPasses": 2.0, "keyPasses": 3.0, "assists": 3.0,
        "goals": 3.0, "successfulDribbles": 2.0, "interceptions": 1.5,
        "progressivePasses": 2.0, "recoveries": 1.5,
        "losses": -1.5, "fouls": -0.5, "yellowCards": -2.0,
        "passesToFinalThird": 2.0, "xgAssist": 2.5,
    },
    "FWD": {
        "goals": 4.0, "shots": 1.5, "shotsOnTarget": 2.5, "xgShot": 3.0,
        "assists": 2.5, "successfulDribbles": 2.0, "keyPasses": 2.0,
        "touchInBox": 2.0, "offsides": -0.5, "losses": -1.0,
    },
}

ROLE_TO_GROUP = {
    "Goalkeeper": "GK", "GK": "GK",
    "Defender": "DEF", "Centre Back": "DEF", "Left Back": "DEF",
    "Right Back": "DEF", "Wing Back": "DEF",
    "Midfielder": "MID", "Central Midfielder": "MID", "Defensive Midfielder": "MID",
    "Attacking Midfielder": "MID", "Wide Midfielder": "MID",
    "Forward": "FWD", "Striker": "FWD", "Left Winger": "FWD", "Right Winger": "FWD",
}

# Improvement 5: half-life for historical performance age-decay (days)
_PERF_HALF_LIFE_DAYS = 90

# Improvement 1: exponential decay factor for recent-form window
_FORM_WINDOW   = 5    # look at last 5 matches
_FORM_DECAY    = 0.70 # each older match weighted 30 % less than the next newer one

# Improvement 2: Bayesian shrinkage prior strength
_SHRINK_K = 5  # equivalent to 5 "ghost" matches at the role mean


def role_to_group(role_name: str) -> str:
    for key, group in ROLE_TO_GROUP.items():
        if key.lower() in role_name.lower():
            return group
    return "MID"  # default fallback


def compute_performance_score(stats: Dict, role_group: str) -> float:
    """Compute a weighted performance score for a player given their stats and role."""
    weights = POSITION_STAT_WEIGHTS.get(role_group, POSITION_STAT_WEIGHTS["MID"])
    total = stats.get("minutesOnField", 0)
    if total == 0:
        return 0.0
    per90 = 90.0 / total
    score = 0.0
    for stat, w in weights.items():
        val = stats.get(stat, 0) or 0
        score += val * per90 * w
    return round(score, 4)


def _match_age_factor(match_stat: Dict, today: date) -> float:
    """Improvement 5: exponential decay so older matches count less."""
    date_str = match_stat.get("matchDate", "") or match_stat.get("match_date", "")
    try:
        md = datetime.strptime(date_str[:10], "%Y-%m-%d").date()
        age_days = max((today - md).days, 0)
        return 0.5 ** (age_days / _PERF_HALF_LIFE_DAYS)
    except Exception:
        return 1.0  # unknown date → no penalty


def compute_efficiency_metrics(stats: Dict) -> Dict:
    """Compute % metrics that capture efficiency regardless of volume."""
    def safe_pct(num, denom):
        return round(num / denom * 100, 2) if denom else 0.0

    return {
        "pass_accuracy":      safe_pct(stats.get("successfulPasses", 0), stats.get("passes", 0)),
        "duel_win_rate":      safe_pct(stats.get("duelsWon", 0), stats.get("duels", 0)),
        "dribble_success":    safe_pct(stats.get("successfulDribbles", 0), stats.get("dribbles", 0)),
        "shot_accuracy":      safe_pct(stats.get("shotsOnTarget", 0), stats.get("shots", 0)),
        "aerial_win_rate":    safe_pct(stats.get("aerialDuelsWon", 0), stats.get("aerialDuels", 0)),
        "cross_accuracy":     safe_pct(stats.get("successfulCrosses", 0), stats.get("crosses", 0)),
        "def_action_success": safe_pct(stats.get("successfulDefensiveAction", 0), stats.get("defensiveActions", 0)),
    }


def build_player_feature_vector(
    player_profile: Dict,
    match_stats_list: List[Dict],
    opponent_team_id: Optional[int] = None,
) -> Optional[Dict]:
    """
    Merge player profile + aggregated match stats into a flat feature dict.
    """
    valid_stats = [s for s in match_stats_list if s.get("minutesOnField", 0) > 0]
    if not valid_stats:
        return None

    # ── Positions played ─────────────────────────────────────────────────────
    all_positions: set = set()
    position_names: list = []
    for s in match_stats_list:
        for pos in s.get("positions", []):
            code = pos.get("position", {}).get("code", "")
            name = pos.get("position", {}).get("name", "")
            if code:
                all_positions.add(code)
            if name:
                position_names.append(name)

    role_name = player_profile.get("role", {}).get("name", "Midfielder")
    if role_name == "Midfielder" and position_names:
        role_name = Counter(position_names).most_common(1)[0][0]
    role_group = role_to_group(role_name)

    # ── Improvement 5: age-weighted aggregate stats ───────────────────────────
    today = date.today()
    age_weights = [_match_age_factor(s, today) for s in valid_stats]
    total_age_weight = sum(age_weights) or 1.0

    agg: Dict = {}
    # Sum stats with age weighting (for performance score)
    all_keys = valid_stats[0].keys()
    for k in all_keys:
        try:
            agg[k] = sum(
                (s.get(k, 0) or 0) * w
                for s, w in zip(valid_stats, age_weights)
                if isinstance(s.get(k, 0), (int, float))
            )
        except TypeError:
            agg[k] = 0

    minutes_total = int(sum(s.get("minutesOnField", 0) or 0 for s in valid_stats)) or 1

    # Per-90 uses raw (unweighted) totals for counting stats
    raw_agg: Dict = {}
    for k in all_keys:
        try:
            raw_agg[k] = sum(
                (s.get(k, 0) or 0)
                for s in valid_stats
                if isinstance(s.get(k, 0), (int, float))
            )
        except TypeError:
            raw_agg[k] = 0

    per90 = {k: round(v / minutes_total * 90, 4) for k, v in raw_agg.items()
             if isinstance(v, (int, float))}

    # ── Improvement 5: age-weighted performance score ────────────────────────
    weighted_scores = [
        compute_performance_score(s, role_group) * w
        for s, w in zip(valid_stats, age_weights)
    ]
    perf_score = round(sum(weighted_scores) / total_age_weight, 4)

    # ── Improvement 1: exponential-decay recent form ─────────────────────────
    recent = valid_stats[-_FORM_WINDOW:]
    recent_raw_scores = [compute_performance_score(s, role_group) for s in recent]
    if recent_raw_scores:
        # most-recent match gets weight 1.0, each older step decays by _FORM_DECAY
        form_weights = [_FORM_DECAY ** (len(recent_raw_scores) - 1 - i)
                        for i in range(len(recent_raw_scores))]
        recent_score = float(np.average(recent_raw_scores, weights=form_weights))
        # form_trend: positive = improving, negative = declining
        form_trend = recent_raw_scores[-1] - float(np.mean(recent_raw_scores))
    else:
        recent_score = 0.0
        form_trend = 0.0

    # ── Efficiency metrics (use raw cumulative totals for accuracy) ───────────
    efficiency = compute_efficiency_metrics(raw_agg)

    # ── Improvement 6: yellow-card accumulation / suspension flag ────────────
    cumulative_yellows = int(raw_agg.get("yellowCards", 0))
    yellow_card_risk   = 1 if cumulative_yellows >= 4 else 0  # 1 more = ban

    # ── Age ──────────────────────────────────────────────────────────────────
    birth = player_profile.get("birthDate", "")
    age = 0.0
    if birth:
        try:
            bd = datetime.strptime(birth, "%Y-%m-%d").date()
            age = round((date.today() - bd).days / 365.25, 1)
        except Exception:
            pass

    count = len(valid_stats)

    feature = {
        "playerId":            player_profile.get("wyId"),
        "shortName":           player_profile.get("shortName", ""),
        "role":                role_name,
        "role_group":          role_group,
        "age":                 age,
        "matches_played":      count,
        "total_minutes":       minutes_total,
        "performance_score":   perf_score,
        "recent_form_score":   round(recent_score, 4),
        "form_trend":          round(form_trend, 4),
        "cumulative_yellows":  cumulative_yellows,
        "yellow_card_risk":    yellow_card_risk,
        # Improvement 2: confidence field (fed into Bayesian shrinkage later)
        "confidence":          round(min(count / 10.0, 1.0), 3),
        **{f"per90_{k}": v for k, v in per90.items()},
        **efficiency,
        "positions_played":    ",".join(sorted(all_positions)),
    }
    return feature


def load_match_stats_json(filepath: str) -> List[Dict]:
    """Load a match stats JSON file and return the players list."""
    with open(filepath) as f:
        data = json.load(f)
    return data.get("players", [])


def build_dataset_from_files(
    match_stat_files: List[str],
    player_profiles: Dict[int, Dict],
    opponent_team_id: Optional[int] = None,
) -> pd.DataFrame:
    """
    Build full feature DataFrame from match stat files + player profiles.
    Applies Bayesian shrinkage (Improvement 2) after building all rows.
    """
    player_stats_map: Dict[int, List[Dict]] = {}

    for filepath in match_stat_files:
        match_players = load_match_stats_json(filepath)
        for entry in match_players:
            pid = entry.get("playerId")
            if pid is None:
                continue
            if pid not in player_stats_map:
                player_stats_map[pid] = []
            combined = dict(entry.get("total", {}))
            combined["positions"] = entry.get("positions", [])
            combined["matchId"]   = entry.get("matchId")
            combined["matchDate"] = entry.get("matchDate", "")
            player_stats_map[pid].append(combined)

    rows = []
    for pid, stats_list in player_stats_map.items():
        profile = player_profiles.get(pid, {"wyId": pid, "role": {"name": "Midfielder"}})
        row = build_player_feature_vector(profile, stats_list, opponent_team_id)
        if row:
            rows.append(row)

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)

    # ── Improvement 2: Bayesian shrinkage toward role-group mean ─────────────
    for col in ("performance_score", "recent_form_score"):
        if col not in df.columns:
            continue
        group_means = df.groupby("role_group")[col].mean()
        for role, mu in group_means.items():
            mask = df["role_group"] == role
            n = df.loc[mask, "matches_played"].astype(float)
            # shrink: weighted average between player value and role mean
            df.loc[mask, col] = (n * df.loc[mask, col] + _SHRINK_K * mu) / (n + _SHRINK_K)

    return df
