from pathlib import Path

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    umbraro_env: str = "development"
    data_path: str = "../data/All_Data.csv"
    stadium_map_path: str = "../data/reference/team_stadium_map.csv"
    model_bundle_path: str = "ml/umbraro_catboost_bundle.joblib"
    tracked_team: str = "UMBRARO"
    cors_origins: str = "http://localhost:3000,http://localhost:8080,http://localhost:5555"
    database_url: str = "sqlite+aiosqlite:///./umbraro.db"
    jwt_secret: str = "CHANGE-ME-IN-PRODUCTION"
    jwt_access_minutes: int = 15
    jwt_refresh_days: int = 7
    sportradar_api_key: str = ""
    sportradar_base_url: str = "https://api.sportradar.com/soccer/trial/v4/en"
    sportradar_rate_delay: float = 0.5
    firebase_project_id: str = ""
    firebase_credentials_path: str = ""

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
