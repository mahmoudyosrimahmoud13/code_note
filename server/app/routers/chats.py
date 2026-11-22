from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import chat_logic, views
from ..db import get_db
from ..models import Chat, ChatMember, Message, User
from ..realtime import hub
from ..security import current_user

router = APIRouter(prefix="/chats", tags=["chats"])


@router.get("")
async def list_chats(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    return await views.chat_summaries(db, user)


class Direct(BaseModel):
    user_id: str


@router.post("/direct")
async def direct(body: Direct, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if body.user_id == user.id:
        raise HTTPException(400, "You can't start a chat with yourself.")
    other = await db.get(User, body.user_id)
    if other is None or other.is_deleted or other.is_disabled:
        raise HTTPException(404, "This person isn't available.")
    key = ":".join(sorted([user.id, other.id]))
    chat = await db.scalar(select(Chat).where(Chat.dm_key == key))
    if chat is None:
        blocked = await chat_logic.blocked_between(db, user.id, other.id)
        if blocked == "me":
            raise HTTPException(403, "You blocked this person. Unblock them to chat.")
        if blocked == "them":
            raise HTTPException(403, "You can't message this person.")
        chat = Chat(is_group=False, dm_key=key, created_by=user.id)
        db.add(chat)
        await db.flush()
        db.add_all([ChatMember(chat_id=chat.id, user_id=user.id), ChatMember(chat_id=chat.id, user_id=other.id)])
        await db.commit()
    return await views.chat_details(db, user, chat.id)


class NewGroup(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: str = Field(default="", max_length=500)
    image_url: str | None = None
    member_ids: list[str] = []
    admin_only: bool = False


@router.post("/groups")
async def new_group(body: NewGroup, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    chat = Chat(is_group=True, name=body.name.strip(), description=body.description.strip(),
                image_url=body.image_url, admin_only=body.admin_only, created_by=user.id)
    db.add(chat)
    await db.flush()
    db.add(ChatMember(chat_id=chat.id, user_id=user.id, role="admin"))
    ids = [i for i in dict.fromkeys(body.member_ids) if i != user.id]
    people = (await db.scalars(
        select(User).where(User.id.in_(ids), User.is_deleted.is_(False), User.is_disabled.is_(False))
    )).all() if ids else []
    for p in people:
        db.add(ChatMember(chat_id=chat.id, user_id=p.id))
    await db.commit()
    await chat_logic.system(db, chat, user, "created", name=chat.name)
    await chat_logic.chat_changed(db, chat.id)
    return await views.chat_details(db, user, chat.id)


@router.get("/{chat_id}")
async def get_chat(chat_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    await chat_logic.membership(db, chat_id, user)
    return await views.chat_details(db, user, chat_id)


class ChatUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=500)
    image_url: str | None = None
    admin_only: bool | None = None


@router.patch("/{chat_id}")
async def update_chat(chat_id: str, body: ChatUpdate, user: User = Depends(current_user),
                      db: AsyncSession = Depends(get_db)):
    chat, member = await chat_logic.membership(db, chat_id, user)
    chat_logic.require_admin(chat, member)
    renamed = body.name is not None and body.name.strip() != chat.name
    if body.name is not None:
        chat.name = body.name.strip()
    if body.description is not None:
        chat.description = body.description.strip()
    if body.image_url is not None:
        chat.image_url = body.image_url or None
    if body.admin_only is not None:
        chat.admin_only = body.admin_only
    await db.commit()
    if renamed:
        await chat_logic.system(db, chat, user, "renamed", name=chat.name)
    await chat_logic.chat_changed(db, chat.id)
    return await views.chat_details(db, user, chat.id)


@router.delete("/{chat_id}")
async def delete_chat(chat_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """Groups: an admin deletes it for everyone. Direct chats: hidden for
    me with its history; a new message brings it back, empty."""
    chat, member = await chat_logic.membership(db, chat_id, user)
    if chat.is_group:
        chat_logic.require_admin(chat, member)
        ids = await chat_logic.member_ids(db, chat.id)
        await db.delete(chat)
        await db.commit()
        await hub.send(ids, {"type": "chat.removed", "chat_id": chat_id})
        return {}
    member.hidden = True
    member.hidden_seq = chat.last_message_seq or 0
    member.read_seq = max(member.read_seq, member.hidden_seq)
    await db.commit()
    await hub.send([user.id], {"type": "chat.removed", "chat_id": chat_id})
    return {}


class AddMembers(BaseModel):
    user_ids: list[str]


@router.post("/{chat_id}/members")
async def add_members(chat_id: str, body: AddMembers, user: User = Depends(current_user),
                      db: AsyncSession = Depends(get_db)):
    chat, member = await chat_logic.membership(db, chat_id, user)
    chat_logic.require_admin(chat, member)
    current = set(await chat_logic.member_ids(db, chat.id))
    people = (await db.scalars(
        select(User).where(User.id.in_(body.user_ids), User.is_deleted.is_(False), User.is_disabled.is_(False))
    )).all()
    added = [p for p in people if p.id not in current]
    # New members start after the current last message: they don't get
    # the old history pushed at them as unread.
    start = chat.last_message_seq or 0
    for p in added:
        db.add(ChatMember(chat_id=chat.id, user_id=p.id, read_seq=start, delivered_seq=start))
    await db.commit()
    for p in added:
        await chat_logic.system(db, chat, user, "added", p)
    await chat_logic.chat_changed(db, chat.id)
    return await views.chat_details(db, user, chat.id)


class Role(BaseModel):
    role: str


@router.patch("/{chat_id}/members/{user_id}")
async def set_role(chat_id: str, user_id: str, body: Role, user: User = Depends(current_user),
                   db: AsyncSession = Depends(get_db)):
    chat, member = await chat_logic.membership(db, chat_id, user)
    chat_logic.require_admin(chat, member)
    if body.role not in ("admin", "member"):
        raise HTTPException(422, "The role is admin or member.")
    target = await db.get(ChatMember, (chat_id, user_id))
    if target is None:
        raise HTTPException(404, "This person isn't in the group.")
    if body.role == "member" and target.role == "admin":
        admins = (await db.scalars(
            select(ChatMember).where(ChatMember.chat_id == chat_id, ChatMember.role == "admin")
        )).all()
        if len(admins) <= 1:
            raise HTTPException(400, "A group needs at least one admin. Make someone else an admin first.")
    changed = target.role != body.role
    target.role = body.role
    await db.commit()
    if changed:
        other = await db.get(User, user_id)
        await chat_logic.system(db, chat, user, "promoted" if body.role == "admin" else "demoted", other)
    await chat_logic.chat_changed(db, chat.id)
    return await views.chat_details(db, user, chat.id)


@router.delete("/{chat_id}/members/{user_id}")
async def remove(chat_id: str, user_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    chat, member = await chat_logic.membership(db, chat_id, user)
    if not chat.is_group:
        raise HTTPException(400, "That only works in groups.")
    if user_id != user.id:
        chat_logic.require_admin(chat, member)
    target = await db.get(User, user_id)
    if target is None or await db.get(ChatMember, (chat_id, user_id)) is None:
        raise HTTPException(404, "This person isn't in the group.")
    await chat_logic.remove_member(db, chat, target, user)
    if user_id == user.id:
        return {}
    return await views.chat_details(db, user, chat.id)


class MySettings(BaseModel):
    muted: bool


@router.patch("/{chat_id}/me")
async def my_settings(chat_id: str, body: MySettings, user: User = Depends(current_user),
                      db: AsyncSession = Depends(get_db)):
    _, member = await chat_logic.membership(db, chat_id, user)
    member.muted = body.muted
    await db.commit()
    await hub.send([user.id], {"type": "chat.updated", "chat_id": chat_id})
    return {}


class Mark(BaseModel):
    seq: int | None = None


async def _mark(db: AsyncSession, chat_id: str, user: User, seq: int | None, read: bool) -> None:
    chat, member = await chat_logic.membership(db, chat_id, user)
    top = chat.last_message_seq or 0
    value = min(seq, top) if seq is not None else top
    changed = False
    if read and value > member.read_seq:
        member.read_seq = value
        changed = True
    if value > member.delivered_seq:
        member.delivered_seq = value
        changed = True
    if changed:
        await db.commit()
        ids = await chat_logic.member_ids(db, chat_id)
        await hub.send(ids, {"type": "receipt", "chat_id": chat_id, "user_id": user.id,
                             "read_seq": member.read_seq, "delivered_seq": member.delivered_seq})


@router.post("/{chat_id}/read")
async def read(chat_id: str, body: Mark, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    await _mark(db, chat_id, user, body.seq, read=True)
    return {}


@router.post("/{chat_id}/delivered")
async def delivered(chat_id: str, body: Mark, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    await _mark(db, chat_id, user, body.seq, read=False)
    return {}


@router.post("/delivered-all")
async def delivered_all(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """The app came online: everything waiting for me is now delivered."""
    rows = (await db.execute(
        select(ChatMember, Chat).join(Chat, Chat.id == ChatMember.chat_id)
        .where(ChatMember.user_id == user.id, Chat.last_message_seq > ChatMember.delivered_seq)
    )).all()
    for member, chat in rows:
        member.delivered_seq = chat.last_message_seq or 0
    await db.commit()
    for member, chat in rows:
        ids = await chat_logic.member_ids(db, chat.id)
        await hub.send(ids, {"type": "receipt", "chat_id": chat.id, "user_id": user.id,
                             "read_seq": member.read_seq, "delivered_seq": member.delivered_seq})
    return {}


@router.get("/{chat_id}/messages")
async def messages(chat_id: str, before_seq: int | None = None, after_seq: int | None = None, limit: int = 50,
                   user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    _, member = await chat_logic.membership(db, chat_id, user)
    limit = max(1, min(limit, 200))
    q = select(Message).where(Message.chat_id == chat_id, Message.seq > member.hidden_seq)
    if before_seq is not None:
        q = q.where(Message.seq < before_seq)
    if after_seq is not None:
        q = q.where(Message.seq > after_seq).order_by(Message.seq.asc()).limit(limit)
        rows = list(reversed((await db.scalars(q)).all()))
    else:
        rows = (await db.scalars(q.order_by(Message.seq.desc()).limit(limit))).all()
    return [views.message(m) for m in rows]


@router.get("/{chat_id}/pinned")
async def pinned(chat_id: str, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    _, member = await chat_logic.membership(db, chat_id, user)
    rows = (await db.scalars(
        select(Message).where(Message.chat_id == chat_id, Message.pinned_at.is_not(None),
                              Message.deleted_at.is_(None), Message.seq > member.hidden_seq)
        .order_by(Message.pinned_at.desc())
    )).all()
    return [views.message(m) for m in rows]


class Send(BaseModel):
    client_id: str = Field(min_length=1, max_length=64)
    kind: str = "text"
    body: str = Field(default="", max_length=20000)
    payload: dict | None = None
    reply_to_id: str | None = None


@router.post("/{chat_id}/messages")
async def send(chat_id: str, body: Send, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    chat, member = await chat_logic.membership(db, chat_id, user)
    # A retry of a message that already arrived: give back the first one.
    existing = await db.scalar(select(Message).where(Message.sender_id == user.id, Message.client_id == body.client_id))
    if existing is not None:
        return views.message(existing)
    if body.kind not in ("text", "note", "block", "image"):
        raise HTTPException(422, "Unknown message kind.")
    if body.kind == "text" and not body.body.strip():
        raise HTTPException(422, "The message is empty.")
    if body.kind == "image" and not (body.payload or {}).get("url"):
        raise HTTPException(422, "The picture is missing.")
    if body.kind in ("note", "block") and not body.payload:
        raise HTTPException(422, "The note is missing.")
    if body.payload is not None and len(str(body.payload)) > 1_000_000:
        raise HTTPException(413, "That note is too big to send (1 MB at most).")
    if chat.is_group and chat.admin_only and member.role != "admin":
        raise HTTPException(403, "Only admins can send messages in this group.")
    if not chat.is_group:
        others = [i for i in await chat_logic.member_ids(db, chat.id) if i != user.id]
        if others:
            other = await db.get(User, others[0])
            if other is None or other.is_deleted:
                raise HTTPException(403, "This account was deleted.")
            blocked = await chat_logic.blocked_between(db, user.id, others[0])
            if blocked == "me":
                raise HTTPException(403, "You blocked this person. Unblock them to send messages.")
            if blocked == "them":
                raise HTTPException(403, "You can't message this person.")
    reply = None
    if body.reply_to_id:
        reply = await db.scalar(select(Message).where(Message.id == body.reply_to_id, Message.chat_id == chat_id))
    m = await chat_logic.post(db, chat, user, kind=body.kind, body=body.body, payload=body.payload,
                              reply_to=reply, client_id=body.client_id)
    return views.message(m)
