"""
Quick ablation: league-wide Jaccard with vs. without the opponent-XI
cascade features. Compares two trainings of the same logistic regression
on the same training rows, the only difference being whether the
``opp_xi_*`` feature block is included.

Reports league aggregate Jaccard for both and the per-team delta.
"""

from __future__ import annotations

import glob
import json
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parents[1]  # backend/
sys.path.insert(0, str(ROOT))

# Reuse the training-table builder from the league trainer by importing it.
import importlib.util
spec = importlib.util.spec_from_file_location(
    "train_league", str(ROOT / "scripts" / "train_lineup_classifier_league.py")
)
train_league = importlib.util.module_from_spec(spec)  # type: ignore
spec.loader.exec_module(train_league)  # type: ignore

from sportradar.team_registry import SUPERLIGA_TEAMS  # type: ignore  # noqa: E402

DRIVE = ROOT / "ml" / "data" / "drive_cache"
LINEUP_HISTORY = ROOT / "ml" / "data" / "lineup_history_league.json"

I_MIN = 8


def run_cv(table: pd.DataFrame, feature_cols: List[str],
           league_history: dict, static_by_team: Dict) -> Dict[str, List[float]]:
    table_sorted = table.sort_values(["match_id"]).reset_index(drop=True)
    per_team_overlaps: Dict[str, List[float]] = {t.short: [] for t in SUPERLIGA_TEAMS}

    for team in SUPERLIGA_TEAMS:
        team_blob = next(
            (tb for tb in league_history["teams"] if tb["team_short"] == team.short),
            None,
        )
        if team_blob is None:
            continue
        wy_substr = team.wy_substr
        static_df = static_by_team[wy_substr]
        role_lookup = static_df.set_index("playerId")["role_group"].to_dict()

        for hold_out_idx, fixture in enumerate(team_blob["fixtures"]):
            if hold_out_idx < I_MIN:
                continue
            mid = int(fixture["match_id"])
            train_mask = table_sorted["match_id"] < mid
            test_mask = ((table_sorted["team_short"] == team.short)
                         & (table_sorted["match_id"] == mid))
            if not train_mask.any() or not test_mask.any():
                continue

            X_train = table_sorted.loc[train_mask, feature_cols].to_numpy()
            y_train = table_sorted.loc[train_mask, "started"].to_numpy()
            X_test = table_sorted.loc[test_mask, feature_cols].to_numpy()

            scaler = StandardScaler().fit(X_train)
            clf = LogisticRegression(
                max_iter=1000, class_weight="balanced", C=1.0, solver="lbfgs",
            ).fit(scaler.transform(X_train), y_train)
            scores = clf.predict_proba(scaler.transform(X_test))[:, 1]

            test_df = table_sorted.loc[test_mask, ["playerId"]].copy()
            test_df["role_group"] = test_df["playerId"].map(role_lookup)
            test_df["score"] = scores

            actual = {int(s["playerId"]) for s in fixture["starters"]}
            predicted = train_league._hungarian_xi(
                test_df, formation={"GK": 1, "DEF": 4, "MID": 3, "FWD": 3}
            )
            pred = set(predicted)
            union = pred | actual
            if union:
                per_team_overlaps[team.short].append(len(pred & actual) / len(union))
    return per_team_overlaps


def main() -> int:
    from ml.pipeline import load_player_profiles  # noqa: E402

    profiles = load_player_profiles(str(DRIVE / "players (1).json"))
    match_files = sorted(glob.glob(str(DRIVE / "*_players_stats.json")))
    with LINEUP_HISTORY.open("r", encoding="utf-8") as f:
        league_history = json.load(f)

    print("Building per-team static dfs (slow) ...")
    static_by_team = train_league._build_static_df_per_team(
        SUPERLIGA_TEAMS, profiles, match_files
    )
    print("Indexing per-match player blocks ...")
    blocks_by_pid = train_league._per_match_blocks(match_files)
    print("Building opponent-XI lookup ...")
    opp_xi_lookup = train_league._build_opp_xi_lookup(league_history, static_by_team)
    print("Assembling training rows ...")
    table = train_league._build_training_rows(
        league_history, static_by_team, blocks_by_pid, opp_xi_lookup
    )
    print(f"  table shape: {table.shape}")

    skip_cols = {"playerId", "team_short", "match_id", "fixture_idx",
                 "season_id", "round_id", "started"}
    all_feature_cols = [c for c in table.columns
                        if c not in skip_cols
                        and table[c].dtype in (np.float64, np.float32, np.int64, np.int32)]
    no_opp_xi_cols = [c for c in all_feature_cols if not c.startswith("opp_xi_")]
    print(f"  with opp_xi: {len(all_feature_cols)} features")
    print(f"  without opp_xi: {len(no_opp_xi_cols)} features ({len(all_feature_cols)-len(no_opp_xi_cols)} removed)")

    print("\nRunning CV WITH opp_xi features ...")
    with_overlaps = run_cv(table, all_feature_cols, league_history, static_by_team)

    print("Running CV WITHOUT opp_xi features ...")
    without_overlaps = run_cv(table, no_opp_xi_cols, league_history, static_by_team)

    print()
    print(f"{'team':24s} {'with opp':10s} {'without':10s} {'delta':9s}")
    print("-" * 60)
    league_with: List[float] = []
    league_without: List[float] = []
    for team in SUPERLIGA_TEAMS:
        wo = with_overlaps[team.short]
        wo_ = without_overlaps[team.short]
        if not wo or not wo_:
            continue
        league_with.extend(wo)
        league_without.extend(wo_)
        mu_w = float(np.mean(wo))
        mu_wo = float(np.mean(wo_))
        delta = mu_w - mu_wo
        sign = "+" if delta >= 0 else ""
        print(f"{team.short:24s} {mu_w:10.4f} {mu_wo:10.4f} {sign}{delta:8.4f}")
    print("-" * 60)
    lg_w = float(np.mean(league_with))
    lg_wo = float(np.mean(league_without))
    sign = "+" if (lg_w - lg_wo) >= 0 else ""
    print(f"{'LEAGUE':24s} {lg_w:10.4f} {lg_wo:10.4f} {sign}{lg_w - lg_wo:8.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
