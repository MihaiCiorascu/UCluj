from __future__ import annotations

from pydantic import BaseModel, Field


class FixtureRequest(BaseModel):
    home_team: str = Field(..., description="Home team name as it appears in the dataset")
    away_team: str = Field(..., description="Away team name as it appears in the dataset")


class PredictionResponse(BaseModel):
    home_team: str
    away_team: str
    baseline_probability: float = Field(..., ge=0, le=1, description="P(Home Win)")
    model: str = "CatBoost (calibrated)"


class TacticalTarget(BaseModel):
    feature: str
    label: str
    baseline_value: float
    optimized_value: float
    delta: float


class BlueprintResponse(BaseModel):
    home_team: str
    away_team: str
    baseline_probability: float
    optimized_probability: float
    uplift: float
    targets: list[TacticalTarget]
    diagnosis: str


class DriverItem(BaseModel):
    feature: str
    label: str
    importance: float
    direction: str = Field(..., description="'positive' or 'negative'")


class ExplanationResponse(BaseModel):
    home_team: str
    away_team: str
    probability: float
    top_drivers: list[DriverItem]
    top_risks: list[DriverItem]
    narrative: str


class FixtureDetail(BaseModel):
    match_id: str
    season: str | int
    match_date: str
    home_team: str
    away_team: str
    home_score: int | None = None
    away_score: int | None = None
    venue: str | None = None


class StandingsRow(BaseModel):
    position: int
    team: str
    played: int
    wins: int
    draws: int
    losses: int
    goals_for: int
    goals_against: int
    goal_difference: int
    points: int


class DashboardResponse(BaseModel):
    next_fixture: FixtureDetail | None
    win_probability: float | None
    key_drivers: list[DriverItem]
    recent_fixtures: list[FixtureDetail]
    upcoming_fixtures: list[FixtureDetail]
    standings_snapshot: list[StandingsRow]


class ChatRequest(BaseModel):
    query: str = Field(..., min_length=1, description="Tactical query from coaching staff")
    home_team: str | None = None
    away_team: str | None = None


class ChatResponse(BaseModel):
    answer: str
    context: dict | None = None


# --- Auth schemas ---

class RegisterRequest(BaseModel):
    email: str = Field(..., min_length=3, description="User email")
    password: str = Field(..., min_length=8, description="Password (min 8 chars)")
    full_name: str = Field(..., min_length=2, description="User full name / username")
    team_name: str | None = Field(None, description="Selected team (defaults to Universitatea Cluj)")


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str | None = None
    role: str
    team_name: str | None = None
    is_active: bool
    avatar_url: str | None = None


class CognitoRegisterRequest(BaseModel):
    team_name: str | None = Field(None, description="Selected team (defaults to Universitatea Cluj)")
