from datetime import date, datetime, time, timezone
from pathlib import Path

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    umbraro_env: str = "development"
    data_path: str = "../data/All_Data.csv"
    stadium_map_path: str = "../data/reference/team_stadium_map.csv"
    model_bundle_path: str = "ml/umbraro_catboost_bundle.joblib"
    tracked_team: str = "UMBRARO"
    cors_origins: str = "http://localhost:3000,http://localhost:8080,http://localhost:5555"
    database_url: str = "postgresql+asyncpg://postgres:password@localhost:5432/ucluj"
    jwt_secret: str = "CHANGE-ME-IN-PRODUCTION"
    jwt_access_minutes: int = 15
    jwt_refresh_days: int = 7
    sportradar_api_key: str = ""
    sportradar_base_url: str = "https://api.sportradar.com/soccer/trial/v4/en"
    sportradar_rate_delay: float = 0.5
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""
    cognito_region: str = "eu-central-1"

    # --- Avatars (Part B): S3 presigned-upload storage ---
    # Provisioned by infra/template.yaml. Env vars (App Runner): AVATARS_S3_BUCKET,
    # AVATARS_S3_REGION. The backend signs a presigned PUT against this bucket for
    # key avatars/<user_id>.jpg and builds the public URL
    # https://<bucket>.s3.<region>.amazonaws.com/avatars/<user_id>.jpg.
    avatars_s3_bucket: str = "ucluj-user-avatars"
    avatars_s3_region: str = "eu-central-1"

    # --- Instant chat (Part C): API Gateway WebSocket fan-out ---
    # Provisioned by infra/template.yaml. Env vars (App Runner):
    # WS_API_MANAGEMENT_ENDPOINT, WS_CONNECTIONS_TABLE. FastAPI persists a message
    # to RDS, then Queries the DynamoDB channel-index for live connectionIds and
    # fans the message out via the API Gateway Management API post_to_connection.
    # When ws_api_management_endpoint is empty, fan-out is skipped (history-only),
    # so local development without the infra still works.
    ws_api_management_endpoint: str = ""
    ws_connections_table: str = "umbraro-ws-connections"

    # Demo mode for the committee presentation.
    # The Romanian Superliga 2024-2025 season is over and Sportradar trial
    # returns no current fixtures, so the live dashboard would be empty. When
    # demo_mode is on, the backend pretends "now" is demo_today (ISO date,
    # interpreted at noon UTC) so the week-fixtures, standings, dashboard, and
    # XI flows all light up against the CSV-backed 2024-2025 data. The live
    # Sportradar fetch and its caches are bypassed in demo mode.
    demo_mode: bool = False
    demo_today: str = ""

    # Iter-Q.3 follow-up: optimizer configurability.
    # method: "mc" (production default, robust; always returns an in-distribution candidate)
    #         "trust_constr" (opt-in; scipy interior-point per Byrd, Hribar & Nocedal 1999;
    #                         ~4x fewer CatBoost evaluations in the convergent case; falls
    #                         back to MC on failure so the coach never sees an error)
    # seed: reproducibility for the MC sampler (Pineau et al. 2021).
    # num_simulations: the thesis production value is N = 25,000, which keeps
    # the standard deviation of the returned best probability below 0.002
    # while staying sub-second per fixture after vectorisation. This is the
    # single source of truth for N across the prescription and optimizer
    # services; keep the Flutter footer string in sync with it.
    optimizer_method: str = "mc"
    optimizer_seed: int = 42
    optimizer_num_simulations: int = 25000

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def resolved_data_path(self) -> Path:
        return (Path(__file__).parent.parent / self.data_path).resolve()

    @property
    def resolved_stadium_map_path(self) -> Path:
        return (Path(__file__).parent.parent / self.stadium_map_path).resolve()

    @property
    def resolved_model_path(self) -> Path:
        return (Path(__file__).parent.parent / self.model_bundle_path).resolve()

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()


def _parse_demo_today(value: str) -> date:
    """Parse the DEMO_TODAY env var into a date. Raises ValueError if invalid."""
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            "DEMO_MODE is enabled but DEMO_TODAY is missing or not an ISO date "
            f"(YYYY-MM-DD). Got: {value!r}"
        ) from exc


# Fail fast at import time if the demo-mode configuration is incoherent.
if settings.demo_mode:
    _parse_demo_today(settings.demo_today)


# Sportradar season IDs for the Romanian Superliga (`sr:competition:152`).
# Discovered via `GET /competitions/sr:competition:152/seasons.json`. The live
# constant is the active season at deploy time; the demo constant is the
# 2024-25 season that the dataset and the Wyscout XI predictor are anchored
# to. When DEMO_MODE flips, the standings and week-fixture endpoints pivot
# off ``effective_season_id()`` so Sportradar gets pinned to the right season.
_LIVE_SEASON_ID = "sr:season:131507"   # Superliga 25/26
# The demo now mirrors 2025-26, the season the Wyscout XI roster and the
# drive_cache match data actually belong to (verified: the roster includes
# players only at their clubs since 2025-26, e.g. Coubis at U Cluj). Pinning
# the demo here makes fixtures, standings, the recommended XI, stats, and
# photos one coherent season instead of 2025-26 rosters over 2024-25 fixtures.
_DEMO_SEASON_ID = "sr:season:131507"   # Superliga 25/26


def effective_season_id() -> str:
    """Return the Sportradar season ID the backend should query.

    In demo mode every season-pinned Sportradar call points at the 2024-25
    season, which matches the dataset and the demo date the committee will
    see. In production the call hits the current 25/26 season.
    """
    return _DEMO_SEASON_ID if settings.demo_mode else _LIVE_SEASON_ID


def effective_season() -> str:
    """Return the SuperLiga season label that contains ``effective_now()``.

    The Romanian Superliga calendar runs July to May, so a fixture date in
    months 7-12 belongs to the season labelled ``<year>`` and a date in
    months 1-6 belongs to ``<year - 1>``. This convention matches the
    ``season`` column in ``data/All_Data.csv`` where 2024-25 fixtures are
    tagged ``"2024"``.

    The Sportradar standings endpoint implicitly returns "current season"
    relative to the wall clock; this helper gives every CSV-backed standings
    or per-season query the same anchor when ``DEMO_MODE`` is on.
    """
    now = effective_now()
    return str(now.year if now.month >= 7 else now.year - 1)


def effective_now() -> datetime:
    """Return the server's effective notion of "now".

    Returns ``datetime.now(timezone.utc)`` normally. When ``DEMO_MODE`` is on,
    returns ``demo_today`` at 12:00 UTC so all week-window and "upcoming" math
    pivots around the committee-demo date instead of the wall clock. This is
    a deliberate scope: cache TTLs, JWT expiry, and database timestamps still
    use real time so the harness stays honest about its own state.
    """
    if settings.demo_mode:
        return datetime.combine(
            _parse_demo_today(settings.demo_today),
            time(12, 0),
            tzinfo=timezone.utc,
        )
    return datetime.now(timezone.utc)
