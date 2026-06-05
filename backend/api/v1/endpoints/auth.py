from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.models import (
    RegisterRequest,
    LoginRequest,
    RefreshRequest,
    TokenResponse,
    UserResponse,
    CognitoRegisterRequest,
)
from core.security import get_current_user
from db.engine import async_session as session_factory
from db.models import User
from services import avatar_service
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
    body: CognitoRegisterRequest,
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


class UpdateMeRequest(BaseModel):
    full_name: str


@router.post("/me", response_model=UserResponse)
async def update_me(
    body: UpdateMeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(_get_db),
):
    """Update the signed-in user's display name."""
    name = (body.full_name or "").strip()
    result = await db.execute(select(User).where(User.id == current_user.id))
    user = result.scalar_one()
    if name:
        user.full_name = name
        await db.commit()
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        team_name=user.team_name,
        is_active=user.is_active,
        avatar_url=user.avatar_url,
    )


class AvatarUploadUrlResponse(BaseModel):
    uploadUrl: str
    avatarUrl: str


@router.post("/me/avatar-upload-url", response_model=AvatarUploadUrlResponse)
async def avatar_upload_url(current_user: User = Depends(get_current_user)):
    """Hand the client a presigned S3 PUT URL for its own avatar object.

    The browser PUTs the raw JPEG bytes straight to ``uploadUrl`` (Content-Type
    image/jpeg), then calls PUT /auth/me/avatar with ``avatarUrl`` to persist it.
    The S3 key is stable (avatars/<user_id>.jpg, overwrite-in-place); ``avatarUrl``
    carries a ?v=<ts> cache-buster so clients refetch the new image.
    """
    return AvatarUploadUrlResponse(
        uploadUrl=avatar_service.generate_presigned_put_url(current_user.id),
        avatarUrl=avatar_service.public_avatar_url(current_user.id),
    )


class UpdateAvatarRequest(BaseModel):
    avatar_url: str


@router.put("/me/avatar", response_model=UserResponse)
async def update_avatar(
    body: UpdateAvatarRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(_get_db),
):
    """Persist an already-uploaded avatar URL.

    No file is written: the bytes already live in S3 (uploaded directly by the
    browser via the presigned PUT URL). This only records the public URL on the
    user row so it is returned by GET /auth/me and shown in chat.
    """
    url = (body.avatar_url or "").strip()
    if not url:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="avatar_url is required")

    result = await db.execute(select(User).where(User.id == current_user.id))
    user = result.scalar_one()
    user.avatar_url = url
    await db.commit()

    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role,
        team_name=user.team_name,
        is_active=user.is_active,
        avatar_url=user.avatar_url,
    )


@router.get("/teams", response_model=list[str])
async def list_teams():
    return sorted(get_supported_teams())
