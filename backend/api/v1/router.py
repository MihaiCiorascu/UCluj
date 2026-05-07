from fastapi import APIRouter

from api.v1.endpoints import auth, health, predict, optimize, explain, dashboard, fixtures, standings, chat, ws_chat, xi, week, match_details, admin_diag

v1_router = APIRouter()

v1_router.include_router(auth.router)
v1_router.include_router(health.router, tags=["health"])
v1_router.include_router(predict.router, tags=["predict"])
v1_router.include_router(optimize.router, tags=["optimize"])
v1_router.include_router(explain.router, tags=["explain"])
v1_router.include_router(dashboard.router, tags=["dashboard"])
v1_router.include_router(fixtures.router, tags=["fixtures"])
v1_router.include_router(standings.router, tags=["standings"])
v1_router.include_router(chat.router, tags=["chat"])
v1_router.include_router(ws_chat.router, tags=["ws_chat"])
v1_router.include_router(xi.router, tags=["xi"], prefix="/xi")
v1_router.include_router(week.router, tags=["week"])
v1_router.include_router(match_details.router, tags=["match_details"])
v1_router.include_router(admin_diag.router)
