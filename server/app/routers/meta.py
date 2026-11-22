from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import views
from ..config import VERSION, get_settings
from ..db import get_db
from ..models import Announcement
from .auth import app_settings

router = APIRouter(tags=["meta"])


@router.get("/health")
async def health():
    """The app calls this when you type the server address, to check it's
    really a CodeNote server."""
    return {"app": "codenote", "version": VERSION, "name": get_settings().server_name}


@router.get("/config")
async def config(db: AsyncSession = Depends(get_db)):
    s = await app_settings(db)
    await db.commit()
    latest = await db.scalar(
        select(Announcement).where(Announcement.active.is_(True)).order_by(Announcement.created_at.desc()).limit(1)
    )
    return {
        "name": get_settings().server_name,
        "signup_enabled": s.signup_enabled,
        "maintenance_message": s.maintenance_message,
        "google_client_ids": get_settings().google_ids,
        "email_verification": get_settings().require_email_verification,
        "announcement": views.announcement(latest) if latest else None,
    }
