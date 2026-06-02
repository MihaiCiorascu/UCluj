"""
Football Starting XI Predictor — Main Pipeline
==============================================
Usage:
    python pipeline.py \
        --my-team-id 11571 \
        --opponent-team-id 99999 \
        --formation 4-3-3 \
        --match-stats-dir ./data/match_stats/ \
        --player-profiles ./data/player_profiles.json \
        --output ./output_xi.json

Or import and call programmatically — see bottom of file for example.
"""

import argparse
import json
import os
import sys
import glob
import pickle
from pathlib import Path
from typing import Dict, List, Optional

import pandas as pd
import numpy as np

# ── Local imports ──────────────────────────────────────────────────────────────
sys.path.insert(0, str(Path(__file__).parent))
from feature_engineering import (
    build_dataset_from_files,
    load_match_stats_json,
    build_player_feature_vector,
)
from xi_predictor import StartingXIPredictor, FORMATIONS
from drive_loader import (
    download_drive_folder,
    discover_data_paths,
    DRIVE_FOLDER_ID,
)


# ─── Helper: load player profiles ─────────────────────────────────────────────

def load_player_profiles(filepath: str) -> Dict[int, Dict]:
    """
    Load player profiles from a JSON file.
    Supports two formats:
      - A list of player objects: [{wyId: ..., ...}, ...]
      - A dict keyed by playerId: {"123": {...}, ...}
    """
    with open(filepath) as f:
        raw = json.load(f)
    if isinstance(raw, list):
        return {p["wyId"]: p for p in raw if "wyId" in p}
    elif isinstance(raw, dict):
        if "players" in raw and isinstance(raw["players"], list):
            return {p["wyId"]: p for p in raw["players"] if "wyId" in p}
        return {int(k): v for k, v in raw.items()}
    return {}


def load_team_assignments(filepath: str) -> Dict[int, int]:
    """
    Optional: load a JSON mapping playerId -> teamId.
    Format: {"playerId": teamId, ...}
    """
    if not filepath or not os.path.exists(filepath):
        return {}
    with open(filepath) as f:
        raw = json.load(f)
    return {int(k): int(v) for k, v in raw.items()}


# ─── Core pipeline function ────────────────────────────────────────────────────

