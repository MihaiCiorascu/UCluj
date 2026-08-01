from __future__ import annotations

import pandas as pd

from ml.feature_config import OPTIMIZABLE_LABELS
from services.model_service import ModelService

# Labels when the SUBJECT team is the HOME team (or generic perspective)
FEATURE_LABELS: dict[str, str] = {
    "Computed_Elo_Diff": "Elo Advantage",
    "Computed_HFA": "Home Field Advantage",
    "Computed_Home_Elo": "Team Elo Rating",
    "Computed_Away_Elo": "Opponent Elo Rating",
    "Home_RestDays": "Rest Days",
    "Away_RestDays": "Opponent Rest Days",
    "Home_Points_5": "Recent Form (Points)",
    "Away_Points_5": "Opponent Form (Points)",
    "Home_Goals_5": "Goals Scored (5-match)",
    "Away_Goals_5": "Opponent Goals (5-match)",
    "Home_Conceded_5": "Goals Conceded (5-match)",
    "Away_Conceded_5": "Opponent Conceded (5-match)",
    "Home_Poss_5": "Possession (5-match)",
    "Away_Poss_5": "Opponent Possession (5-match)",
    "Home_Shots_5": "Shots (5-match)",
    "Away_Shots_5": "Opponent Shots (5-match)",
    "Home_SoT_5": "Shots on Target (5-match)",
    "Away_SoT_5": "Opponent SoT (5-match)",
    "Home_Corners_5": "Corners (5-match)",
    "Away_Corners_5": "Opponent Corners (5-match)",
    "Home_H2H_Pts_3": "H2H Record",
    "Away_H2H_Pts_3": "Opponent H2H Record",
    "Home_YellowCards_5": "Discipline (Yellow Cards)",
    "Away_YellowCards_5": "Opponent Discipline",
    "Home_Saves_5": "Goalkeeper Saves",
    "Away_Saves_5": "Opponent GK Saves",
    **OPTIMIZABLE_LABELS,
}

# Labels when the SUBJECT team is the AWAY team (Home_* = opponent, Away_* = subject)
FEATURE_LABELS_AWAY: dict[str, str] = {
    "Computed_Elo_Diff": "Opponent Elo Lead",
    "Computed_HFA": "Opponent Home Advantage",
    "Computed_Home_Elo": "Opponent Elo Rating",
    "Computed_Away_Elo": "Team Elo Rating",
    "Home_RestDays": "Opponent Rest Days",
    "Away_RestDays": "Rest Days",
    "Home_Points_5": "Opponent Recent Form",
    "Away_Points_5": "Recent Form (Points)",
    "Home_Goals_5": "Opponent Goals (5-match)",
    "Away_Goals_5": "Goals Scored (5-match)",
    "Home_Conceded_5": "Opponent Conceded (5-match)",
    "Away_Conceded_5": "Goals Conceded (5-match)",
    "Home_Poss_5": "Opponent Possession (5-match)",
    "Away_Poss_5": "Possession (5-match)",
    "Home_Shots_5": "Opponent Shots (5-match)",
    "Away_Shots_5": "Shots (5-match)",
    "Home_SoT_5": "Opponent SoT (5-match)",
    "Away_SoT_5": "Shots on Target (5-match)",
    "Home_Corners_5": "Opponent Corners (5-match)",
    "Away_Corners_5": "Corners (5-match)",
    "Home_H2H_Pts_3": "Opponent H2H Record",
    "Away_H2H_Pts_3": "H2H Record",
    "Home_YellowCards_5": "Opponent Discipline",
    "Away_YellowCards_5": "Discipline (Yellow Cards)",
    "Home_Saves_5": "Opponent GK Saves",
    "Away_Saves_5": "Goalkeeper Saves",
    # OPTIMIZABLE_LABELS are Home_* features, when away they're opponent's
    "Home_Poss_5": "Opponent Possession",
    "Home_Shots_5": "Opponent Shots",
    "Home_SoT_5": "Opponent SoT",
    "Home_Corners_5": "Opponent Corners",
    "Home_Goals_5": "Opponent Goals",
    "Home_Conceded_5": "Opponent Conceded",
}

