"""Passwords, sign-in tokens and the "who is calling" dependency."""

import hashlib
import secrets
import time
from datetime import timedelta

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .config import get_settings
from .db import get_db, utcnow
from .models import RefreshToken, User

_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode()[:72], bcrypt.gensalt()).decode()


def check_password(password: str, hashed: str | None) -> bool:
    if not hashed:
        return False
    try:
        return bcrypt.checkpw(password.encode()[:72], hashed.encode())
    except ValueError:
        return False


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def access_token(user: User) -> str:
    s = get_settings()
    # time.time() is UTC everywhere (a naive datetime's .timestamp() would
    # read it as the server's local time).
    now = int(time.time())
    return jwt.encode(
        {
            "sub": user.id,
            "tv": user.token_version,
            "iat": now,
            "exp": now + s.access_minutes * 60,
            "typ": "access",
        },
        s.secret_key,
        algorithm="HS256",
    )


def read_access_token(token: str) -> dict:
    try:
        data = jwt.decode(token, get_settings().secret_key, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Your session expired. Sign in again.")
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not signed in.")
    if data.get("typ") != "access":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not signed in.")
    return data


async def new_refresh_token(db: AsyncSession, user: User) -> str:
    token = secrets.token_urlsafe(48)
    db.add(
        RefreshToken(
            id=sha256(token),
            user_id=user.id,
            expires_at=utcnow() + timedelta(days=get_settings().refresh_days),
        )
    )
    return token


async def user_from_token(db: AsyncSession, token: str) -> User:
    data = read_access_token(token)
    user = await db.get(User, data["sub"])
    if user is None or user.is_deleted:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "This account no longer exists.")
    if user.is_disabled:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account was turned off by an admin.")
    if data.get("tv") != user.token_version:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "You were signed out. Sign in again.")
    return user


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not signed in.")
    user = await user_from_token(db, creds.credentials)
    now = utcnow()
    if user.last_seen_at is None or (now - user.last_seen_at).total_seconds() > 60:
        user.last_seen_at = now
        await db.commit()
    return user


async def admin_user(user: User = Depends(current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only admins can do this.")
    return user
