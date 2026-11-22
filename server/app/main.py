"""CodeNote server: accounts, chat and notes sync for CodeNote Online.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import VERSION, get_settings
from .db import create_tables, reset_engine
from .realtime import hub
from .routers import admin, auth, chats, files, messages, meta, sync, users, ws

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(_: FastAPI):
    if get_settings().secret_key == "change-me":
        logging.getLogger("codenote").warning(
            "SECRET_KEY is the default. Set a long random value before real use."
        )
    await create_tables()
    yield
    # Shutting down: finish open sockets and background work, then close
    # the database cleanly.
    await hub.drain()
    await reset_engine()


app = FastAPI(title="CodeNote server", version=VERSION, lifespan=lifespan)

origins = [o.strip() for o in get_settings().cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    """Plain words instead of a list of field errors."""
    first = exc.errors()[0] if exc.errors() else {}
    field = ".".join(str(p) for p in first.get("loc", [])[1:]) or "request"
    msg = first.get("msg", "is not valid")
    if field == "email":
        text = "That email address doesn't look right."
    elif field == "password" and "at least" in msg:
        text = "Passwords need at least 8 characters."
    else:
        text = f"{field}: {msg}"
    return JSONResponse(status_code=422, content={"detail": text})


for r in (meta, auth, users, chats, messages, files, sync, admin, ws):
    app.include_router(r.router)
