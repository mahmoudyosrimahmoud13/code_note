"""Notes sync. Each device sends what changed and asks for what changed
since the last revision it saw. The newest change wins, by the time it was
made on the device (the note's lastModified, or when it was deleted)."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import views
from ..db import get_db, utcnow
from ..models import DeviceToken, SyncedItem, User
from ..realtime import hub
from ..security import current_user

router = APIRouter(tags=["sync"])


def _when(item: "Item") -> datetime:
    raw = item.modified_at or (item.data or {}).get("lastModified")
    if raw:
        try:
            dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
            if dt.tzinfo is not None:
                dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
            return dt
        except ValueError:
            pass
    return utcnow()


@router.get("/sync")
async def pull(since: int = 0, limit: int = 500, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(
        select(SyncedItem).where(SyncedItem.owner_id == user.id, SyncedItem.rev > since)
        .order_by(SyncedItem.rev).limit(max(1, min(limit, 1000)))
    )).all()
    return {
        "rev": rows[-1].rev if rows else max(since, 0),
        "latest": user.sync_rev,
        "items": [views.synced(r) for r in rows],
    }


class Item(BaseModel):
    kind: str
    id: str = Field(min_length=1, max_length=64)
    data: dict | None = None
    deleted: bool = False
    # When it changed on the device; defaults to data.lastModified.
    modified_at: str | None = None


class Push(BaseModel):
    items: list[Item] = Field(max_length=500)


@router.post("/sync")
async def push(body: Push, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    # Lock this account's row so two devices pushing at once get separate
    # revisions (Postgres; SQLite writes one at a time anyway).
    locked = await db.scalar(select(User).where(User.id == user.id).with_for_update())
    applied, conflicts = [], []
    for item in body.items:
        if item.kind not in ("note", "group"):
            raise HTTPException(422, "Unknown item kind.")
        if not item.deleted and item.data is None:
            raise HTTPException(422, "The note is missing.")
        if item.data is not None and len(str(item.data)) > 2_000_000:
            raise HTTPException(413, "A note is too big to sync (2 MB at most).")
        when = _when(item)
        row = await db.get(SyncedItem, (user.id, item.kind, item.id))
        if row is not None and row.modified_at > when:
            conflicts.append(views.synced(row))  # the cloud copy is newer: keep it
            continue
        locked.sync_rev += 1
        if row is None:
            row = SyncedItem(owner_id=user.id, kind=item.kind, item_id=item.id)
            db.add(row)
        row.data = None if item.deleted else item.data
        row.deleted = item.deleted
        row.modified_at = when
        row.rev = locked.sync_rev
        row.updated_at = utcnow()
        applied.append(item.id)
    await db.commit()
    if applied:
        await hub.send([user.id], {"type": "sync", "rev": locked.sync_rev})
    return {"rev": locked.sync_rev, "applied": applied, "conflicts": conflicts}


class Device(BaseModel):
    token: str = Field(min_length=10, max_length=512)
    platform: str = "android"


@router.post("/devices")
async def add_device(body: Device, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    row = await db.get(DeviceToken, body.token)
    if row is None:
        db.add(DeviceToken(token=body.token, user_id=user.id, platform=body.platform))
    else:
        row.user_id = user.id  # the phone changed accounts
        row.platform = body.platform
        row.updated_at = utcnow()
    await db.commit()
    return {}


@router.delete("/devices")
async def remove_device(body: Device, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    row = await db.get(DeviceToken, body.token)
    if row is not None and row.user_id == user.id:
        await db.delete(row)
        await db.commit()
    return {}
