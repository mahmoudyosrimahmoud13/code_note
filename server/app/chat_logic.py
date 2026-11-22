"""Rules shared by the chat routes: who may do what, posting messages
(including system lines like "Sara added Omar"), and telling everyone."""

import asyncio

from fastapi import HTTPException
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import push, views
from .db import utcnow
from .models import Block, Chat, ChatMember, DeviceToken, Message, User
from .realtime import hub


async def member_ids(db: AsyncSession, chat_id: str) -> list[str]:
    return list((await db.scalars(select(ChatMember.user_id).where(ChatMember.chat_id == chat_id))).all())


async def membership(db: AsyncSession, chat_id: str, user: User) -> tuple[Chat, ChatMember]:
    chat = await db.get(Chat, chat_id)
    member = await db.get(ChatMember, (chat_id, user.id)) if chat else None
    if chat is None or member is None:
        raise HTTPException(404, "This chat doesn't exist, or you're not in it.")
    return chat, member


def require_admin(chat: Chat, member: ChatMember) -> None:
    if not chat.is_group:
        raise HTTPException(400, "That only works in groups.")
    if member.role != "admin":
        raise HTTPException(403, "Only group admins can do this.")


async def blocked_between(db: AsyncSession, a: str, b: str) -> str | None:
    """'me' if a blocked b, 'them' if b blocked a, else None."""
    rows = (await db.execute(
        select(Block.blocker_id).where(
            or_(and_(Block.blocker_id == a, Block.blocked_id == b), and_(Block.blocker_id == b, Block.blocked_id == a))
        )
    )).scalars().all()
    if a in rows:
        return "me"
    if b in rows:
        return "them"
    return None


def snippet(kind: str, body: str, payload: dict | None) -> str:
    if kind == "image":
        return f"📷 {body}".strip() if body else "📷 Photo"
    if kind == "note":
        title = (payload or {}).get("title") or "Untitled"
        return f"📝 Note: {title}"
    if kind == "block":
        lang = (payload or {}).get("language")
        return f"‹/› Code{f' ({lang})' if lang else ''}: {body}"[:120] if body else "‹/› Code block"
    return body[:200]


async def post(
    db: AsyncSession,
    chat: Chat,
    sender: User | None,
    *,
    kind: str,
    body: str = "",
    payload: dict | None = None,
    reply_to: Message | None = None,
    client_id: str | None = None,
    notify: bool = True,
) -> Message:
    """Saves a message, moves the chat to the top, and tells everyone."""
    m = Message(
        chat_id=chat.id,
        sender_id=sender.id if sender else None,
        client_id=client_id,
        kind=kind,
        body=body,
        payload=payload,
        reactions={},
    )
    if reply_to is not None and reply_to.deleted_at is None:
        m.reply_to_id = reply_to.id
        m.reply_preview = {
            "id": reply_to.id,
            "sender_id": reply_to.sender_id,
            "kind": reply_to.kind,
            "body": snippet(reply_to.kind, reply_to.body, reply_to.payload),
        }
    db.add(m)
    await db.flush()
    chat.last_message_seq = m.seq
    chat.updated_at = utcnow()

    members = (await db.scalars(select(ChatMember).where(ChatMember.chat_id == chat.id))).all()
    for mem in members:
        mem.hidden = False  # a deleted direct chat comes back, without old history
        if sender is not None and mem.user_id == sender.id:
            mem.read_seq = m.seq
            mem.delivered_seq = m.seq
    await db.commit()

    out = views.message(m)
    ids = [mem.user_id for mem in members]
    await hub.send(ids, {"type": "message.new", "chat_id": chat.id, "message": out})
    if sender is not None:
        await hub.send(ids, {"type": "receipt", "chat_id": chat.id, "user_id": sender.id,
                             "read_seq": m.seq, "delivered_seq": m.seq})
    if notify and sender is not None and kind != "system":
        targets = [mem.user_id for mem in members if mem.user_id != sender.id and not mem.muted]
        asyncio.create_task(_push(chat, sender, m, targets))
    return m


async def _push(chat: Chat, sender: User, m: Message, user_ids: list[str]) -> None:
    if not user_ids or not push.enabled():
        return
    from .db import sessions

    async with sessions()() as db:
        tokens = list((await db.scalars(select(DeviceToken.token).where(DeviceToken.user_id.in_(user_ids)))).all())
        if not tokens:
            return
        title = f"{chat.name} · {sender.name}" if chat.is_group else sender.name
        body = snippet(m.kind, m.body, m.payload)
        dead = await push.send(tokens, title, body, {"type": "message", "chat_id": chat.id, "message_id": m.id})
        for t in dead:
            row = await db.get(DeviceToken, t)
            if row is not None:
                await db.delete(row)
        await db.commit()


async def system(db: AsyncSession, chat: Chat, actor: User, event: str, target: User | None = None, **extra) -> None:
    await post(db, chat, None, kind="system",
               payload={"event": event, "actor_id": actor.id, "target_id": target.id if target else None, **extra},
               notify=False)


async def chat_changed(db: AsyncSession, chat_id: str, also: list[str] | None = None) -> None:
    ids = await member_ids(db, chat_id)
    await hub.send(ids + (also or []), {"type": "chat.updated", "chat_id": chat_id})


async def remove_member(db: AsyncSession, chat: Chat, user: User, actor: User) -> None:
    """Takes [user] out of a group. Keeps at least one admin; deletes an
    empty group."""
    member = await db.get(ChatMember, (chat.id, user.id))
    if member is None:
        return
    was_admin = member.role == "admin"
    await db.delete(member)
    await db.flush()
    rest = (await db.scalars(
        select(ChatMember).where(ChatMember.chat_id == chat.id).order_by(ChatMember.joined_at)
    )).all()
    if not rest:
        await db.delete(chat)
        await db.commit()
        await hub.send([user.id], {"type": "chat.removed", "chat_id": chat.id})
        return
    if was_admin and not any(m.role == "admin" for m in rest):
        rest[0].role = "admin"
    await db.commit()
    await hub.send([user.id], {"type": "chat.removed", "chat_id": chat.id})
    await system(db, chat, actor, "left" if actor.id == user.id else "removed", None if actor.id == user.id else user)
    await chat_changed(db, chat.id)
