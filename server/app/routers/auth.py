import re
import secrets
import time
from collections import defaultdict, deque
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import mailer, views
from ..config import get_settings
from ..db import get_db, utcnow
from ..models import AppSettings, EmailCode, RefreshToken, User
from ..security import (
    access_token,
    check_password,
    current_user,
    hash_password,
    new_refresh_token,
    sha256,
)

router = APIRouter(prefix="/auth", tags=["auth"])

USERNAME = re.compile(r"^[a-z0-9_.]{3,24}$")

# A few tries a minute per address, against password guessing.
_attempts: dict[str, deque] = defaultdict(deque)


def _limit(key: str, per_minute: int = 8) -> None:
    if not get_settings().rate_limit:
        return
    now = time.monotonic()
    q = _attempts[key]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= per_minute:
        raise HTTPException(429, "Too many tries. Wait a minute and try again.")
    q.append(now)


def clean_username(value: str) -> str:
    u = value.strip().lstrip("@").lower()
    if not USERNAME.match(u):
        raise HTTPException(422, "Usernames are 3 to 24 characters: letters, numbers, _ and .")
    return u


async def username_taken(db: AsyncSession, username: str, except_id: str | None = None) -> bool:
    q = select(User.id).where(User.username == username)
    if except_id:
        q = q.where(User.id != except_id)
    return (await db.scalar(q)) is not None


async def app_settings(db: AsyncSession) -> AppSettings:
    s = await db.get(AppSettings, 1)
    if s is None:
        s = AppSettings(id=1)
        db.add(s)
        await db.flush()
    return s


async def _check_signup_allowed(db: AsyncSession) -> bool:
    """Raises if sign-up is off or full. True if this is the first account."""
    s = await app_settings(db)
    count = await db.scalar(select(func.count()).select_from(User).where(User.is_deleted.is_(False)))
    if count and not s.signup_enabled:
        raise HTTPException(403, "Sign-up is closed on this server right now.")
    if count and count >= s.user_limit:
        raise HTTPException(403, "This server is full. Ask its admin to raise the limit.")
    return not count


async def session(db: AsyncSession, user: User) -> dict:
    refresh = await new_refresh_token(db, user)
    await db.commit()
    return {
        "access_token": access_token(user),
        "refresh_token": refresh,
        "expires_in": get_settings().access_minutes * 60,
        "user": views.profile(user, me=user),
    }


class SignUp(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=200)
    name: str = Field(min_length=1, max_length=80)
    username: str


@router.post("/signup")
async def signup(body: SignUp, request: Request, db: AsyncSession = Depends(get_db)):
    _limit(f"signup:{request.client.host if request.client else ''}", 10)
    email = body.email.lower()
    username = clean_username(body.username)
    if await db.scalar(select(User.id).where(User.email == email)):
        raise HTTPException(409, "There's already an account with this email. Sign in instead.")
    if await username_taken(db, username):
        raise HTTPException(409, "That username is taken. Try another one.")
    first = await _check_signup_allowed(db)
    user = User(
        email=email,
        password_hash=hash_password(body.password),
        name=body.name.strip(),
        username=username,
        is_admin=first or email in get_settings().admin_list,
    )
    db.add(user)
    await db.flush()
    if get_settings().require_email_verification:
        await _send_code(db, email, "verify")
    return await session(db, user)


class Login(BaseModel):
    email: EmailStr
    password: str


