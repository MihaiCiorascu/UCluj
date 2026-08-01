"""
demo.py, Quick demo using the uploaded Arges vs Botosani match file.

This simulates what the pipeline does when you feed it multiple match files.
Run from the football_xi/ directory:
    python demo.py
"""

import sys
import json
import copy
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from utils.feature_engineering import build_dataset_from_files, load_match_stats_json
from models.xi_predictor import StartingXIPredictor, FORMATIONS

# Paths
MATCH_FILE = "/mnt/user-data/uploads/Arges__-_Botos_ani__0-0_players_stats.json"

# Player profile for D. Aftene (provided by user)
SAMPLE_PROFILES = {
    1309916: {
        "wyId": 1309916,
        "shortName": "D. Aftene",
        "firstName": "Dragos",
        "lastName": "Aftene",
        "birthDate": "2005-10-04",
        "role": {"name": "Midfielder", "code2": "MD", "code3": "MID"},
        "currentTeamId": 11571,
        "gender": "male",
        "status": "active",
    }
}

# Demo: assign mock team IDs from the match data
def extract_team_assignments(match_file: str, sample_profiles: dict) -> dict:
    """
    Since the match file doesn't encode teamId per player,
    we use currentTeamId from profiles + guess from positions for the rest.
    
    In a real system your DB would have this mapping.
    """
    players = load_match_stats_json(match_file)
    assignments = {}
    
    # Split roughly in half (home/away) for demo purposes
    # In production: use your matches JSON that has teamId per player
    pids = [p["playerId"] for p in players if p.get("total", {}).get("minutesOnField", 0) > 0]
    
    # Players we know
    for pid, profile in sample_profiles.items():
        assignments[pid] = profile.get("currentTeamId", 11571)
    
    # Split remaining between two demo teams (Arges=11571, Botosani=99999)
    mid = len(pids) // 2
    for i, pid in enumerate(pids):
        if pid not in assignments:
            assignments[pid] = 11571 if i < mid else 99999

    return assignments


def main():
    print("=" * 60)
    print("  Football Starting XI Predictor, DEMO")
    print("=" * 60)

    # 1. Build feature dataset from the single sample file
    df = build_dataset_from_files([MATCH_FILE], SAMPLE_PROFILES)
    print(f"\n[Demo] Players with valid stats: {len(df)}")

    # 2. Assign team IDs
    assignments = extract_team_assignments(MATCH_FILE, SAMPLE_PROFILES)
    df["teamId"] = df["playerId"].apply(lambda pid: assignments.get(pid))

    my_team_id = 11571    # Arges
    opp_team_id = 99999   # Botosani (demo)

    my_team = df[df["teamId"] == my_team_id].copy()
    opp_team = df[df["teamId"] == opp_team_id].copy()

    print(f"[Demo] Your team (Arges, ID {my_team_id}): {len(my_team)} players")
    print(f"[Demo] Opponent (Botosani, ID {opp_team_id}): {len(opp_team)} players")

    # 3. Train predictor (unsupervised, no labels from a single match)
    predictor = StartingXIPredictor(model_type="rf")
    predictor.fit(df, labels=None, verbose=True)

    # 4. Predict XI for 4-3-3
    for formation in ["4-3-3", "4-4-2", "3-5-2"]:
        print(f"\n{'-'*60}")
        print(f"  FORMATION: {formation}")
        print(f"{'-'*60}")
        result = predictor.predict_xi(
            df=my_team,
            formation=formation,
            your_team_id=my_team_id,
            opponent_df=opp_team,
        )
        xi = result["xi"]
        for group in ["GK", "DEF", "MID", "FWD"]:
            sub = xi[xi["role_group"] == group]
            if sub.empty:
                continue
            print(f"\n  [{group}]")
            for _, row in sub.iterrows():
                name = row.get("shortName") or f"ID:{row['playerId']}"
                score = row.get("predicted_score", 0)
                role = row.get("role", "")
                mins = int(row.get("total_minutes", 0) or 0)
                pm = int(row.get("matches_played", 0) or 0)
                print(f"    {name:<26} {role:<26} Score:{score:.4f}  Mins:{mins}  Matches:{pm}")

    print("\n[Demo] Done. Feed more match files to improve predictions.")


if __name__ == "__main__":
    main()
