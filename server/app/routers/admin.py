from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import views
from ..db import get_db, utcnow
from ..models import Announcement, Chat, Message, RefreshToken, User
from ..realtime import hub
from ..security import admin_user, current_user
from .auth import app_settings

router = APIRouter(tags=["admin"])


@router.get("/announcements")
async def announcements(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(select(Announcement).order_by(Announcement.created_at.desc()).limit(50))).all()
    return [views.announcement(a) for a in rows]


@router.get("/admin/stats")
async def stats(admin: User = Depends(admin_user), db: AsyncSession = Depends(get_db)):
    day = utcnow() - timedelta(days=1)
    count = lambda q: db.scalar(select(func.count()).select_from(q))  # noqa: E731
    return {
        "users": await db.scalar(select(func.count()).select_from(User).where(User.is_deleted.is_(False))),
        "active_today": await db.scalar(select(func.count()).select_from(User).where(User.last_seen_at > day)),
        "online": hub.online_count(),
        "chats": await count(Chat),
        "groups": await db.scalar(select(func.count()).select_from(Chat).where(Chat.is_group.is_(True))),
        "messages": await count(Message),
        "messages_today": await db.scalar(select(func.count()).select_from(Message).where(Message.created_at > day)),
    }


@router.get("/admin/users")
async def users(q: str = "", admin: User = Depends(admin_user), db: AsyncSession = Depends(get_db)):
    query = select(User).where(User.is_deleted.is_(False)).order_by(User.created_at.desc()).limit(200)
    text = q.strip().lower()
    if text:
        like = f"%{text}%"
        query = query.where(or_(func.lower(User.name).like(like), User.username.like(like), func.lower(User.email).like(like)))
    return [views.profile(u, with_email=True) for u in (await db.scalars(query)).all()]


class UserUpdate(BaseModel):
    is_disabled: bool | None = None
    is_admin: bool | None = None


@router.patch("/admin/users/{user_id}")
async def update_user(user_id: str, body: UserUpdate, admin: User = Depends(admin_user),
                      db: AsyncSession = Depends(get_db)):
    target = await db.get(User, user_id)
    if target is None or target.is_deleted:
        raise HTTPException(404, "This person doesn't exist.")
    if target.id == admin.id and (body.is_disabled or body.is_admin is False):
        raise HTTPException(400, "You can't turn off or demote your own account.")
    if body.is_admin is not None:
        target.is_admin = body.is_admin
    if body.is_disabled is not None and body.is_disabled != target.is_disabled:
        target.is_disabled = body.is_disabled
        if body.is_disabled:
            target.token_version += 1
            await db.execute(delete(RefreshToken).where(RefreshToken.user_id == target.id))
    await db.commit()
    if target.is_disabled:
        await hub.disconnect_user(target.id)
    return views.profile(target, with_email=True)


class Settings(BaseModel):
    signup_enabled: bool | None = None
    user_limit: int | None = Field(default=None, ge=1, le=10_000_000)
    maintenance_message: str | None = Field(default=None, max_length=500)


def _settings_out(s) -> dict:
    return {"signup_enabled": s.signup_enabled, "user_limit": s.user_limit, "maintenance_message": s.maintenance_message}


@router.get("/admin/settings")
async def get_settings_(admin: User = Depends(admin_user), db: AsyncSession = Depends(get_db)):
    s = await app_settings(db)
    await db.commit()
    return _settings_out(s)


@router.patch("/admin/settings")
async def set_settings(body: Settings, admin: User = Depends(admin_user), db: AsyncSession = Depends(get_db)):
    s = await app_settings(db)
    for key, value in body.model_dump(exclude_none=True).items():
        setattr(s, key, value)
    await db.commit()
    return _settings_out(s)


class NewAnnouncement(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(default="", max_length=5000)
    kind: str = "info"


@router.post("/admin/announcements")
async def announce(body: NewAnnouncement, admin: User = Depends(admin_user), db: AsyncSession = Depends(get_db)):
    if body.kind not in ("info", "warning", "update"):
        raise HTTPException(422, "The kind is info, warning or update.")
    a = Announcement(title=body.title.strip(), body=body.body.strip(), kind=body.kind, created_by=admin.id)
    db.add(a)
    await db.commit()
    everyone = (await db.scalars(select(User.id).where(User.is_deleted.is_(False)))).all()
    await hub.send(everyone, {"type": "announcement", "announcement": views.announcement(a)})
    return views.announcement(a)


class AnnouncementUpdate(BaseModel):
    active: bool


@router.patch("/admin/announcements/{announcement_id}")
async def update_announcement(announcement_id: str, body: AnnouncementUpdate, admin: User = Depends(admin_user),
                              db: AsyncSession = Depends(get_db)):
    a = await db.get(Announcement, announcement_id)
    if a is None:
        raise HTTPException(404, "Not found.")
    a.active = body.active
    await db.commit()
    return views.announcement(a)
