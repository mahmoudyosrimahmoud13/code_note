import json

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from ..db import iso, sessions, utcnow
from ..models import ChatMember, User
from ..realtime import hub
from ..security import user_from_token

router = APIRouter()


async def _contacts(user_id: str) -> list[str]:
    """Everyone who shares a chat with this person (they see online status)."""
    async with sessions()() as db:
        mine = select(ChatMember.chat_id).where(ChatMember.user_id == user_id)
        rows = (await db.scalars(
            select(ChatMember.user_id).where(ChatMember.chat_id.in_(mine), ChatMember.user_id != user_id).distinct()
        )).all()
        return list(rows)


async def _presence(user_id: str, online: bool) -> None:
    async with sessions()() as db:
        user = await db.get(User, user_id)
        if user is None:
            return
        user.last_seen_at = utcnow()
        await db.commit()
        seen = iso(user.last_seen_at)
    await hub.send(await _contacts(user_id),
                   {"type": "presence", "user_id": user_id, "online": online, "last_seen_at": seen})


@router.websocket("/ws")
async def socket(ws: WebSocket, token: str = ""):
    async with sessions()() as db:
        try:
            user = await user_from_token(db, token)
        except HTTPException:
            await ws.close(code=4001)
            return
        user_id = user.id
    await ws.accept()
    hub.handler_started()
    try:
        if await hub.join(user_id, ws):
            await _presence(user_id, True)
        while True:
            text = await ws.receive_text()
            try:
                event = json.loads(text)
            except ValueError:
                continue
            kind = event.get("type")
            if kind == "ping":
                await ws.send_text('{"type":"pong"}')
            elif kind == "typing" and isinstance(event.get("chat_id"), str):
                chat_id = event["chat_id"]
                async with sessions()() as db:
                    if await db.get(ChatMember, (chat_id, user_id)) is None:
                        continue
                    ids = (await db.scalars(select(ChatMember.user_id).where(ChatMember.chat_id == chat_id))).all()
                await hub.send([i for i in ids if i != user_id],
                               {"type": "typing", "chat_id": chat_id, "user_id": user_id})
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        try:
            if await hub.leave(user_id, ws):
                # Saved as its own job: if this socket's task is being cut off
                # (server stopping, client gone), the database write still
                # finishes cleanly instead of being stopped halfway.
                hub.run_later(_presence(user_id, False))
        finally:
            hub.handler_finished()
