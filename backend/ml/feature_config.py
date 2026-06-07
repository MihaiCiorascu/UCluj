BASE_FEATURES = [
    "Home_Points_5", "Away_Points_5",
    "Home_Goals_5", "Away_Goals_5",
    "Home_Conceded_5", "Away_Conceded_5",
    "Home_RestDays", "Away_RestDays",
    "Home_Poss_5", "Away_Poss_5",
    "Home_Shots_5", "Away_Shots_5",
    "Home_SoT_5", "Away_SoT_5",
    "Home_Corners_5", "Away_Corners_5",
    "Computed_Home_Elo", "Computed_Away_Elo",
    "Computed_HFA", "Computed_Elo_Diff",
]

OPTIONAL_FEATURES = [
    "Home_YellowCards_5", "Away_YellowCards_5",
    "Home_Saves_5", "Away_Saves_5",
    "Home_H2H_Pts_3", "Away_H2H_Pts_3",
]

# Controllables-only decision set. Goals and Conceded are deliberately
# excluded: they are near-tautological predictors of a win-probability model,
# so optimising over them collapses to "score more, concede less", which is
# not an actionable tactical lever. They remain frozen baseline model inputs
# (the prediction still reflects the team's real scoring/defensive form), but
# the optimiser only dials the four levers a coach can genuinely influence.
OPTIMIZABLE_FEATURES = [
    "Home_Poss_5",
    "Home_Shots_5",
    "Home_SoT_5",
    "Home_Corners_5",
]

OPTIMIZABLE_LABELS = {
    "Home_Poss_5": "Possession",
    "Home_Shots_5": "Shots",
    "Home_SoT_5": "Shots on Target",
    "Home_Corners_5": "Corners",
}

TARGET_COL = "Target_Binary"

METADATA_COLS = [
    "match_id", "season", "match_date", "league",
    "home_team", "away_team", "home_score", "away_score",
]
