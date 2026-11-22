"""Live updates over WebSockets.

Each signed-in device keeps one socket open. Events go to everyone they
concern. This runs in one server process; run uvicorn with one worker (it
handles thousands of sockets), or put several servers behind a load
balancer with sticky sessions only if each person's devices land on the
same one.
"""

import asyncio
import json
from collections import defaultdict

from fastapi import WebSocket


class Hub:
    def __init__(self) -> None:
        self._sockets: dict[str, set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()
        self._handlers = 0                       # socket loops still running
        self._idle = asyncio.Event()
        self._idle.set()
        self._jobs: set[asyncio.Task] = set()    # background work (push)

    def handler_started(self) -> None:
        self._handlers += 1
        self._idle.clear()

    def handler_finished(self) -> None:
        self._handlers = max(0, self._handlers - 1)
        if self._handlers == 0:
            self._idle.set()

    def run_later(self, coro) -> None:
        """Runs work in the background, keeping a reference so it isn't lost."""
        task = asyncio.create_task(coro)
        self._jobs.add(task)
        task.add_done_callback(self._jobs.discard)

    async def drain(self, timeout: float = 5.0) -> None:
        """On shutdown: let open sockets finish saving "offline" and let
        background jobs end, so nothing is cut off halfway through a
        database call."""
        try:
            await asyncio.wait_for(self._idle.wait(), timeout)
        except asyncio.TimeoutError:
            pass
        if self._jobs:
            _, pending = await asyncio.wait(set(self._jobs), timeout=timeout)
            for task in pending:
                task.cancel()

    def online_count(self) -> int:
        return len(self._sockets)

    def is_online(self, user_id: str) -> bool:
        return bool(self._sockets.get(user_id))

    async def join(self, user_id: str, ws: WebSocket) -> bool:
        """Adds a socket. True if the person just came online."""
        async with self._lock:
            first = not self._sockets[user_id]
            self._sockets[user_id].add(ws)
            return first

    async def leave(self, user_id: str, ws: WebSocket) -> bool:
        """Removes a socket. True if the person is now offline."""
        async with self._lock:
            sockets = self._sockets.get(user_id)
            if not sockets:
                return False
            sockets.discard(ws)
            if not sockets:
                del self._sockets[user_id]
                return True
            return False

    async def send(self, user_ids, event: dict, *, skip: WebSocket | None = None) -> None:
        text = json.dumps(event, default=str)
        targets = []
        for uid in set(user_ids):
            targets.extend(ws for ws in list(self._sockets.get(uid, ())) if ws is not skip)
        if not targets:
            return
        await asyncio.gather(*(self._safe_send(ws, text) for ws in targets))

    async def disconnect_user(self, user_id: str) -> None:
        for ws in list(self._sockets.get(user_id, ())):
            try:
                await ws.send_text(json.dumps({"type": "account.disabled"}))
                await ws.close(code=4003)
            except Exception:
                pass

    @staticmethod
    async def _safe_send(ws: WebSocket, text: str) -> None:
        try:
            await ws.send_text(text)
        except Exception:
            pass  # the socket is closing; its own loop cleans up


hub = Hub()
