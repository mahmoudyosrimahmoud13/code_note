"""Tests for the Supabase migration, on plain Postgres with a small stand-in
for Supabase Auth (supabase_stub.sql). Each call runs as the signed-in
person, like the app does.

    SB_TEST_DSN=postgresql://postgres@localhost:5433/sb_test pytest supabase/tests
"""

import json
import os
import uuid

import psycopg
import pytest

DSN = os.environ.get("SB_TEST_DSN", "postgresql://postgres@localhost:5433/sb_test")


@pytest.fixture(scope="module")
def db():
    with psycopg.connect(DSN, autocommit=True) as conn:
        yield conn


class Err(Exception):
    pass


def call(db, uid, fn, *args):
    """Runs public.fn(args) as [uid] (None = signed out)."""
    placeholders = ", ".join(["%s"] * len(args))
    with db.transaction():
        with db.cursor() as cur:
            cur.execute("set local role " + ("authenticated" if uid else "anon"))
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
            try:
                cur.execute(f"select public.{fn}({placeholders})", args)
            except psycopg.Error as e:
                raise Err(e.diag.message_primary) from None
            row = cur.fetchone()
    return row[0] if row else None


def select_as(db, uid, sql, *args):
    with db.transaction():
        with db.cursor() as cur:
            cur.execute("set local role authenticated")
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid,))
            cur.execute(sql, args)
            return cur.fetchall()


def signup(db, name, email=None, username=None):
    email = email or f"{name.lower()}-{uuid.uuid4().hex[:6]}@example.com"
    meta = {"name": name, "username": username or f"{name.lower()}_{uuid.uuid4().hex[:5]}"}
    with db.cursor() as cur:
        cur.execute("insert into auth.users (email, raw_user_meta_data) values (%s, %s) returning id",
                    (email, json.dumps(meta)))
        return str(cur.fetchone()[0])


def chat_of(db, uid, chat_id):
    return next((c for c in call(db, uid, "my_chats") if c["id"] == chat_id), None)


def send(db, uid, chat_id, body="hi", reply=None):
    return call(db, uid, "send_message", chat_id, uuid.uuid4().hex, "text", body, None, reply)


def test_accounts(db):
    first = signup(db, "Admin")
    assert call(db, first, "me")["is_admin"] is True
    second = signup(db, "Sara", username="sara_sb")
    assert call(db, second, "me")["is_admin"] is False
    # A taken username gets a suffix at sign-up; changing to a taken one fails.
    third = signup(db, "Sara2", username="sara_sb")
    assert call(db, third, "me")["username"].startswith("sara_sb_")
    with pytest.raises(Err, match="taken"):
        call(db, third, "update_profile", None, "SARA_SB", None, None)
    assert call(db, third, "update_profile", None, "Sara_Three", "Hi", None)["username"] == "sara_three"
    assert call(db, None, "username_available", "sara_three") is False
    assert call(db, None, "username_available", "free_name_x") is True
    # Signed out: the chat functions can't even be called.
    with pytest.raises(Err, match="permission denied"):
        call(db, None, "my_chats")
    # Others' emails stay private.
    found = call(db, second, "search_users", "sara_three")
    assert found[0]["id"] == third and "email" not in found[0]
    assert "email" in call(db, first, "get_user", third)  # admins see it