POSITIVE_WHEN_HIGH = {
    "Computed_Elo_Diff", "Computed_HFA", "Computed_Home_Elo",
    "Home_RestDays", "Home_Points_5", "Home_Goals_5",
    "Home_Poss_5", "Home_Shots_5", "Home_SoT_5",
    "Home_Corners_5", "Home_H2H_Pts_3", "Home_Saves_5",
}


class ExplanationService:

    def __init__(self, model_svc: ModelService):
        self._model = model_svc

    def explain(
        self,
        features: pd.DataFrame,
        probability: float,
        subject_is_home: bool = True,
    ) -> dict:
        """Explain a fixture from the subject team's perspective.

        ``probability`` must be P(subject win), already converted from P(Home Win).
        ``subject_is_home`` controls which label set and SHAP sign convention to
        use. Positive SHAP increases P(Home Win); when the subject is away that is
        bad for the subject, so the sign flips.
        """
        contributions = self._model.local_contributions(features)
        label_map = FEATURE_LABELS if subject_is_home else FEATURE_LABELS_AWAY
        # sign: +1 when home (positive SHAP benefits the subject), -1 when away
        sign = 1 if subject_is_home else -1

        if not contributions:
            importances = self._model.feature_importances()
            if not importances:
                return {"top_drivers": [], "top_risks": [], "narrative": "Feature importances unavailable."}
            total = sum(max(float(v), 0.0) for v in importances.values()) or 1.0
            items = [
                {
                    "feature": feat,
                    "label": label_map.get(feat, feat),
                    "importance": round(max(float(imp), 0.0) / total, 4),
                    "direction": "positive",
                }
                for feat, imp in importances.items()
            ]
            items.sort(key=lambda x: x["importance"], reverse=True)
            drivers = items[:5]
            risks: list[dict] = []
            narrative = self._build_narrative(drivers, risks, probability)
            return {"top_drivers": drivers, "top_risks": risks, "narrative": narrative}

        total_abs = sum(abs(float(v)) for v in contributions.values()) or 1.0
        items = []
        for feat, shap in contributions.items():
            subject_shap = sign * float(shap)  # positive = benefits the subject
            items.append({
                "feature": feat,
                "label": label_map.get(feat, feat),
                "importance": round(abs(float(shap)) / total_abs, 4),
                "direction": "positive" if subject_shap >= 0.0 else "negative",
            })

        items.sort(key=lambda x: x["importance"], reverse=True)
        drivers = [i for i in items if i["direction"] == "positive"][:5]
        risks = [i for i in items if i["direction"] == "negative"][:5]
        narrative = self._build_narrative(drivers, risks, probability)

        return {"top_drivers": drivers, "top_risks": risks, "narrative": narrative}

    def build_narrative(
        self,
        drivers: list[dict],
        risks: list[dict],
        probability: float,
    ) -> str:
        """Public narrative builder for already-oriented drivers/risks."""
        return self._build_narrative(drivers, risks, probability)

    def _is_positive_driver(self, feature: str, value: float) -> bool:
        if feature in POSITIVE_WHEN_HIGH:
            return value > 0
        return value <= 0

    def _build_narrative(self, drivers: list, risks: list, prob: float) -> str:
        parts = []
        if prob >= 0.65:
            parts.append(f"Strong position at {prob:.0%} win probability.")
        elif prob >= 0.45:
            parts.append(f"Moderate advantage at {prob:.0%} win probability.")
        else:
            parts.append(f"Challenging outlook at {prob:.0%} win probability.")

        if drivers:
            top = drivers[0]
            parts.append(f"Primary driver: {top['label']}.")

        if risks:
            top_risk = risks[0]
            parts.append(f"Key risk: {top_risk['label']}.")

        return " ".join(parts)
