"""Read-only meta endpoint.

Exposes server-side configuration that the Flutter client needs to know about
at startup, in particular whether the backend is running in demo mode and, if
so, which date it is pretending is "today". The client uses this to render a
"DEMO MODE - fixtures from <date>" ribbon so the committee can see at a glance
that the dashboard is showing a curated historical slice rather than live data.

No authentication: the meta payload is harmless and is needed before login.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.config import settings

router = APIRouter()


@router.get("/meta")
def meta() -> dict:
    return {
        "demo_mode": settings.demo_mode,
        "demo_today": settings.demo_today if settings.demo_mode else "",
        "environment": settings.umbraro_env,
    }
