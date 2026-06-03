from contextlib import asynccontextmanager
import asyncio
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from data.loader import load_all_data, load_stadium_map, load_model_bundle
from db.engine import init_db
from api.v1.router import v1_router
from sportradar.router import router as sr_admin_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    app.state.df = load_all_data(settings.resolved_data_path)
    app.state.stadium_map = load_stadium_map(settings.resolved_stadium_map_path)
    app.state.bundle = load_model_bundle(settings.resolved_model_path)
    from services.xi_service import XiService
    app.state.xi_service = XiService(model_path="ml/xi_model.pkl", data_dir="ml/data/drive_cache")
    # Cold-start strategy. App Runner does zero-downtime deploys: the old
    # instance keeps serving until the new one passes its health check. So we
    # BLOCK on the panel-critical warm (Sportradar fixtures cache + current-week
    # predictions + CatBoost) before the app serves, which means traffic only
    # swaps to the new instance once the dashboard is hot. This removes the
    # window where a freshly deployed 0.5 vCPU instance ran the heavy
    # /week-fixtures compute under the user's request. The blocking warm is
    # bounded and exception-safe, so it can never hang or break boot.
    from app.prewarm import prewarm_critical, prewarm_background
    await prewarm_critical(app.state.df, app.state.stadium_map, app.state.bundle)
    # The heavier XI dataset build (~50-70s on the small instance) stays in the
    # background; the match screen tolerates one cold hit far better than the
    # landing dashboard. Parked on app.state so it is not GC'd mid-flight.
    app.state._prewarm_task = asyncio.create_task(
        prewarm_background(
            app.state.xi_service,
            app.state.df,
            app.state.stadium_map,
        )
    )
    yield


app = FastAPI(
    title="UmbraRo API",
    description="Tactical intelligence backend for UmbraRo",
    version="0.1.0",
    lifespan=lifespan,
)

origins = [
    "http://localhost:52757",
    "http://127.0.0.1:8000",
]

_extra_origins = [o.strip() for o in os.environ.get("EXTRA_CORS_ORIGINS", "").split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://localhost:3000",
        "http://127.0.0.1:8080",
        *_extra_origins,
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

app.include_router(v1_router, prefix="/api/v1")
app.include_router(sr_admin_router, prefix="/api/v1")







