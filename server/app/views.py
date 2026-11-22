"""Turns rows into the JSON shapes in docs/online/CONTRACT.md."""

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import iso
from .models import Announcement, Block, Chat, ChatMember, Message, SyncedItem, User
from .realtime import hub


def profile(user: User, *, me: User | None = None, with_email: bool = False) -> dict:
    show_email = with_email or (me is not None and (me.id == user.id or me.is_admin))
    if user.is_deleted:
        return {
            "id": user.id,
            "name": "Deleted account",
            "username": None,
            "avatar_url": None,
            "about": "",
            "is_admin": False,
            "is_disabled": False,
            "is_deleted": True,
            "created_at": iso(user.created_at),
            "last_seen_at": None,
            "online": False,
        }
    out = {
        "id": user.id,
        "name": user.name,
        "username": user.username,
        "avatar_url": user.avatar_url,
        "about": user.about,
        "is_admin": user.is_admin,
        "is_disabled": user.is_disabled,
        "is_deleted": False,
        "created_at": iso(user.created_at),
        "last_seen_at": iso(user.last_seen_at),
        "online": hub.is_online(user.id),
    }
    if show_email:
        out["email"] = user.email
        out["email_verified"] = user.email_verified
    return out


def message(m: Message) -> dict:
    deleted = m.deleted_at is not None
    return {
        "id": m.id,
        "seq": m.seq,
        "chat_id": m.chat_id,
        "sender_id": m.sender_id,
        "client_id": m.client_id,
        "kind": m.kind,
        "body": "" if deleted else m.body,
        "payload": None if deleted else m.payload,
        "reply_to": None if deleted else m.reply_preview,
        "reactions": {} if deleted else (m.reactions or {}),
        "pinned": m.pinned_at is not None and not deleted,
        "edited": m.edited_at is not None,
        "deleted": deleted,
        "created_at": iso(m.created_at),
    }


def announcement(a: Announcement) -> dict:
    return {
        "id": a.id,
        "title": a.title,
        "body": a.body,
        "kind": a.kind,
        "active": a.active,
        "created_at": iso(a.created_at),
    }


def synced(item: SyncedItem) -> dict:
    return {
        "kind": item.kind,
        "id": item.item_id,
        "data": None if item.deleted else item.data,
        "deleted": item.deleted,
        "rev": item.rev,
        "updated_at": iso(item.updated_at),
    }


async def chat_summaries(
    db: AsyncSession, me: User, chat_ids: list[str] | None = None, *, include_hidden: bool = False
) -> list[dict]:
    """The chat list for [me], newest first. One query per kind of data, so
    a long list stays fast (the old app fetched each person separately)."""
    q = (
        select(Chat, ChatMember)
        .join(ChatMember, and_(ChatMember.chat_id == Chat.id, ChatMember.user_id == me.id))
        .order_by(Chat.updated_at.desc())
    )
    if not include_hidden:
        q = q.where(ChatMember.hidden.is_(False))
    if chat_ids is not None:
        q = q.where(Chat.id.in_(chat_ids))
    rows = (await db.execute(q)).all()
    if not rows:
        return []
    ids = [c.id for c, _ in rows]

    last_seqs = [c.last_message_seq for c, _ in rows if c.last_message_seq]
    last_messages = {}
    if last_seqs:
        for m in (await db.scalars(select(Message).where(Message.seq.in_(last_seqs)))).all():
            last_messages[m.chat_id] = m

    # Unread: after my read mark, not mine, not deleted, not hidden.
    unread_q = (
        select(Message.chat_id, func.count())
        .join(ChatMember, and_(ChatMember.chat_id == Message.chat_id, ChatMember.user_id == me.id))
        .where(
            Message.chat_id.in_(ids),
            Message.seq > ChatMember.read_seq,
            Message.seq > ChatMember.hidden_seq,
            Message.deleted_at.is_(None),
            Message.kind != "system",
            (Message.sender_id != me.id) | Message.sender_id.is_(None),
        )
        .group_by(Message.chat_id)
    )
    unread = dict((await db.execute(unread_q)).all())

    counts = dict(
        (await db.execute(
            select(ChatMember.chat_id, func.count()).where(ChatMember.chat_id.in_(ids)).group_by(ChatMember.chat_id)
        )).all()
    )

    # The other person in each direct chat.
    direct_ids = [c.id for c, _ in rows if not c.is_group]
    others: dict[str, User] = {}
    if direct_ids:
        other_rows = (await db.execute(
            select(ChatMember.chat_id, User)
            .join(User, User.id == ChatMember.user_id)
            .where(ChatMember.chat_id.in_(direct_ids), ChatMember.user_id != me.id)
        )).all()
        others = {chat_id: user for chat_id, user in other_rows}

    # Blocking in direct chats: "me" (I blocked them) or "them".
    blocks = (await db.execute(
        select(Block.blocker_id, Block.blocked_id).where((Block.blocker_id == me.id) | (Block.blocked_id == me.id))
    )).all()
    blocked_by_me = {b for a, b in blocks if a == me.id}
    blocked_me = {a for a, b in blocks if b == me.id}

    out = []
    for chat, member in rows:
        last = last_messages.get(chat.id)
        if last is not None and last.seq <= member.hidden_seq:
            last = None
        other = others.get(chat.id)
        out.append({
            "id": chat.id,
            "is_group": chat.is_group,
            "name": chat.name if chat.is_group else (other.name if other and not other.is_deleted else "Deleted account"),
            "description": chat.description,
            "image_url": chat.image_url if chat.is_group else (other.avatar_url if other and not other.is_deleted else None),
            "admin_only": chat.admin_only,
            "created_by": chat.created_by,
            "created_at": iso(chat.created_at),
            "updated_at": iso(chat.updated_at),
            "last_message": message(last) if last else None,
            "unread": unread.get(chat.id, 0),
            "muted": member.muted,
            "my_role": member.role,
            "member_count": counts.get(chat.id, 0),
            "other_user": profile(other, me=me) if other else None,
            "blocked": None if chat.is_group or other is None else (
                "me" if other.id in blocked_by_me else ("them" if other.id in blocked_me else None)),
            "my_read_seq": member.read_seq,
            "hidden_seq": member.hidden_seq,
        })
    return out


async def chat_details(db: AsyncSession, me: User, chat_id: str) -> dict:
    summaries = await chat_summaries(db, me, [chat_id], include_hidden=True)
    if not summaries:
        from fastapi import HTTPException

        raise HTTPException(404, "This chat doesn't exist, or you're not in it.")
    out = summaries[0]
    rows = (await db.execute(
        select(ChatMember, User).join(User, User.id == ChatMember.user_id)
        .where(ChatMember.chat_id == chat_id).order_by(ChatMember.joined_at)
    )).all()
    out["members"] = [
        {
            "user": profile(u, me=me),
            "role": m.role,
            "joined_at": iso(m.joined_at),
            "read_seq": m.read_seq,
            "delivered_seq": m.delivered_seq,
        }
        for m, u in rows
    ]
    return out
