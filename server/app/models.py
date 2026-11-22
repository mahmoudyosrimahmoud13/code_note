"""Tables. The Supabase migration (supabase/migrations) has the same ones."""

import uuid
from datetime import datetime

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, utcnow

# Autoincrementing big numbers (SQLite only autoincrements INTEGER).
BigSeq = BigInteger().with_variant(Integer, "sqlite")


def new_id() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(200))
    google_sub: Mapped[str | None] = mapped_column(String(64), unique=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    name: Mapped[str] = mapped_column(String(80), default="")
    # Stored lowercase; unique.
    username: Mapped[str | None] = mapped_column(String(24), unique=True, index=True)
    avatar_url: Mapped[str | None] = mapped_column(String(1000))
    about: Mapped[str] = mapped_column(String(300), default="")
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_disabled: Mapped[bool] = mapped_column(Boolean, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime)
    # Counter for notes sync revisions.
    sync_rev: Mapped[int] = mapped_column(BigInteger, default=0)
    # Bumped to sign out every device (password change, disable).
    token_version: Mapped[int] = mapped_column(Integer, default=0)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # sha256 of the token
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class EmailCode(Base):
    __tablename__ = "email_codes"

    id: Mapped[int] = mapped_column(BigSeq, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(320), index=True)
    purpose: Mapped[str] = mapped_column(String(16))  # verify | reset
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    attempts: Mapped[int] = mapped_column(Integer, default=0)


class Block(Base):
    __tablename__ = "blocks"

    blocker_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    blocked_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Chat(Base):
    __tablename__ = "chats"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    is_group: Mapped[bool] = mapped_column(Boolean, default=False)
    # "smaller-id:bigger-id" for direct chats, so there's one per pair.
    dm_key: Mapped[str | None] = mapped_column(String(80), unique=True)
    name: Mapped[str] = mapped_column(String(80), default="")
    description: Mapped[str] = mapped_column(String(500), default="")
    image_url: Mapped[str | None] = mapped_column(String(1000))
    admin_only: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[str | None] = mapped_column(String(36))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    last_message_seq: Mapped[int | None] = mapped_column(BigInteger)


class ChatMember(Base):
    __tablename__ = "chat_members"

    chat_id: Mapped[str] = mapped_column(ForeignKey("chats.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    role: Mapped[str] = mapped_column(String(8), default="member")  # admin | member
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    read_seq: Mapped[int] = mapped_column(BigInteger, default=0)
    delivered_seq: Mapped[int] = mapped_column(BigInteger, default=0)
    # Messages up to here are hidden for this person (deleted chat).
    hidden_seq: Mapped[int] = mapped_column(BigInteger, default=0)
    hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    muted: Mapped[bool] = mapped_column(Boolean, default=False)


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (
        UniqueConstraint("sender_id", "client_id", name="uq_message_client"),
        Index("ix_messages_chat_seq", "chat_id", "seq"),
    )

    seq: Mapped[int] = mapped_column(BigSeq, primary_key=True, autoincrement=True)
    id: Mapped[str] = mapped_column(String(36), unique=True, default=new_id)
    chat_id: Mapped[str] = mapped_column(ForeignKey("chats.id", ondelete="CASCADE"))
    sender_id: Mapped[str | None] = mapped_column(String(36))
    client_id: Mapped[str | None] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(8), default="text")
    body: Mapped[str] = mapped_column(Text, default="")
    payload: Mapped[dict | None] = mapped_column(JSON)
    reply_to_id: Mapped[str | None] = mapped_column(String(36))
    reply_preview: Mapped[dict | None] = mapped_column(JSON)
    reactions: Mapped[dict] = mapped_column(JSON, default=dict)
    pinned_at: Mapped[datetime | None] = mapped_column(DateTime)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    token: Mapped[str] = mapped_column(String(512), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(16), default="android")
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class SyncedItem(Base):
    __tablename__ = "synced_items"
    __table_args__ = (Index("ix_synced_owner_rev", "owner_id", "rev"),)

    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    kind: Mapped[str] = mapped_column(String(8), primary_key=True)  # note | group
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    data: Mapped[dict | None] = mapped_column(JSON)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    # When the item was last changed on a device (decides conflicts).
    modified_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    rev: Mapped[int] = mapped_column(BigInteger, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Announcement(Base):
    __tablename__ = "announcements"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    title: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(Text, default="")
    kind: Mapped[str] = mapped_column(String(8), default="info")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[str | None] = mapped_column(String(36))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AppSettings(Base):
    __tablename__ = "app_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    signup_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    user_limit: Mapped[int] = mapped_column(Integer, default=1000)
    maintenance_message: Mapped[str] = mapped_column(String(500), default="")
