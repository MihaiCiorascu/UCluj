from contextlib import asynccontextmanager
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://mortgages-treaty-trinity-rely.trycloudflare.com",
        "https://feeling-avoiding-attribute-lisa.trycloudflare.com",
        "https://raleigh-science-edwards-illustrated.trycloudflare.com",
        "https://hospitality-maintenance-alias-perl.trycloudflare.com",
        "https://environments-internal-hudson-analytical.trycloudflare.com",
        "https://holidays-isbn-hybrid-unified.trycloudflare.com",
        "https://becomes-exercises-stick-textbooks.trycloudflare.com",
        "https://uhack26-8050e.web.app",
        "https://hackatonu.web.app",
        "https://modifications-upon-gravity-nursery.trycloudflare.com",
        "https://jpeg-inf-statistical-argument.trycloudflare.com",
        "https://offices-family-resume-crest.trycloudflare.com",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("uploads", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

app.include_router(v1_router, prefix="/api/v1")
app.include_router(sr_admin_router, prefix="/api/v1")







