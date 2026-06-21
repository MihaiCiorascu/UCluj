from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Dict, Any, Optional

from core.dependencies import get_xi_service, get_feature_service
from core.security import get_current_user
from services.xi_service import XiService
from services.feature_service import FeatureService

router = APIRouter()


def _subject_short(user) -> str:
    """The home team for XI prediction: the authenticated user's club (registry
    short), defaulting to Universitatea Cluj when unset."""
    return (getattr(user, "team_name", None) or "U Cluj").strip()


def _home_kwargs(home_team, user) -> dict:
    """Resolve the preview's home team: an explicit override (used to view any
    club's fixture, e.g. a non-subject match) when given, else the user's club."""
    if home_team and str(home_team).strip():
        return {"home_team_substring": str(home_team).strip()}
    return {"home_team_short": _subject_short(user)}


def _coerce_locked(locked: Optional[Dict[str, int]]) -> Optional[Dict[int, int]]:
    """Coerce a JSON ``locked`` object to ``{slot_index(int) -> playerId(int)}``.

    JSON object keys are always strings, so the wire form is
    ``{"3": 123456, "0": 7788}`` (key = slot index, value = playerId). Entries
    whose key or value cannot be parsed as integers are dropped silently; the
    predictor performs the deeper validation (range, membership, duplicates).
    """
    if not locked:
        return None
    out: Dict[int, int] = {}
    for k, v in locked.items():
        try:
            out[int(k)] = int(v)
        except (TypeError, ValueError):
            continue
    return out or None


class XiRequest(BaseModel):
    opponent_team_id: Optional[int] = None
    formation: str = "auto"


class MatchPreviewRequest(BaseModel):
    opponent_name: str
    formation: str = "auto"
    # JSON object keyed by stringified slot index -> playerId.
    locked: Dict[str, int] = Field(default_factory=dict)
    # Home team override (defaults to the user's club); set when previewing a
    # fixture that does not involve the user's team.
    home_team: Optional[str] = None
    # Upcoming fixture date (ISO). Used only to show rest-days before the real
    # next match; ignored if absent or unparseable.
    fixture_date: Optional[str] = None


class OpponentTeam(BaseModel):
    id: int
    name: str

@router.post("/predict", response_model=Dict[str, Any])
def predict_xi(
    body: XiRequest,
    xi_svc: XiService = Depends(get_xi_service),
    _user=Depends(get_current_user),
):
    try:
        result = xi_svc.predict_xi(
            formation=body.formation,
            opponent_team_id=body.opponent_team_id,
            home_team_short=_subject_short(_user),
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/opponents", response_model=list[OpponentTeam])
def list_opponents(
    xi_svc: XiService = Depends(get_xi_service),
    _user=Depends(get_current_user),
):
    try:
        return xi_svc.list_opponents(home_team_substring=_subject_short(_user))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/match-preview", response_model=Dict[str, Any])
def match_preview(
    opponent_name: str = Query(..., description="Opponent team name as it appears in fixtures"),
    formation: str = Query("auto", description="A curated formation key, or 'auto' to auto-pick the best shape"),
    home_team: Optional[str] = Query(None, description="Home team override (defaults to the user's club)"),
    fixture_date: Optional[str] = Query(None, description="Upcoming fixture date (ISO); for rest-days display only"),
    xi_svc: XiService = Depends(get_xi_service),
    feature_svc: FeatureService = Depends(get_feature_service),
    _user=Depends(get_current_user),
):
    """Simple match preview (no slot locks). ``formation`` defaults to 'auto'."""
    try:
        return xi_svc.match_preview(
            opponent_name=opponent_name,
            formation=formation,
            main_df=feature_svc._df,
            fixture_date=fixture_date,
            **_home_kwargs(home_team, _user),
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/match-preview", response_model=Dict[str, Any])
def match_preview_post(
    body: MatchPreviewRequest,
    xi_svc: XiService = Depends(get_xi_service),
    feature_svc: FeatureService = Depends(get_feature_service),
    _user=Depends(get_current_user),
):
    """Match preview with optional slot locks and lock-aware re-optimisation.

    Body: ``{opponent_name, formation="auto", locked={slot_index_str: playerId}}``.
    Locked players are pinned to their slot and the rest of the XI re-optimises
    around them. With ``formation="auto"`` the best curated shape is chosen with
    those locks applied. Returns the same shape as the GET endpoint, with the
    resolved ``formation`` and the re-optimised ``starting_xi`` / ``bench``.
    """
    try:
        return xi_svc.match_preview(
            opponent_name=body.opponent_name,
            formation=body.formation,
            main_df=feature_svc._df,
            locked=_coerce_locked(body.locked),
            fixture_date=body.fixture_date,
            **_home_kwargs(body.home_team, _user),
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