@router.post("/login")
async def login(body: Login, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    _limit(f"login:{email}")
    user = await db.scalar(select(User).where(User.email == email, User.is_deleted.is_(False)))
    if user is None or not check_password(body.password, user.password_hash):
        raise HTTPException(401, "Wrong email or password.")
    if user.is_disabled:
        raise HTTPException(403, "This account was turned off by an admin.")
    return await session(db, user)


class Google(BaseModel):
    id_token: str


@router.post("/google")
async def google(body: Google, db: AsyncSession = Depends(get_db)):
    ids = get_settings().google_ids
    if not ids:
        raise HTTPException(400, "Google sign-in isn't set up on this server.")
    from google.auth.transport import requests as grequests
    from google.oauth2 import id_token

    try:
        info = id_token.verify_oauth2_token(body.id_token, grequests.Request(), audience=None)
    except Exception:
        raise HTTPException(401, "Google sign-in didn't work. Try again.")
    if info.get("aud") not in ids or not info.get("email_verified"):
        raise HTTPException(401, "Google sign-in didn't work. Try again.")
    sub = info["sub"]
    email = info["email"].lower()

    user = await db.scalar(select(User).where(User.google_sub == sub))
    if user is None:
        user = await db.scalar(select(User).where(User.email == email, User.is_deleted.is_(False)))
        if user is not None:
            user.google_sub = sub  # link Google to the existing account
            user.email_verified = True
    if user is None:
        first = await _check_signup_allowed(db)
        base = re.sub(r"[^a-z0-9_.]", "", email.split("@")[0].lower())[:18] or "user"
        username = base if len(base) >= 3 else f"{base}_{secrets.token_hex(2)}"
        while await username_taken(db, username):
            username = f"{base[:18]}_{secrets.token_hex(2)}"
        user = User(
            email=email,
            google_sub=sub,
            email_verified=True,
            name=info.get("name") or email.split("@")[0],
            username=username,
            avatar_url=info.get("picture"),
            is_admin=first or email in get_settings().admin_list,
        )
        db.add(user)
        await db.flush()
    if user.is_disabled:
        raise HTTPException(403, "This account was turned off by an admin.")
    return await session(db, user)


class Refresh(BaseModel):
    refresh_token: str


@router.post("/refresh")
async def refresh(body: Refresh, db: AsyncSession = Depends(get_db)):
    row = await db.get(RefreshToken, sha256(body.refresh_token))
    if row is None or row.expires_at < utcnow():
        raise HTTPException(401, "Your session expired. Sign in again.")
    user = await db.get(User, row.user_id)
    await db.delete(row)  # each refresh token works once
    if user is None or user.is_deleted:
        await db.commit()
        raise HTTPException(401, "This account no longer exists.")
    if user.is_disabled:
        await db.commit()
        raise HTTPException(403, "This account was turned off by an admin.")
    return await session(db, user)


@router.post("/logout")
async def logout(body: Refresh, db: AsyncSession = Depends(get_db)):
    await db.execute(delete(RefreshToken).where(RefreshToken.id == sha256(body.refresh_token)))
    await db.commit()
    return {}


async def _send_code(db: AsyncSession, email: str, purpose: str) -> None:
    code = f"{secrets.randbelow(1_000_000):06d}"
    await db.execute(delete(EmailCode).where(EmailCode.email == email, EmailCode.purpose == purpose))
    db.add(EmailCode(email=email, purpose=purpose, code_hash=sha256(code), expires_at=utcnow() + timedelta(minutes=15)))
    await db.commit()
    await mailer.send_code(email, purpose, code)


async def _use_code(db: AsyncSession, email: str, purpose: str, code: str) -> None:
    row = await db.scalar(select(EmailCode).where(EmailCode.email == email, EmailCode.purpose == purpose))
    if row is None or row.expires_at < utcnow():
        raise HTTPException(400, "That code expired. Ask for a new one.")
    if row.attempts >= 5:
        raise HTTPException(429, "Too many wrong codes. Ask for a new one.")
    if row.code_hash != sha256(code.strip()):
        row.attempts += 1
        await db.commit()
        raise HTTPException(400, "That code isn't right.")
    await db.delete(row)


@router.post("/verify/send")
async def verify_send(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    _limit(f"verify:{user.id}", 3)
    if not user.email_verified:
        await _send_code(db, user.email, "verify")
    return {}


class Code(BaseModel):
    code: str


@router.post("/verify")
async def verify(body: Code, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    await _use_code(db, user.email, "verify", body.code)
    user.email_verified = True
    await db.commit()
    return views.profile(user, me=user)


class Forgot(BaseModel):
    email: EmailStr


@router.post("/password/forgot")
async def forgot(body: Forgot, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    _limit(f"forgot:{email}", 3)
    user = await db.scalar(select(User).where(User.email == email, User.is_deleted.is_(False)))
    if user is not None:
        await _send_code(db, email, "reset")
    # Same answer either way, so nobody can test which emails have accounts.
    return {}


class Reset(BaseModel):
    email: EmailStr
    code: str
    password: str = Field(min_length=8, max_length=200)


@router.post("/password/reset")
async def reset(body: Reset, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    _limit(f"reset:{email}")
    await _use_code(db, email, "reset", body.code)
    user = await db.scalar(select(User).where(User.email == email, User.is_deleted.is_(False)))
    if user is None:
        raise HTTPException(400, "That code isn't right.")
    user.password_hash = hash_password(body.password)
    user.email_verified = True
    user.token_version += 1  # sign out everywhere
    await db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    await db.commit()
    return {}


class Change(BaseModel):
    old_password: str = ""
    password: str = Field(min_length=8, max_length=200)


@router.post("/password/change")
async def change(body: Change, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if user.password_hash and not check_password(body.old_password, user.password_hash):
        raise HTTPException(400, "Your current password isn't right.")
    user.password_hash = hash_password(body.password)
    user.token_version += 1
    await db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    return await session(db, user)