def run_pipeline(
    my_team_id: int,
    opponent_team_id: Optional[int],
    match_stats_dir: str = "",
    player_profiles_path: str = "",
    formation: str = "4-3-3",
    team_assignments_path: Optional[str] = None,
    output_path: Optional[str] = None,
    model_save_path: Optional[str] = None,
    model_load_path: Optional[str] = None,
    verbose: bool = True,
    drive_folder_id: Optional[str] = None,
    drive_cache_dir: Optional[str] = None,
    force_redownload: bool = False,
) -> Dict:
    """
    Full end-to-end pipeline.

    Steps:
      0. (Optional) Download training data from Google Drive
      1. Discover match stat files
      2. Load player profiles
      3. Build feature dataset
      4. Assign team IDs (from file or extracted from stats)
      5. Train/load model
      6. Predict starting XI for your team vs opponent
      7. Print and optionally save results

    Returns dict with xi, bench, scores.
    """
    # ── 0. Download from Google Drive (if requested) ───────────────────────
    if drive_folder_id:
        cache = download_drive_folder(drive_folder_id, drive_cache_dir, force_redownload)
        discovered_stats_dir, discovered_profiles = discover_data_paths(cache)
        if not match_stats_dir:
            match_stats_dir = discovered_stats_dir
        if not player_profiles_path and discovered_profiles:
            player_profiles_path = discovered_profiles
        if verbose:
            print(f"[Drive] match_stats_dir  → {match_stats_dir}")
            print(f"[Drive] player_profiles  → {player_profiles_path or '(none found)'}")

    if not match_stats_dir:
        raise ValueError("Provide --match-stats-dir or --drive-folder-id so the pipeline knows where to find data.")

    # ── 1. Find match files ────────────────────────────────────────────────
    match_files = sorted(glob.glob(os.path.join(match_stats_dir, "*.json")))
    if not match_files:
        raise FileNotFoundError(f"No JSON files found in: {match_stats_dir}")
    if verbose:
        print(f"[Pipeline] Found {len(match_files)} match stat file(s)")

    # ── 2. Load player profiles ────────────────────────────────────────────
    player_profiles: Dict[int, Dict] = {}
    if player_profiles_path and os.path.exists(player_profiles_path):
        player_profiles = load_player_profiles(player_profiles_path)
        if verbose:
            print(f"[Pipeline] Loaded {len(player_profiles)} player profiles")

    # ── 3. Build feature dataset ───────────────────────────────────────────
    df = build_dataset_from_files(match_files, player_profiles)
    if df.empty:
        raise ValueError("Feature dataset is empty — check your match stat files.")
    if verbose:
        print(f"[Pipeline] Dataset: {len(df)} players, {len(df.columns)} features")

    # ── 4. Assign team IDs ─────────────────────────────────────────────────
    # Try loading from external file, then from profiles, then from match stats
    team_map = load_team_assignments(team_assignments_path or "")

    def resolve_team(pid):
        if pid in team_map:
            return team_map[pid]
        profile = player_profiles.get(pid, {})
        return profile.get("currentTeamId", None)

    df["teamId"] = df["playerId"].apply(resolve_team)

    # Split your team vs opponent
    my_team_df = df[df["teamId"] == my_team_id].copy()
    opp_team_df = df[df["teamId"] == opponent_team_id].copy() if opponent_team_id else pd.DataFrame()

    if my_team_df.empty:
        print(f"[Warning] No players found for team ID {my_team_id}. Using all players.")
        my_team_df = df.copy()

    if verbose:
        print(f"[Pipeline] Your team ({my_team_id}): {len(my_team_df)} players")
        if opponent_team_id:
            print(f"[Pipeline] Opponent ({opponent_team_id}): {len(opp_team_df)} players")

    # ── 5. Build or load model ─────────────────────────────────────────────
    predictor = StartingXIPredictor(model_type="auto")

    if model_load_path and os.path.exists(model_load_path):
        with open(model_load_path, "rb") as f:
            predictor = pickle.load(f)
        if verbose:
            print(f"[Pipeline] Loaded model from {model_load_path}")
    else:
        # Try to create training labels:
        # If we have historical matchesInStart data, use it
        if "per90_matchesInStart" in df.columns or "matches_played" in df.columns:
            # Proxy label: player started in >50% of known matches
            # (Replace with actual labels from your DB if available)
            labels = None
            if "per90_matchesInStart" not in df.columns:
                try:
                    # Build richer label from raw stats across matches
                    labels = _build_proxy_labels(match_files, player_profiles, my_team_id)
                    if labels is not None:
                        labels = labels.reindex(df.index).fillna(0).astype(int)
                except Exception as e:
                    if verbose:
                        print(f"[Pipeline] Could not build proxy labels: {e}")
                    labels = None
            predictor.fit(df, labels=labels, verbose=verbose)
        else:
            predictor.fit(df, labels=None, verbose=verbose)

        if model_save_path:
            with open(model_save_path, "wb") as f:
                pickle.dump(predictor, f)
            if verbose:
                print(f"[Pipeline] Model saved to {model_save_path}")

    # ── 6. Predict XI ──────────────────────────────────────────────────────
    result = predictor.predict_xi(
        df=my_team_df,
        formation=formation,
        your_team_id=my_team_id,
        opponent_df=opp_team_df if not opp_team_df.empty else None,
    )

    # ── 7. Format & print ──────────────────────────────────────────────────
    if verbose:
        _print_xi(result, my_team_id, opponent_team_id)

    # ── 8. Feature importance ──────────────────────────────────────────────
    fi = predictor.get_feature_importance()
    if fi is not None and verbose:
        print("\n── Top 10 Feature Importances ──────────────────────────────")
        print(fi.head(10).to_string(index=False))

    # ── 9. Save output ─────────────────────────────────────────────────────
    output = _format_output(result, my_team_id, opponent_team_id)
    if output_path:
        with open(output_path, "w") as f:
            json.dump(output, f, indent=2)
        if verbose:
            print(f"\n[Pipeline] Results saved to {output_path}")

    return output


# ─── Proxy label builder ───────────────────────────────────────────────────────

def _build_proxy_labels(
    match_files: List[str],
    player_profiles: Dict[int, Dict],
    my_team_id: int,
) -> Optional[pd.Series]:
    """
    Build proxy start/bench labels from matchesInStart in historical data.
    Returns a Series indexed by playerId.
    """
    records = {}
    for filepath in match_files:
        for entry in load_match_stats_json(filepath):
            pid = entry.get("playerId")
            if pid is None:
                continue
            started = entry.get("total", {}).get("matchesInStart", 0) or 0
            if pid not in records:
                records[pid] = {"starts": 0, "total": 0}
            records[pid]["starts"] += started
            records[pid]["total"] += 1

    if not records:
        return None

    start_rate = {pid: v["starts"] / max(v["total"], 1) for pid, v in records.items()}
    return pd.Series(start_rate).apply(lambda x: 1 if x >= 0.5 else 0)


# ─── Formatting helpers ────────────────────────────────────────────────────────

