import os
import shutil
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.models import (
    RegisterRequest,
    LoginRequest,
    RefreshRequest,
    TokenResponse,
    UserResponse,
    FirebaseRegisterRequest,
)
from core.security import get_current_user
from db.engine import async_session as session_factory
from db.models import User
from services.auth_service import AuthService
from services.reference_service import get_supported_teams

router = APIRouter(prefix="/auth", tags=["auth"])


async def _get_db():
    async with session_factory() as session:
        yield session


@router.post("/register", response_model=UserResponse, status_code=201)
async def register(body: RegisterRequest, db: AsyncSession = Depends(_get_db)):
    svc = AuthService(db)
    user = await svc.register(body.email, body.password, body.full_name, body.team_name)
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        team_name=user.team_name,
        is_active=user.is_active,
    )


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(_get_db)):
    svc = AuthService(db)
    tokens = await svc.login(body.email, body.password)
    return TokenResponse(**tokens)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(body: RefreshRequest, db: AsyncSession = Depends(_get_db)):
    svc = AuthService(db)
    tokens = await svc.refresh(body.refresh_token)
    return TokenResponse(**tokens)


def _bearer_id_token(request: Request) -> str:
    h = request.headers.get("Authorization") or request.headers.get("authorization")
    if not h or not h.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization bearer")
    return h[7:].strip()


@router.post("/cognito", response_model=TokenResponse)
async def auth_cognito(request: Request, db: AsyncSession = Depends(_get_db)):
    id_token = _bearer_id_token(request)
    svc = AuthService(db)
    try:
        tokens = await svc.exchange_cognito_id_token(id_token)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cognito not configured (set COGNITO_USER_POOL_ID)",
        ) from e
    return TokenResponse(**tokens)


@router.post("/register_with_cognito", response_model=TokenResponse)
async def register_with_cognito(
    request: Request,
    body: FirebaseRegisterRequest,
    db: AsyncSession = Depends(_get_db),
):
    id_token = _bearer_id_token(request)
    svc = AuthService(db)
    try:
        tokens = await svc.register_with_cognito(id_token, body.team_name)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Cognito not configured (set COGNITO_USER_POOL_ID)",
        ) from e
    return TokenResponse(**tokens)


@router.get("/me", response_model=UserResponse)
async def me(user: User = Depends(get_current_user)):
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        team_name=user.team_name,
        is_active=user.is_active,
        avatar_url=user.avatar_url,
    )


_UPLOAD_DIR = "uploads"
os.makedirs(_UPLOAD_DIR, exist_ok=True)


@router.put("/me/avatar")
async def update_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(_get_db),
):
    file_id = str(uuid.uuid4())
    ext = os.path.splitext(file.filename or "")[1]
    filename = f"{file_id}{ext}"
    file_path = os.path.join(_UPLOAD_DIR, filename)

    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    result = await db.execute(select(User).where(User.id == current_user.id))
    user = result.scalar_one()
    user.avatar_url = f"/uploads/{filename}"
    await db.commit()

    return {"avatar_url": f"/uploads/{filename}"}


@router.get("/teams", response_model=list[str])
async def list_teams():
    return sorted(get_supported_teams())
