from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import chat_logic, views
from ..db import get_db, utcnow
from ..models import Chat, Message, User
from ..realtime import hub
from ..security import current_user

router = APIRouter(prefix="/messages", tags=["messages"])


async def _load(db: AsyncSession, message_id: str, user: User):
    m = await db.scalar(select(Message).where(Message.id == message_id))
    if m is None:
        raise HTTPException(404, "This message doesn't exist.")
    chat, member = await chat_logic.membership(db, m.chat_id, user)
    if m.seq <= member.hidden_seq:
        raise HTTPException(404, "This message doesn't exist.")
    return m, chat, member


async def _changed(db: AsyncSession, chat: Chat, m: Message) -> dict:
    await db.commit()
    out = views.message(m)
    await hub.send(await chat_logic.member_ids(db, chat.id), {"type": "message.updated", "chat_id": chat.id, "message": out})
    return out


class Edit(BaseModel):
    body: str = Field(min_length=1, max_length=20000)


@router.patch("/{message_id}")
async def edit(message_id: str, body: Edit, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    m, chat, _ = await _load(db, message_id, user)
    if m.sender_id != user.id:
        raise HTTPException(403, "You can only edit your own messages.")
    if m.deleted_at is not None:
        raise HTTPException(400, "This message was deleted.")
    if m.kind not in ("text", "image"):
        raise HTTPException(400, "Only text and captions can be edited.")
    if body.body.strip() == m.body.strip():
        return views.message(m)
    m.body = body.body
    m.edited_at = utcnow()
    return await _changed(db, chat, m)


@router.delete("/{message_id}")
async def delete(message_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    m, chat, member = await _load(db, message_id, user)
    if m.sender_id != user.id and not (chat.is_group and member.role == "admin"):
        raise HTTPException(403, "You can only delete your own messages.")
    if m.kind == "system":
        raise HTTPException(400, "That can't be deleted.")
    if m.deleted_at is None:
        m.deleted_at = utcnow()
        m.body = ""
        m.payload = None
        m.reactions = {}
        m.pinned_at = None
    return await _changed(db, chat, m)


class Pin(BaseModel):
    pinned: bool


@router.put("/{message_id}/pin")
async def pin(message_id: str, body: Pin, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    m, chat, member = await _load(db, message_id, user)
    if chat.is_group and member.role != "admin":
        raise HTTPException(403, "Only group admins can pin messages.")
    if m.deleted_at is not None or m.kind == "system":
        raise HTTPException(400, "That message can't be pinned.")
    m.pinned_at = utcnow() if body.pinned else None
    return await _changed(db, chat, m)


class React(BaseModel):
    emoji: str = Field(min_length=1, max_length=16)


@router.put("/{message_id}/reaction")
async def react(message_id: str, body: React, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    m, chat, _ = await _load(db, message_id, user)
    if m.deleted_at is not None or m.kind == "system":
        raise HTTPException(400, "You can't react to that.")
    reactions = dict(m.reactions or {})
    reactions[user.id] = body.emoji
    m.reactions = reactions  # a new dict, so the change is saved
    return await _changed(db, chat, m)


@router.delete("/{message_id}/reaction")
async def unreact(message_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    m, chat, _ = await _load(db, message_id, user)
    reactions = dict(m.reactions or {})
    reactions.pop(user.id, None)
    m.reactions = reactions
    return await _changed(db, chat, m)