def test_direct_chat_flow(db):
    a = signup(db, "Omar")
    b = signup(db, "Lina")
    chat = call(db, a, "start_direct", b)
    assert call(db, b, "start_direct", a)["id"] == chat["id"]
    cid = chat["id"]

    m1 = send(db, a, cid, "hello")
    again = call(db, a, "send_message", cid, m1["client_id"], "text", "hello", None, None)
    assert again["id"] == m1["id"]
    send(db, a, cid, "are you there?")
    assert chat_of(db, b, cid)["unread"] == 2
    msgs = call(db, b, "get_messages", cid, None, None, 50)
    assert [m["body"] for m in msgs] == ["are you there?", "hello"]

    call(db, b, "mark_read", cid, None)
    assert chat_of(db, b, cid)["unread"] == 0
    lina = next(m for m in call(db, a, "chat_details", cid)["members"] if m["user"]["id"] == b)
    assert lina["read_seq"] >= msgs[0]["seq"]

    reply = send(db, b, cid, "yes!", m1["id"])
    assert reply["reply_to"]["body"] == "hello"
    with pytest.raises(Err, match="own messages"):
        call(db, b, "edit_message", m1["id"], "x")
    assert call(db, a, "edit_message", m1["id"], "hello there")["edited"] is True
    assert call(db, b, "react", m1["id"], "👍")["reactions"] == {b: "👍"}
    assert call(db, b, "react", m1["id"], "❤️")["reactions"] == {b: "❤️"}
    assert call(db, b, "pin_message", m1["id"], True)["pinned"] is True
    assert len(call(db, a, "pinned_messages", cid)) == 1
    with pytest.raises(Err, match="own messages"):
        call(db, b, "delete_message", m1["id"])
    gone = call(db, a, "delete_message", m1["id"])
    assert gone["deleted"] and gone["body"] == "" and not gone["pinned"]

    older = call(db, a, "get_messages", cid, reply["seq"], None, 1)
    assert len(older) == 1 and older[0]["seq"] < reply["seq"]

    # Hidden for me only; a new message brings it back without the history.
    call(db, a, "delete_chat", cid)
    assert chat_of(db, a, cid) is None and chat_of(db, b, cid) is not None
    send(db, b, cid, "back again")
    assert chat_of(db, a, cid)["unread"] == 1
    assert [m["body"] for m in call(db, a, "get_messages", cid, None, None, 50)] == ["back again"]

    # Row-level security: live updates only see your own chats.
    stranger = signup(db, "Stranger")
    assert select_as(db, stranger, "select count(*) from public.messages where chat_id = %s", cid)[0][0] == 0
    assert select_as(db, b, "select count(*) from public.messages where chat_id = %s", cid)[0][0] > 0
    # Hidden history isn't visible to its owner either.
    visible = select_as(db, a, "select count(*) from public.messages where chat_id = %s", cid)[0][0]
    assert visible == 1
    with pytest.raises(psycopg.Error):
        select_as(db, stranger, "insert into public.messages (chat_id, kind, body) values (%s, 'text', 'x')", cid)


def test_blocking(db):
    a = signup(db, "Kareem")
    b = signup(db, "Mona")
    cid = call(db, a, "start_direct", b)["id"]
    call(db, a, "block_user", b)
    assert chat_of(db, a, cid)["blocked"] == "me"
    assert chat_of(db, b, cid)["blocked"] == "them"
    with pytest.raises(Err, match="can't message"):
        send(db, b, cid)
    me_b = call(db, a, "me")["username"]
    assert call(db, b, "search_users", me_b) == []
    assert [p["id"] for p in call(db, a, "my_blocks")] == [b]
    call(db, a, "unblock_user", b)
    send(db, b, cid, "hi again")


def test_groups(db):
    owner = signup(db, "Owner")
    x = signup(db, "Xena")
    y = signup(db, "Yusuf")
    g = call(db, owner, "create_group", "Team", "", None, [x], False)
    gid = g["id"]
    assert g["my_role"] == "admin" and g["member_count"] == 2
    assert call(db, x, "get_messages", gid, None, None, 50)[-1]["payload"]["event"] == "created"
    with pytest.raises(Err, match="admins"):
        call(db, x, "update_group", gid, "Mine", None, None, None)

    send(db, owner, gid, "before Yusuf")
    call(db, owner, "add_members", gid, [y])
    assert chat_of(db, y, gid)["unread"] == 0

    call(db, owner, "update_group", gid, None, None, None, True)
    with pytest.raises(Err, match="Only admins"):
        send(db, x, gid, "hey")
    call(db, owner, "update_group", gid, None, None, None, False)
    msg = send(db, x, gid, "hey team")
    with pytest.raises(Err, match="admins can pin"):
        call(db, x, "pin_message", msg["id"], True)
    assert call(db, owner, "delete_message", msg["id"])["deleted"]

    with pytest.raises(Err, match="at least one admin"):
        call(db, owner, "set_member_role", gid, owner, "member")
    call(db, owner, "set_member_role", gid, x, "admin")
    call(db, x, "remove_member", gid, y)
    assert chat_of(db, y, gid) is None
    call(db, owner, "set_member_role", gid, x, "member")
    assert call(db, owner, "remove_member", gid, owner) is None  # leave
    assert chat_of(db, x, gid)["my_role"] == "admin"
    events = {m["payload"]["event"] for m in call(db, x, "get_messages", gid, None, None, 50) if m["kind"] == "system"}
    assert {"created", "added", "promoted", "demoted", "removed", "left"} <= events

    g2 = call(db, x, "create_group", "Second", "", None, [y], False)
    assert [c["id"] for c in call(db, x, "get_user", y)["common_groups"]] == [g2["id"]]
    with pytest.raises(Err, match="admins"):
        call(db, y, "delete_chat", g2["id"])
    call(db, x, "delete_chat", g2["id"])
    assert chat_of(db, y, g2["id"]) is None


