"""Database engine and sessions."""

from collections.abc import AsyncIterator
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    pass


def utcnow() -> datetime:
    """Now in UTC, without a time zone attached (stored that way everywhere)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value.isoformat(timespec="milliseconds") + "Z"


_engine = None
_sessions: async_sessionmaker[AsyncSession] | None = None


def engine():
    global _engine, _sessions
    if _engine is None:
        url = get_settings().database_url
        kwargs = {}
        if url.startswith("sqlite"):
            kwargs["connect_args"] = {"timeout": 30}
        else:
            kwargs.update(pool_size=10, max_overflow=20, pool_pre_ping=True)
        _engine = create_async_engine(url, **kwargs)
        _sessions = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine


def sessions() -> async_sessionmaker[AsyncSession]:
    engine()
    assert _sessions is not None
    return _sessions


async def reset_engine() -> None:
    """For tests: forget the engine so a new DATABASE_URL is used."""
    global _engine, _sessions
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _sessions = None


async def get_db() -> AsyncIterator[AsyncSession]:
    async with sessions()() as session:
        yield session


async def create_tables() -> None:
    from . import models  # noqa: F401  (registers the tables)

    async with engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