def _print_xi(result: Dict, my_team_id: int, opponent_team_id: Optional[int]):
    formation = result["formation"]
    xi = result["xi"]
    bench = result["bench"]

    print(f"\n{'='*60}")
    print(f"  PREDICTED STARTING XI  |  Formation: {formation}")
    print(f"  Your Team: {my_team_id}  |  Opponent: {opponent_team_id or 'Unknown'}")
    print(f"{'='*60}")

    order = ["GK", "DEF", "MID", "FWD"]
    for group in order:
        sub = xi[xi["role_group"] == group]
        if sub.empty:
            continue
        print(f"\n  [{group}]")
        for _, row in sub.iterrows():
            name = row.get("shortName") or row.get("playerId")
            score = row.get("predicted_score", 0)
            role = row.get("role", "")
            mins = int(row.get("total_minutes", 0))
            print(f"    {name:<25} | {role:<25} | Score: {score:.3f} | Mins: {mins}")

    print(f"\n{'─'*60}")
    print("  BENCH (top 7 remaining)")
    print(f"{'─'*60}")
    for _, row in bench.iterrows():
        name = row.get("shortName") or row.get("playerId")
        score = row.get("predicted_score", 0)
        group = row.get("role_group", "")
        print(f"    {name:<25} | {group} | Score: {score:.3f}")
    print(f"{'='*60}\n")


def _format_output(result: Dict, my_team_id: int, opponent_team_id: Optional[int]) -> Dict:
    def df_to_list(df: pd.DataFrame) -> List[Dict]:
        if df is None or df.empty:
            return []
        cols = ["playerId", "shortName", "role", "role_group",
                "position_group_fine", "official_position", "slot_index",
                "predicted_score", "performance_score", "recent_form_score",
                "total_minutes", "matches_played",
                "pass_accuracy", "duel_win_rate",
                "shot_accuracy", "dribble_success", "def_action_success", "aerial_win_rate",
                "per90_goals", "per90_assists", "per90_keyPasses", "per90_shots",
                "per90_interceptions", "per90_gkSaves", "per90_gkCleanSheets"]
        cols = [c for c in cols if c in df.columns]
        return df[cols].fillna(0).to_dict(orient="records")

    return {
        "myTeamId": my_team_id,
        "opponentTeamId": opponent_team_id,
        "formation": result["formation"],
        "startingXI": df_to_list(result["xi"]),
        "bench": df_to_list(result["bench"]),
    }


# ─── CLI Entry Point ───────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Predict Starting XI based on match stats and player profiles"
    )
    parser.add_argument("--my-team-id", type=int, required=True)
    parser.add_argument("--opponent-team-id", type=int, default=None)
    parser.add_argument("--formation", default="4-3-3",
                        choices=list(FORMATIONS.keys()))
    parser.add_argument("--match-stats-dir", default=None,
                        help="Directory containing match stats JSON files (not needed when using --drive-folder-id)")
    parser.add_argument("--player-profiles", default=None,
                        help="Path to player profiles JSON")
    parser.add_argument("--drive-folder-id", default=DRIVE_FOLDER_ID,
                        help="Google Drive folder ID to download training data from "
                             f"(default: {DRIVE_FOLDER_ID})")
    parser.add_argument("--drive-cache-dir", default=None,
                        help="Local directory to cache Drive downloads (default: ml/data/drive_cache)")
    parser.add_argument("--force-redownload", action="store_true",
                        help="Re-download Drive data even if a local cache exists")
    parser.add_argument("--no-drive", action="store_true",
                        help="Disable Google Drive download; use --match-stats-dir instead")
    parser.add_argument("--team-assignments", default=None,
                        help="Optional JSON mapping playerId -> teamId")
    parser.add_argument("--output", default=None,
                        help="Path to save output JSON")
    parser.add_argument("--save-model", default=None,
                        help="Path to save trained model (.pkl)")
    parser.add_argument("--load-model", default=None,
                        help="Path to load pre-trained model (.pkl)")

    args = parser.parse_args()

    run_pipeline(
        my_team_id=args.my_team_id,
        opponent_team_id=args.opponent_team_id,
        match_stats_dir=args.match_stats_dir or "",
        player_profiles_path=args.player_profiles or "",
        formation=args.formation,
        team_assignments_path=args.team_assignments,
        output_path=args.output,
        model_save_path=args.save_model,
        model_load_path=args.load_model,
        verbose=True,
        drive_folder_id=None if args.no_drive else args.drive_folder_id,
        drive_cache_dir=args.drive_cache_dir,
        force_redownload=args.force_redownload,
    )


if __name__ == "__main__":
    main()