def test_sync(db):
    a = signup(db, "Syncer")
    note = {"id": "note-1", "title": "One", "lastModified": "2026-11-22T10:00:00Z"}
    r = call(db, a, "sync_push", json.dumps([{"kind": "note", "id": "note-1", "data": note}]))
    assert r["applied"] == ["note-1"] and r["rev"] == 1
    assert call(db, a, "sync_pull", 0, 500)["items"][0]["data"]["title"] == "One"
    old = {**note, "title": "Old", "lastModified": "2026-11-22T09:00:00Z"}
    r = call(db, a, "sync_push", json.dumps([{"kind": "note", "id": "note-1", "data": old}]))
    assert r["applied"] == [] and r["conflicts"][0]["data"]["title"] == "One"
    r = call(db, a, "sync_push", json.dumps([{"kind": "note", "id": "note-1", "deleted": True,
                                              "modified_at": "2026-11-22T11:00:00Z"}]))
    assert r["applied"] == ["note-1"]
    last = call(db, a, "sync_pull", 1, 500)["items"][0]
    assert last["deleted"] and last["data"] is None
    other = signup(db, "Other")
    assert call(db, other, "sync_pull", 0, 500)["items"] == []
    assert select_as(db, other, "select count(*) from public.synced_items")[0][0] == 0


def test_admin(db):
    with db.cursor() as cur:
        cur.execute("select id::text from public.profiles where is_admin order by created_at limit 1")
        admin = cur.fetchone()[0]
    user = signup(db, "Regular")
    with pytest.raises(Err, match="Only admins"):
        call(db, user, "admin_stats")
    assert call(db, admin, "admin_stats")["users"] >= 2
    listed = call(db, admin, "admin_users", call(db, user, "me")["username"])
    assert listed[0]["id"] == user and "email" in listed[0]

    call(db, admin, "admin_update_user", user, True, None)
    with pytest.raises(Err, match="turned off"):
        call(db, user, "my_chats")
    call(db, admin, "admin_update_user", user, False, None)
    with pytest.raises(Err, match="own account"):
        call(db, admin, "admin_update_user", admin, True, None)

    call(db, admin, "admin_update_settings", False, None, None)
    with pytest.raises(psycopg.Error, match="closed"):
        signup(db, "Late")
    call(db, admin, "admin_update_settings", True, 1, None)
    with pytest.raises(psycopg.Error, match="full"):
        signup(db, "Late")
    call(db, admin, "admin_update_settings", True, 1000, None)

    a = call(db, admin, "admin_announce", "Update", "New version", "update")
    assert call(db, None, "app_config")["announcement"]["id"] == a["id"]
    assert call(db, user, "announcements_list")[0]["id"] == a["id"]
    call(db, admin, "admin_set_announcement", a["id"], False)
    assert call(db, None, "app_config")["announcement"] is None


def test_delete_account(db):
    a = signup(db, "Leaving")
    b = signup(db, "Staying")
    cid = call(db, a, "start_direct", b)["id"]
    send(db, a, cid, "bye")
    g = call(db, a, "create_group", "Left behind", "", None, [b], False)
    call(db, a, "delete_my_account")
    with pytest.raises(Err):
        call(db, a, "me")
    assert chat_of(db, b, cid)["name"] == "Deleted account"
    assert chat_of(db, b, g["id"])["my_role"] == "admin"
    with pytest.raises(Err, match="deleted"):
        send(db, b, cid, "?")


def test_helpers_are_private(db):
    a = signup(db, "Snoop")
    with pytest.raises(Err, match="permission denied"):
        call(db, a, "_post", str(uuid.uuid4()), a, "text", "x", None, None, None)
