from __future__ import annotations

import secrets

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from db.models import User
from core.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from services.reference_service import get_supported_teams


class AuthService:

    def __init__(self, session: AsyncSession):
        self._session = session

    async def register(self, email: str, password: str, full_name: str, team_name: str | None = None) -> User:
        result = await self._session.execute(select(User).where(User.email == email))
        if result.scalar_one_or_none() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

        clean_team_name = (team_name or "Universitatea Cluj").strip()
        supported_teams = get_supported_teams()
        if supported_teams and clean_team_name not in supported_teams and clean_team_name != "Universitatea Cluj":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid team selection")

        user = User(
            email=email,
            password_hash=hash_password(password),
            full_name=full_name.strip(),
            team_name=clean_team_name,
        )
        self._session.add(user)
        await self._session.commit()
        await self._session.refresh(user)
        return user

    async def login(self, email: str, password: str) -> dict:
        result = await self._session.execute(select(User).where(User.email == email))
        user = result.scalar_one_or_none()

        if user is None or not verify_password(password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is deactivated")

        return {
            "access_token": create_access_token(user.id, user.email, user.role),
            "refresh_token": create_refresh_token(user.id),
            "token_type": "bearer",
        }

    async def refresh(self, refresh_token: str) -> dict:
        payload = decode_token(refresh_token, expected_type="refresh")
        user_id = payload.get("sub")

        result = await self._session.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()

        if user is None or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")

        return {
            "access_token": create_access_token(user.id, user.email, user.role),
            "refresh_token": create_refresh_token(user.id),
            "token_type": "bearer",
        }

    def _tokens_for(self, user: User) -> dict:
        if not user.is_active:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is deactivated")
        return {
            "access_token": create_access_token(user.id, user.email, user.role),
            "refresh_token": create_refresh_token(user.id),
            "token_type": "bearer",
        }

    async def exchange_cognito_id_token(self, id_token: str) -> dict:
        from services.cognito_id_token import verify_id_token

        try:
            claims = verify_id_token(id_token)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Cognito token"
            ) from exc

        sub = claims.get("sub")
        email = (claims.get("email") or "").strip().lower()
        if not sub or not email:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Token missing sub or email")

        r = await self._session.execute(select(User).where(User.cognito_sub == sub))
        user = r.scalar_one_or_none()
        if user is not None:
            return self._tokens_for(user)

        r = await self._session.execute(select(User).where(func.lower(User.email) == email))
        user = r.scalar_one_or_none()
        if user is not None:
            user.cognito_sub = sub
            await self._session.commit()
            await self._session.refresh(user)
            return self._tokens_for(user)

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "NEEDS_REGISTRATION",
                "message": "No account for this sign-in yet.",
            },
        )

    async def register_with_cognito(self, id_token: str, team_name: str | None = None) -> dict:
        from services.cognito_id_token import verify_id_token

        try:
            claims = verify_id_token(id_token)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Cognito token"
            ) from exc

        sub = claims.get("sub")
        email = (claims.get("email") or "").strip()
        if not sub or not email:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Token missing sub or email")

        r = await self._session.execute(select(User).where(User.cognito_sub == sub))
        if r.scalar_one_or_none() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Sign-in already registered")

        r = await self._session.execute(select(User).where(func.lower(User.email) == email.lower()))
        if r.scalar_one_or_none() is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

        clean_team_name = (team_name or "Universitatea Cluj").strip()
        supported_teams = get_supported_teams()
        if supported_teams and clean_team_name not in supported_teams and clean_team_name != "Universitatea Cluj":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid team selection")

        user = User(
            email=email,
            password_hash=hash_password(secrets.token_urlsafe(48)),
            team_name=clean_team_name,
            cognito_sub=sub,
            full_name=claims.get("name"),
        )
        self._session.add(user)
        await self._session.commit()
        await self._session.refresh(user)
        return self._tokens_for(user)
