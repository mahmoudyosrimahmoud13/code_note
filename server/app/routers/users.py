from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import chat_logic, views
from ..db import get_db
from ..models import Block, Chat, ChatMember, DeviceToken, RefreshToken, SyncedItem, User
from ..realtime import hub
from ..security import current_user
from .auth import clean_username, username_taken

router = APIRouter(tags=["users"])


@router.get("/me")
async def me(user: User = Depends(current_user)):
    return views.profile(user, me=user)


class MeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    username: str | None = None
    about: str | None = Field(default=None, max_length=300)
    avatar_url: str | None = Field(default=None, max_length=1000)


@router.patch("/me")
async def update_me(body: MeUpdate, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if body.username is not None:
        u = clean_username(body.username)
        if await username_taken(db, u, except_id=user.id):
            raise HTTPException(409, "That username is taken. Try another one.")
        user.username = u
    if body.name is not None:
        user.name = body.name.strip()
    if body.about is not None:
        user.about = body.about.strip()
    if body.avatar_url is not None:
        user.avatar_url = body.avatar_url or None
    await db.commit()
    # People who chat with me see the new name and picture.
    chat_ids = (await db.scalars(select(ChatMember.chat_id).where(ChatMember.user_id == user.id))).all()
    for cid in chat_ids:
        await chat_logic.chat_changed(db, cid)
    return views.profile(user, me=user)


@router.delete("/me")
async def delete_me(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """Deletes the account. Messages stay in other people's chats, from
    "Deleted account"; groups lose this person; notes in the cloud go."""
    groups = (await db.scalars(
        select(Chat).join(ChatMember, ChatMember.chat_id == Chat.id)
        .where(ChatMember.user_id == user.id, Chat.is_group.is_(True))
    )).all()
    for chat in groups:
        await chat_logic.remove_member(db, chat, user, user)
    await db.execute(delete(SyncedItem).where(SyncedItem.owner_id == user.id))
    await db.execute(delete(DeviceToken).where(DeviceToken.user_id == user.id))
    await db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
    await db.execute(delete(Block).where(or_(Block.blocker_id == user.id, Block.blocked_id == user.id)))
    user.is_deleted = True
    user.email = f"deleted-{user.id}@deleted.invalid"
    user.username = None
    user.name = "Deleted account"
    user.avatar_url = None
    user.about = ""
    user.password_hash = None
    user.google_sub = None
    user.token_version += 1
    await db.commit()
    await hub.disconnect_user(user.id)
    return {}


@router.get("/users/username-available")
async def username_available(username: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    try:
        u = clean_username(username)
    except HTTPException:
        return {"available": False}
    return {"available": not await username_taken(db, u, except_id=user.id)}


@router.get("/users/username-free")
async def username_free(username: str, db: AsyncSession = Depends(get_db)):
    """For the sign-up screen, before there's an account."""
    try:
        u = clean_username(username)
    except HTTPException:
        return {"available": False}
    return {"available": not await username_taken(db, u)}


async def _blocked_ids(db: AsyncSession, me: User) -> set[str]:
    rows = (await db.execute(
        select(Block.blocker_id, Block.blocked_id).where(or_(Block.blocker_id == me.id, Block.blocked_id == me.id))
    )).all()
    return {b if a == me.id else a for a, b in rows}


@router.get("/users/search")
async def search(q: str = "", user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    text = q.strip().lstrip("@").lower()
    if len(text) < 2:
        return []
    like = f"%{text}%"
    rows = (await db.scalars(
        select(User).where(
            User.id != user.id,
            User.is_deleted.is_(False),
            User.is_disabled.is_(False),
            or_(func.lower(User.name).like(like), User.username.like(like), func.lower(User.email) == text),
        ).order_by(User.username).limit(30)
    )).all()
    hide = await _blocked_ids(db, user)
    # Exact username matches first.
    rows = sorted((u for u in rows if u.id not in hide), key=lambda u: (u.username != text, not (u.username or "").startswith(text)))
    return [views.profile(u, me=user) for u in rows]


@router.get("/users/{user_id}")
async def get_user(user_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    other = await db.get(User, user_id)
    if other is None:
        raise HTTPException(404, "This person doesn't exist.")
    out = views.profile(other, me=user)
    out["blocked_by_me"] = (await db.get(Block, (user.id, other.id))) is not None
    mine = select(ChatMember.chat_id).where(ChatMember.user_id == user.id)
    common = (await db.execute(
        select(Chat.id, Chat.name, Chat.image_url)
        .join(ChatMember, and_(ChatMember.chat_id == Chat.id, ChatMember.user_id == other.id))
        .where(Chat.is_group.is_(True), Chat.id.in_(mine))
    )).all()
    out["common_groups"] = [{"id": i, "name": n, "image_url": img} for i, n, img in common]
    return out


@router.get("/me/blocks")
async def my_blocks(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(
        select(User).join(Block, Block.blocked_id == User.id).where(Block.blocker_id == user.id)
    )).all()
    return [views.profile(u, me=user) for u in rows]


async def _direct_chat_id(db: AsyncSession, a: str, b: str) -> str | None:
    key = ":".join(sorted([a, b]))
    return await db.scalar(select(Chat.id).where(Chat.dm_key == key))


@router.put("/users/{user_id}/block")
async def block(user_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if user_id == user.id:
        raise HTTPException(400, "You can't block yourself.")
    if await db.get(User, user_id) is None:
        raise HTTPException(404, "This person doesn't exist.")
    if await db.get(Block, (user.id, user_id)) is None:
        db.add(Block(blocker_id=user.id, blocked_id=user_id))
        await db.commit()
    chat_id = await _direct_chat_id(db, user.id, user_id)
    if chat_id:
        await chat_logic.chat_changed(db, chat_id)
    return {}


@router.delete("/users/{user_id}/block")
async def unblock(user_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    row = await db.get(Block, (user.id, user_id))
    if row is not None:
        await db.delete(row)
        await db.commit()
    chat_id = await _direct_chat_id(db, user.id, user_id)
    if chat_id:
        await chat_logic.chat_changed(db, chat_id)
    return {}
