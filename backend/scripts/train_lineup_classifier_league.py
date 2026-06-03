"""
League-wide supervised lineup classifier (Iteration L.3b + L.4).

Generalises the U Cluj-only ``train_lineup_classifier.py`` to all
sixteen Romanian Superliga teams. Key additions over the single-team
version:

1. **Pooled training rows** — every team's (player, fixture) pairs are
   stacked into a single training matrix. Sample size grows from
   ~945 rows (U Cluj only) to roughly 16 × 35 × 27 ≈ 15,000 rows.
2. **Team one-hot** — a 16-column block encodes which team owns each
   row, letting the classifier learn per-team selection idiosyncrasies
   without losing the cross-team signal.
3. **Opponent-XI cascade features** — for each (player, fixture) row,
   nine columns summarise the *actual* opposing team's starting XI in
   that fixture (sum of per-90 goals, per-90 shots on target, per-90
   key passes, per-90 def actions, per-90 aerial duels won, plus
   GK/DEF/MID/FWD counts). At inference time these are filled from the
   *predicted* opponent XI in a two-stage cascade (predict opponent XI
   first, then the home XI conditioned on it).
4. **Rolling-origin CV** — for each held-out (team, fixture_idx ≥
   I_MIN) cell, train on every cell strictly earlier in calendar order
   *across all teams* and score the held-out cell's candidates.

Persisted as ``backend/ml/xi_lineup_model_league.joblib``. The
single-team U Cluj bundle ``xi_lineup_model.joblib`` is kept on disk
unchanged for the §3.6.4 ablation table.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import joblib
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

from ml.feature_engineering import (  # type: ignore  # noqa: E402
    build_dataset_from_files,
    build_player_feature_vector,
    compute_availability_features,
    compute_load_features,
    get_team_match_chronology,
    get_team_squad_from_matches,
    load_match_stats_json,
)
from ml.match_dates import date_for  # type: ignore  # noqa: E402
from ml.opponent_profile import build_opponent_profile_table  # type: ignore  # noqa: E402
from ml.pipeline import load_player_profiles  # type: ignore  # noqa: E402
from sportradar.team_registry import (  # type: ignore  # noqa: E402
    SUPERLIGA_TEAMS,
    TeamRef,
    files_for_team,
)

DRIVE = ROOT / "ml" / "data" / "drive_cache"
LINEUP_HISTORY = ROOT / "ml" / "data" / "lineup_history_league.json"
OUT_BUNDLE = ROOT / "ml" / "xi_lineup_model_league.joblib"
ALL_DATA_CSV = ROOT.parent / "data" / "All_Data.csv"

I_MIN = 8  # warm-up fixtures before the first rolling-origin prediction per team.

STATIC_PLAYER_COLS = [
    "performance_score", "recent_form_score",
    "pass_accuracy", "duel_win_rate", "def_action_success",
    "shot_accuracy", "dribble_success",
    "total_minutes", "matches_played",
]

# Point-in-time load / fatigue / age block (leakage-free retrain, Iteration L.5).
# Added to each (player, fixture) row alongside the now point-in-time static
# columns; the feature_cols auto-detector then picks them up. They restore the
# availability / regularity signal that the leakage-free static columns no
# longer encode (the full-season statics previously leaked it).
LOAD_FEATURE_COLS = [
    "age_at_fixture", "season_start_rate", "rest_days", "minutes_last_14d",
    "matches_last_10d", "acute_load", "chronic_load", "acwr", "minutes_trend",
]

FINE_GROUPS = ["GK", "CB", "FB", "WB", "DM", "CM", "AM", "W", "WF", "ST"]

# Per-90 KPI columns used to build the opponent-XI cascade features
# (summed across the 11 actual or predicted opponent starters).
OPP_XI_SUM_COLS = [
    "per90_goals", "per90_shotsOnTarget", "per90_keyPasses",
    "per90_successfulDefensiveAction", "per90_aerialDuelsWon",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _per_match_blocks(match_stat_files: List[str]) -> Dict[int, List[dict]]:
    """playerId -> list of {matchId, seasonId, roundId, total} blocks."""
    out: Dict[int, List[dict]] = {}
    for fp in match_stat_files:
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
        except Exception:
            continue
        for entry in d.get("players", []) or []:
            pid = entry.get("playerId")
            if pid is None:
                continue
            out.setdefault(int(pid), []).append({
                "matchId": entry.get("matchId"),
                "seasonId": entry.get("seasonId"),
                "roundId": entry.get("roundId"),
                "total": dict(entry.get("total", {}) or {}),
                "positions": entry.get("positions", []) or [],
            })
    return out


def _build_static_df_per_team(
    teams: List[TeamRef],
    profiles: Dict[int, dict],
    match_files: List[str],
) -> Dict[str, pd.DataFrame]:
    """Build the static feature DataFrame for each home team.

    Static features (per-90 KPIs, performance_score, position group)
    depend on the team's substring for *availability* feature
    computation, even though the underlying player aggregates do not
    depend on it. We therefore build one DataFrame per team and use the
    team's substring as the cache key. Returns ``{wy_substr: df}``.
    """
    out: Dict[str, pd.DataFrame] = {}
    for t in teams:
        print(f"  building static df for {t.short} ...", flush=True)
        df = build_dataset_from_files(
            match_files, profiles,
            availability_team_substring=t.wy_substr,
        )
        out[t.wy_substr] = df
    return out


def _build_opp_xi_lookup(
    league_history: dict,
    static_by_team: Dict[str, pd.DataFrame],
) -> Dict[Tuple[int, str], Dict[str, float]]:
    """For each (matchId, team_short) return the opponent's actual-XI feature dict.

    The lookup represents: when team T plays matchId M, the opponent's
    starters are the 11 players who started M for the *other* team. We
    aggregate their per-90 KPIs and counts of position groups.
    """
    # 1. Build matchId -> {team_short: [starter playerIds]} cross-reference.
    by_match: Dict[int, Dict[str, List[int]]] = {}
    for team in league_history["teams"]:
        for fx in team["fixtures"]:
            mid = int(fx["match_id"])
            by_match.setdefault(mid, {})[team["team_short"]] = [
                int(s["playerId"]) for s in fx["starters"]
            ]

    # 2. Per-team static lookup of static features by playerId.
    static_lookup: Dict[str, pd.DataFrame] = {}
    for substr, df in static_by_team.items():
        static_lookup[substr] = df.set_index("playerId")

    # 3. For each (matchId, my_team_short), pick the opponent and aggregate.
    out: Dict[Tuple[int, str], Dict[str, float]] = {}
    for mid, team_lineups in by_match.items():
        team_shorts = list(team_lineups.keys())
        if len(team_shorts) < 2:
            continue
        for my_short in team_shorts:
            opp_shorts = [s for s in team_shorts if s != my_short]
            if not opp_shorts:
                continue
            opp_short = opp_shorts[0]
            opp_team = next(
                (t for t in SUPERLIGA_TEAMS if t.short == opp_short), None
            )
            if opp_team is None or opp_team.wy_substr not in static_lookup:
                continue
            opp_static = static_lookup[opp_team.wy_substr]
            opp_pids = team_lineups[opp_short]
            feats = _aggregate_opp_xi(opp_static, opp_pids)
            out[(mid, my_short)] = feats
    return out


def _aggregate_opp_xi(
    static_df: pd.DataFrame, pids: List[int]
) -> Dict[str, float]:
    """Aggregate a list of opponent starter playerIds into a feature dict."""
    rows = static_df.reindex(pids).dropna(how="all")
    out: Dict[str, float] = {}
    for col in OPP_XI_SUM_COLS:
        out[f"opp_xi_sum_{col}"] = float(rows[col].sum()) if col in rows.columns else 0.0
    out["opp_xi_mean_total_minutes"] = (
        float(rows["total_minutes"].mean()) if "total_minutes" in rows.columns else 0.0
    )
    # Position group counts
    for grp in ("GK", "DEF", "MID", "FWD"):
        if "role_group" in rows.columns:
            cnt = int((rows["role_group"].astype(str).str.upper() == grp).sum())
        else:
            cnt = 0
        out[f"opp_xi_count_{grp}"] = float(cnt)
    return out


def _zero_opp_xi() -> Dict[str, float]:
    out: Dict[str, float] = {}
    for col in OPP_XI_SUM_COLS:
        out[f"opp_xi_sum_{col}"] = 0.0
    out["opp_xi_mean_total_minutes"] = 0.0
    for grp in ("GK", "DEF", "MID", "FWD"):
        out[f"opp_xi_count_{grp}"] = 0.0
    return out


def _combined_blocks_by_pid(match_files: List[str]) -> Dict[int, List[dict]]:
    """playerId -> list of per-match blocks in the format
    :func:`build_player_feature_vector` consumes (mirrors the assembly inside
    :func:`build_dataset_from_files`): the ``total`` stats flattened to the top
    level, plus the nested ``total`` dict, ``matchId``, ``match_date`` (from the
    committed bridge), ``positions``, ``seasonId`` and ``roundId``."""
    out: Dict[int, List[dict]] = {}
    for fp in match_files:
        for entry in load_match_stats_json(fp):
            pid = entry.get("playerId")
            if pid is None:
                continue
            c = dict(entry.get("total", {}) or {})
            c["positions"] = entry.get("positions", [])
            c["matchId"] = entry.get("matchId")
            c["match_date"] = date_for(entry.get("matchId"))
            c["seasonId"] = entry.get("seasonId")
            c["roundId"] = entry.get("roundId")
            c["total"] = dict(entry.get("total", {}) or {})
            out.setdefault(int(pid), []).append(c)
    return out


def _build_training_rows(
    league_history: dict,
    static_by_team: Dict[str, pd.DataFrame],
    combined_by_pid: Dict[int, List[dict]],
    profiles: Dict[int, dict],
    opp_xi_lookup: Dict[Tuple[int, str], Dict[str, float]],
) -> pd.DataFrame:
    """One (player, fixture) row per squad member, every per-player feature
    computed strictly POINT-IN-TIME (leakage-free).

    All static columns, recent form, availability, the cumulative minutes, and
    the load / fatigue / age block are derived from
    :func:`build_player_feature_vector` fed ONLY the player's appearances in
    team matches *before* the fixture (``chrono_before``), as of the fixture
    date. This is the same function inference uses, so train and serve align. A
    player with no pre-fixture appearances yields no row (it cannot be scored).
    """
    rows: List[Dict] = []

    for team_blob in league_history["teams"]:
        team_short = team_blob["team_short"]
        squad_ids = set(int(p) for p in team_blob["squad_ids"])
        chrono = [int(fx["match_id"]) for fx in team_blob["fixtures"]]

        for fixture_idx, fx in enumerate(team_blob["fixtures"]):
            mid = int(fx["match_id"])
            sid = int(fx["season_id"] or 0)
            rid = int(fx["round_id"] or 0)
            before = set(chrono[:fixture_idx])
            fixture_date = date_for(mid)
            starter_pids = {int(s["playerId"]) for s in fx["starters"]}
            opp_features = opp_xi_lookup.get((mid, team_short), _zero_opp_xi())

            for pid in squad_ids:
                blocks_before = [
                    b for b in combined_by_pid.get(int(pid), [])
                    if b.get("matchId") in before
                ]
                profile = profiles.get(
                    int(pid), {"wyId": pid, "role": {"name": "Midfielder"}}
                )
                fv = build_player_feature_vector(
                    profile, blocks_before, None,
                    team_chronology=list(before), as_of_date=fixture_date,
                )
                if not fv:
                    continue  # no pre-fixture appearances -> not scorable
                load = compute_load_features(
                    blocks_before, before, fixture_date, profile.get("birthDate", "")
                )

                fine = str(fv.get("position_group_fine", "MID")).upper()
                row: Dict[str, float] = {
                    "playerId": int(pid),
                    "team_short": team_short,
                    "match_id": mid,
                    "fixture_idx": fixture_idx,
                    "season_id": sid,
                    "round_id": rid,
                    "started": 1 if int(pid) in starter_pids else 0,
                }
                for c in STATIC_PLAYER_COLS:
                    row[c] = float(fv.get(c, 0.0) or 0.0)
                row.update({
                    "availability_last_5": float(fv.get("availability_last_5", 0.0) or 0.0),
                    "started_last_match": float(fv.get("started_last_match", 0.0) or 0.0),
                    "match_gap_since_last_appearance": min(
                        float(fv.get("match_gap_since_last_appearance", 0.0) or 0.0), 35.0),
                    "availability_score": float(fv.get("availability_score", 0.0) or 0.0),
                    "cumulative_minutes_before_fixture": float(load.get("cumulative_minutes_before_fixture", 0.0) or 0.0),
                    "cumulative_appearances": float(load.get("cumulative_appearances", 0.0) or 0.0),
                })
                for c in LOAD_FEATURE_COLS:
                    row[c] = float(fv.get(c, load.get(c, 0.0)) or 0.0)
                row.update(opp_features)
                # Position one-hot
                for g in FINE_GROUPS:
                    row[f"pos_{g}"] = 1.0 if fine == g else 0.0
                # Team one-hot
                for t in SUPERLIGA_TEAMS:
                    row[f"team_{t.short}"] = 1.0 if team_short == t.short else 0.0
                rows.append(row)

    return pd.DataFrame(rows)


def _hungarian_xi(scored: pd.DataFrame, formation: Dict[str, int]) -> List[int]:
    try:
        from scipy.optimize import linear_sum_assignment
    except Exception:
        out: List[int] = []
        for role, count in formation.items():
            sub = scored[scored["role_group"].astype(str).str.upper() == role.upper()]
            sub = sub.sort_values("score", ascending=False).head(int(count))
            out.extend(int(p) for p in sub["playerId"].tolist())
        return out

    slot_labels: List[str] = []
    for role, count in formation.items():
        slot_labels.extend([role.upper()] * int(count))
    n_slots = len(slot_labels)
    rolesU = scored["role_group"].astype(str).str.upper().to_numpy()
    s = scored["score"].astype(float).to_numpy()
    BIG = 1e6
    cost = np.full((len(scored), n_slots), BIG)
    for j, sl in enumerate(slot_labels):
        eligible = rolesU == sl
        cost[eligible, j] = -s[eligible]
    if len(scored) < n_slots:
        pad = n_slots - len(scored)
        cost = np.vstack([cost, np.full((pad, n_slots), BIG)])
    try:
        r, c = linear_sum_assignment(cost)
    except ValueError:
        return []
    picked: List[int] = []
    for rr, cc in zip(r, c):
        if rr < len(scored) and cost[rr, cc] < BIG / 2:
            picked.append(int(scored.iloc[rr]["playerId"]))
    return picked


def main() -> int:
    print("Loading data ...")
    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    print(f"  {len(match_files)} match files, {len(profiles)} player profiles.")

    if not LINEUP_HISTORY.exists():
        print("Lineup history missing — run extract_starting_xi_history_league.py first.")
        return 1
    with LINEUP_HISTORY.open("r", encoding="utf-8") as f:
        league_history = json.load(f)

    print(f"League history: {league_history['n_teams']} teams.")

    print("\nBuilding per-team static feature dataframes (this is the slow step) ...")
    static_by_team = _build_static_df_per_team(SUPERLIGA_TEAMS, profiles, match_files)
    print(f"  built {len(static_by_team)} static DataFrames.")

    print("\nBuilding combined per-player blocks (point-in-time source) ...")
    combined_by_pid = _combined_blocks_by_pid(match_files)
    print(f"  indexed {len(combined_by_pid)} player histories.")

    print("\nBuilding opponent-XI lookup ...")
    opp_xi_lookup = _build_opp_xi_lookup(league_history, static_by_team)
    print(f"  populated opp_xi for {len(opp_xi_lookup)} (matchId, team) pairs.")

    print("\nAssembling POINT-IN-TIME (leakage-free) training rows ...")
    table = _build_training_rows(
        league_history, static_by_team, combined_by_pid, profiles, opp_xi_lookup
    )
    print(f"  training table shape: {table.shape}")
    print(f"  positives: {int(table['started'].sum())}/{len(table)} "
          f"({table['started'].mean():.2%})")

    # Feature columns — exclude bookkeeping columns + categorical strings.
    skip_cols = {"playerId", "team_short", "match_id", "fixture_idx",
                 "season_id", "round_id", "started"}
    feature_cols = [c for c in table.columns
                    if c not in skip_cols
                    and table[c].dtype in (np.float64, np.float32, np.int64, np.int32)]
    print(f"  feature cols: {len(feature_cols)}")

    print("\nRunning rolling-origin per-team CV ...")
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    # Sort by chronological order — Sportradar's matchId is monotonically
    # increasing in fixture date (verified empirically across the 2024-25
    # regular season + playoffs), so it is the natural chronological key.
    # ``round_id`` would be wrong: Sportradar emits one round_id per stage
    # (one for the whole regular season, one for the playoff round), so a
    # ``round_id < rid`` filter would silently include all 16 × 30 regular-
    # season rows in the *first* held-out fixture's training set and empty
    # ones for the rest.
    table_sorted = table.sort_values(["match_id"]).reset_index(drop=True)

    per_team_overlaps: Dict[str, List[float]] = {t.short: [] for t in SUPERLIGA_TEAMS}
    cv_records: List[dict] = []

    # For each held-out (team, fixture_idx >= I_MIN), train on every row
    # whose matchId is strictly smaller.
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

            X_train = table_sorted.loc[train_mask, feature_cols].to_numpy()
            y_train = table_sorted.loc[train_mask, "started"].to_numpy()
            X_test = table_sorted.loc[test_mask, feature_cols].to_numpy()

            scaler = StandardScaler().fit(X_train)
            clf = LogisticRegression(
                max_iter=1000, class_weight="balanced", C=1.0, solver="lbfgs",
            )
            clf.fit(scaler.transform(X_train), y_train)
            scores = clf.predict_proba(scaler.transform(X_test))[:, 1]

            test_df = table_sorted.loc[test_mask, ["playerId"]].copy()
            wy_substr = team.wy_substr
            static_df = static_by_team[wy_substr]
            test_df["role_group"] = test_df["playerId"].map(
                static_df.set_index("playerId")["role_group"].to_dict()
            )
            test_df["score"] = scores

            actual_starters = {int(s["playerId"]) for s in fixture["starters"]}
            predicted = _hungarian_xi(test_df, formation={"GK": 1, "DEF": 4, "MID": 3, "FWD": 3})
            pred_set = set(predicted)
            union = pred_set | actual_starters
            jacc = (len(pred_set & actual_starters) / len(union)) if union else 0.0
            per_team_overlaps[team.short].append(jacc)
            cv_records.append({
                "team_short": team.short,
                "fixture_idx": hold_out_idx,
                "match_id": mid,
                "n_actual": len(actual_starters),
                "n_predicted": len(pred_set),
                "overlap": len(pred_set & actual_starters),
                "jaccard": jacc,
            })

    print()
    print(f"{'team':24s} {'n':5s} {'mean Jaccard':14s} {'std':6s}")
    print("-" * 55)
    league_overlaps: List[float] = []
    for team in SUPERLIGA_TEAMS:
        vs = per_team_overlaps[team.short]
        if not vs:
            print(f"{team.short:24s} 0   (no CV rows)")
            continue
        mu = float(np.mean(vs))
        sigma = float(np.std(vs))
        league_overlaps.extend(vs)
        print(f"{team.short:24s} {len(vs):5d} {mu:14.4f} {sigma:6.4f}")
    print("-" * 55)
    print(f"{'LEAGUE AGGREGATE':24s} {len(league_overlaps):5d} "
          f"{float(np.mean(league_overlaps)):14.4f} "
          f"{float(np.std(league_overlaps)):6.4f}")

    # ── Final model fit on ALL data ─────────────────────────────────────────
    print("\nFitting final model on the full league dataset ...")
    X_all = table_sorted[feature_cols].to_numpy()
    y_all = table_sorted["started"].to_numpy()
    final_scaler = StandardScaler().fit(X_all)
    final_clf = LogisticRegression(
        max_iter=1000, class_weight="balanced", C=1.0, solver="lbfgs",
    ).fit(final_scaler.transform(X_all), y_all)

    print("  final coefficients (top 12 by |w|):")
    coef_pairs = sorted(zip(feature_cols, final_clf.coef_[0]), key=lambda x: -abs(x[1]))
    for name, w in coef_pairs[:12]:
        print(f"    {name:42s}  {w:+.4f}")

    bundle = {
        "model": final_clf,
        "scaler": final_scaler,
        "feature_cols": feature_cols,
        "fine_groups": FINE_GROUPS,
        "team_shorts": [t.short for t in SUPERLIGA_TEAMS],
        "opp_xi_sum_cols": OPP_XI_SUM_COLS,
        "static_player_cols": STATIC_PLAYER_COLS,
        "per_team_mean_jaccard": {
            t: float(np.mean(per_team_overlaps[t])) if per_team_overlaps[t] else float("nan")
            for t in (team.short for team in SUPERLIGA_TEAMS)
        },
        "per_team_n": {
            t: len(per_team_overlaps[t]) for t in (team.short for team in SUPERLIGA_TEAMS)
        },
        "league_mean_jaccard": float(np.mean(league_overlaps)) if league_overlaps else 0.0,
        "league_std_jaccard": float(np.std(league_overlaps)) if league_overlaps else 0.0,
        "league_n": len(league_overlaps),
        "cv_records": cv_records,
        "i_min": I_MIN,
    }

    OUT_BUNDLE.parent.mkdir(parents=True, exist_ok=True)
    if OUT_BUNDLE.exists():
        import shutil
        prev_path = OUT_BUNDLE.parent / "xi_lineup_model_league.prev.joblib"
        shutil.copyfile(OUT_BUNDLE, prev_path)
        print(f"  backed up previous bundle -> {prev_path.name}")
    joblib.dump(bundle, OUT_BUNDLE)
    sz = os.path.getsize(OUT_BUNDLE)
    print(f"\nSaved league bundle -> {OUT_BUNDLE.relative_to(ROOT)} ({sz:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
