"""End-to-end tests for the CodeNote server.

Runs on SQLite by default. Set TEST_DATABASE_URL to a Postgres URL to run
the same tests there.
"""

import os
import tempfile
import uuid

import pytest
from fastapi.testclient import TestClient

DB = os.environ.get("TEST_DATABASE_URL") or f"sqlite+aiosqlite:///{tempfile.mkdtemp()}/test.db"
os.environ["DATABASE_URL"] = DB
os.environ["UPLOAD_DIR"] = tempfile.mkdtemp()
os.environ["SECRET_KEY"] = "test-secret-that-is-long-enough-for-hs256"
os.environ["RATE_LIMIT"] = "false"

from app.main import app  # noqa: E402

FIRST = {}  # the first account of the run (the admin)
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def signup(client, name, username=None, email=None, password="password123"):
    username = username or f"{name.lower()}_{uuid.uuid4().hex[:6]}"
    email = email or f"{username}@example.com"
    r = client.post("/auth/signup", json={"email": email, "password": password, "name": name, "username": username})
    assert r.status_code == 200, r.text
    s = r.json()
    s["h"] = {"Authorization": f"Bearer {s['access_token']}"}
    s["id"] = s["user"]["id"]
    s["email"] = email
    return s


def send(client, who, chat_id, body="hi", **extra):
    r = client.post(f"/chats/{chat_id}/messages", headers=who["h"],
                    json={"client_id": uuid.uuid4().hex, "kind": "text", "body": body, **extra})
    assert r.status_code == 200, r.text
    return r.json()


def chat_of(client, who, chat_id):
    return next((c for c in client.get("/chats", headers=who["h"]).json() if c["id"] == chat_id), None)


def test_health(client):
    r = client.get("/health").json()
    assert r["app"] == "codenote"
    assert client.get("/config").json()["signup_enabled"] is True


def test_accounts(client):
    first = signup(client, "Admin")
    FIRST.update(first)
    assert first["user"]["is_admin"] is True  # the first account is an admin
    second = signup(client, "Sara")
    assert second["user"]["is_admin"] is False

    # Duplicates and bad usernames
    r = client.post("/auth/signup", json={"email": second["email"], "password": "password123", "name": "X", "username": "fresh_name"})
    assert r.status_code == 409
    r = client.post("/auth/signup", json={"email": "x@example.com", "password": "password123", "name": "X", "username": "a"})
    assert r.status_code == 422
    r = client.post("/auth/signup", json={"email": "bad", "password": "password123", "name": "X", "username": "abcde"})
    assert r.json()["detail"] == "That email address doesn't look right."

    # Login, refresh (refresh tokens work once), logout
    r = client.post("/auth/login", json={"email": second["email"], "password": "password123"})
    assert r.status_code == 200
    s = r.json()
    r = client.post("/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": s["refresh_token"]}).status_code == 401
    assert client.post("/auth/login", json={"email": second["email"], "password": "wrong-pass"}).status_code == 401

    # Profile
    r = client.patch("/me", headers=second["h"], json={"about": "Hello", "username": "Sara_New"})
    assert r.json()["username"] == "sara_new"
    assert client.get("/users/username-free", params={"username": "sara_new"}).json()["available"] is False
    assert client.get("/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_password_reset_and_change(client, caplog):
    s = signup(client, "Reset")
    caplog.set_level("WARNING")
    assert client.post("/auth/password/forgot", json={"email": s["email"]}).status_code == 200
    # No SMTP in tests: the code is in the log.
    code = next(r.getMessage().split(": ")[-1] for r in caplog.records if "Code for" in r.getMessage())
    assert client.post("/auth/password/reset", json={"email": s["email"], "code": "000000" if code != "000000" else "111111",
                                                     "password": "newpassword1"}).status_code == 400
    assert client.post("/auth/password/reset", json={"email": s["email"], "code": code, "password": "newpassword1"}).status_code == 200
    # The old session is signed out.
    assert client.get("/me", headers=s["h"]).status_code == 401
    r = client.post("/auth/login", json={"email": s["email"], "password": "newpassword1"})
    assert r.status_code == 200
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.post("/auth/password/change", headers=h, json={"old_password": "wrong", "password": "another123"}).status_code == 400
    assert client.post("/auth/password/change", headers=h, json={"old_password": "newpassword1", "password": "another123"}).status_code == 200


def test_direct_chat_flow(client):
    a = signup(client, "Omar")
    b = signup(client, "Lina")

    found = client.get("/users/search", headers=a["h"], params={"q": b["user"]["username"]}).json()
    assert found and found[0]["id"] == b["id"]
    assert "email" not in found[0]  # others' emails stay private

    chat = client.post("/chats/direct", headers=a["h"], json={"user_id": b["id"]}).json()
    again = client.post("/chats/direct", headers=b["h"], json={"user_id": a["id"]}).json()
    assert chat["id"] == again["id"]  # one chat per pair
    assert chat["other_user"]["id"] == b["id"]

    m1 = send(client, a, chat["id"], "hello")
    # Retrying with the same client_id doesn't send twice.
    r = client.post(f"/chats/{chat['id']}/messages", headers=a["h"],
                    json={"client_id": m1["client_id"], "kind": "text", "body": "hello"})
    assert r.json()["id"] == m1["id"]
    send(client, a, chat["id"], "are you there?")

    assert chat_of(client, b, chat["id"])["unread"] == 2
    assert chat_of(client, a, chat["id"])["unread"] == 0
    msgs = client.get(f"/chats/{chat['id']}/messages", headers=b["h"]).json()
    assert [m["body"] for m in msgs] == ["are you there?", "hello"]  # newest first

    # Read receipts
    client.post(f"/chats/{chat['id']}/read", headers=b["h"], json={})
    assert chat_of(client, b, chat["id"])["unread"] == 0
    details = client.get(f"/chats/{chat['id']}", headers=a["h"]).json()
    lina = next(m for m in details["members"] if m["user"]["id"] == b["id"])
    assert lina["read_seq"] >= msgs[0]["seq"]

    # Reply, edit, react, pin, delete
    reply = send(client, b, chat["id"], "yes!", reply_to_id=m1["id"])
    assert reply["reply_to"]["body"] == "hello"
    assert client.patch(f"/messages/{m1['id']}", headers=b["h"], json={"body": "x"}).status_code == 403
    edited = client.patch(f"/messages/{m1['id']}", headers=a["h"], json={"body": "hello there"}).json()
    assert edited["edited"] and edited["body"] == "hello there"
    r = client.put(f"/messages/{m1['id']}/reaction", headers=b["h"], json={"emoji": "👍"}).json()
    assert r["reactions"] == {b["id"]: "👍"}
    r = client.put(f"/messages/{m1['id']}/reaction", headers=b["h"], json={"emoji": "❤️"}).json()
    assert r["reactions"] == {b["id"]: "❤️"}  # one reaction each
    assert client.put(f"/messages/{m1['id']}/pin", headers=b["h"], json={"pinned": True}).json()["pinned"]
    assert len(client.get(f"/chats/{chat['id']}/pinned", headers=a["h"]).json()) == 1
    assert client.delete(f"/messages/{m1['id']}", headers=b["h"]).status_code == 403
    gone = client.delete(f"/messages/{m1['id']}", headers=a["h"]).json()
    assert gone["deleted"] and gone["body"] == "" and not gone["pinned"]

    # Paging
    older = client.get(f"/chats/{chat['id']}/messages", headers=a["h"], params={"before_seq": reply["seq"], "limit": 1}).json()
    assert len(older) == 1 and older[0]["seq"] < reply["seq"]
    newer = client.get(f"/chats/{chat['id']}/messages", headers=a["h"], params={"after_seq": m1["seq"]}).json()
    assert newer[-1]["seq"] > m1["seq"]

    # Deleting a direct chat hides it and its history for me only.
    client.delete(f"/chats/{chat['id']}", headers=a["h"])
    assert chat_of(client, a, chat["id"]) is None
    assert chat_of(client, b, chat["id"]) is not None
    send(client, b, chat["id"], "back again")
    back = chat_of(client, a, chat["id"])
    assert back is not None and back["unread"] == 1
    assert [m["body"] for m in client.get(f"/chats/{chat['id']}/messages", headers=a["h"]).json()] == ["back again"]


def test_blocking(client):
    a = signup(client, "Kareem")
    b = signup(client, "Mona")
    chat = client.post("/chats/direct", headers=a["h"], json={"user_id": b["id"]}).json()
    assert client.put(f"/users/{b['id']}/block", headers=a["h"]).status_code == 200
    assert chat_of(client, a, chat["id"])["blocked"] == "me"
    assert chat_of(client, b, chat["id"])["blocked"] == "them"
    r = client.post(f"/chats/{chat['id']}/messages", headers=b["h"], json={"client_id": "x1", "kind": "text", "body": "hi"})
    assert r.status_code == 403
    assert client.get("/users/search", headers=b["h"], params={"q": a["user"]["username"]}).json() == []
    assert [p["id"] for p in client.get("/me/blocks", headers=a["h"]).json()] == [b["id"]]
    client.delete(f"/users/{b['id']}/block", headers=a["h"])
    send(client, b, chat["id"], "hi again")


def test_groups(client):
    owner = signup(client, "Owner")
    x = signup(client, "Xena")
    y = signup(client, "Yusuf")
    g = client.post("/chats/groups", headers=owner["h"], json={"name": "Team", "member_ids": [x["id"]]}).json()
    assert g["is_group"] and g["my_role"] == "admin" and g["member_count"] == 2
    first = client.get(f"/chats/{g['id']}/messages", headers=x["h"]).json()
    assert first[-1]["kind"] == "system" and first[-1]["payload"]["event"] == "created"

    # Members can't run the group.
    assert client.patch(f"/chats/{g['id']}", headers=x["h"], json={"name": "Mine"}).status_code == 403
    assert client.post(f"/chats/{g['id']}/members", headers=x["h"], json={"user_ids": [y["id"]]}).status_code == 403

    send(client, owner, g["id"], "before Yusuf joined")
    g = client.post(f"/chats/{g['id']}/members", headers=owner["h"], json={"user_ids": [y["id"]]}).json()
    assert g["member_count"] == 3
    assert chat_of(client, y, g["id"])["unread"] == 0  # old messages aren't unread for new people

    # Admin-only sending
    client.patch(f"/chats/{g['id']}", headers=owner["h"], json={"admin_only": True})
    r = client.post(f"/chats/{g['id']}/messages", headers=x["h"], json={"client_id": "g1", "kind": "text", "body": "hey"})
    assert r.status_code == 403
    client.patch(f"/chats/{g['id']}", headers=owner["h"], json={"admin_only": False})
    msg = send(client, x, g["id"], "hey team")

    # Admins delete anyone's message; members can't pin.
    assert client.put(f"/messages/{msg['id']}/pin", headers=x["h"], json={"pinned": True}).status_code == 403
    assert client.delete(f"/messages/{msg['id']}", headers=owner["h"]).json()["deleted"]

    # Roles: the last admin can't step down.
    r = client.patch(f"/chats/{g['id']}/members/{owner['id']}", headers=owner["h"], json={"role": "member"})
    assert r.status_code == 400
    client.patch(f"/chats/{g['id']}/members/{x['id']}", headers=owner["h"], json={"role": "admin"})
    assert chat_of(client, x, g["id"])["my_role"] == "admin"

    # Removing and leaving
    client.delete(f"/chats/{g['id']}/members/{y['id']}", headers=x["h"])
    assert chat_of(client, y, g["id"]) is None
    client.patch(f"/chats/{g['id']}/members/{x['id']}", headers=owner["h"], json={"role": "member"})
    client.delete(f"/chats/{g['id']}/members/{owner['id']}", headers=owner["h"])  # leave
    assert chat_of(client, x, g["id"])["my_role"] == "admin"  # the last admin left: Xena takes over
    events = [m["payload"]["event"] for m in client.get(f"/chats/{g['id']}/messages", headers=x["h"]).json() if m["kind"] == "system"]
    assert {"created", "added", "promoted", "demoted", "removed", "left"} <= set(events)

    # Common groups on a contact page
    g2 = client.post("/chats/groups", headers=x["h"], json={"name": "Second", "member_ids": [y["id"]]}).json()
    page = client.get(f"/users/{y['id']}", headers=x["h"]).json()
    assert [c["id"] for c in page["common_groups"]] == [g2["id"]]

    # Delete for everyone
    assert client.delete(f"/chats/{g2['id']}", headers=y["h"]).status_code == 403
    assert client.delete(f"/chats/{g2['id']}", headers=x["h"]).status_code == 200
    assert chat_of(client, y, g2["id"]) is None


def test_notes_and_images_in_chat(client):
    a = signup(client, "Nour")
    b = signup(client, "Hany")
    chat = client.post("/chats/direct", headers=a["h"], json={"user_id": b["id"]}).json()
    note = {"id": "n1", "title": "FastAPI tips", "blocks": [], "lastModified": "2026-11-22T10:00:00Z"}
    r = client.post(f"/chats/{chat['id']}/messages", headers=a["h"],
                    json={"client_id": "n-1", "kind": "note", "payload": note})
    assert r.json()["payload"]["title"] == "FastAPI tips"
    assert chat_of(client, b, chat["id"])["last_message"]["kind"] == "note"

    up = client.post("/files", headers=a["h"], files={"file": ("a.png", PNG, "image/png")})
    assert up.status_code == 200, up.text
    url = up.json()["url"]
    assert client.get(url.replace("http://testserver", "")).content == PNG
    bad = client.post("/files", headers=a["h"], files={"file": ("a.png", b"not an image", "image/png")})
    assert bad.status_code == 415
    r = client.post(f"/chats/{chat['id']}/messages", headers=a["h"],
                    json={"client_id": "i-1", "kind": "image", "body": "look", "payload": {"url": url}})
    assert r.status_code == 200
    r = client.post(f"/chats/{chat['id']}/messages", headers=a["h"], json={"client_id": "i-2", "kind": "image"})
    assert r.status_code == 422


def test_sync(client):
    a = signup(client, "Syncer")
    note = {"id": "note-1", "title": "One", "lastModified": "2026-11-22T10:00:00Z"}
    r = client.post("/sync", headers=a["h"], json={"items": [{"kind": "note", "id": "note-1", "data": note}]}).json()
    assert r["applied"] == ["note-1"] and r["rev"] == 1
    pulled = client.get("/sync", headers=a["h"], params={"since": 0}).json()
    assert pulled["items"][0]["data"]["title"] == "One"
    assert client.get("/sync", headers=a["h"], params={"since": 1}).json()["items"] == []

    # An older copy from another device loses.
    old = {**note, "title": "Old", "lastModified": "2026-11-22T09:00:00Z"}
    r = client.post("/sync", headers=a["h"], json={"items": [{"kind": "note", "id": "note-1", "data": old}]}).json()
    assert r["applied"] == [] and r["conflicts"][0]["data"]["title"] == "One"

    # A newer delete wins.
    r = client.post("/sync", headers=a["h"], json={"items": [
        {"kind": "note", "id": "note-1", "deleted": True, "modified_at": "2026-11-22T11:00:00Z"}]}).json()
    assert r["applied"] == ["note-1"]
    last = client.get("/sync", headers=a["h"], params={"since": 1}).json()["items"][0]
    assert last["deleted"] and last["data"] is None

    # Each account only sees its own notes.
    other = signup(client, "Other")
    assert client.get("/sync", headers=other["h"]).json()["items"] == []


def test_admin(client):
    # The first account in this database is the admin.
    admin = client.post("/auth/login", json={"email": FIRST["email"], "password": "password123"}).json()
    h = {"Authorization": f"Bearer {admin['access_token']}"}
    user = signup(client, "Regular")
    assert client.get("/admin/stats", headers=user["h"]).status_code == 403
    stats = client.get("/admin/stats", headers=h).json()
    assert stats["users"] >= 2

    listed = client.get("/admin/users", headers=h, params={"q": user["user"]["username"]}).json()
    assert listed[0]["email"] == user["email"]

    # Turning an account off signs it out.
    client.patch(f"/admin/users/{user['id']}", headers=h, json={"is_disabled": True})
    assert client.get("/me", headers=user["h"]).status_code in (401, 403)
    assert client.post("/auth/login", json={"email": user["email"], "password": "password123"}).status_code == 403
    client.patch(f"/admin/users/{user['id']}", headers=h, json={"is_disabled": False})

    # Sign-up switch and limit
    client.patch("/admin/settings", headers=h, json={"signup_enabled": False})
    r = client.post("/auth/signup", json={"email": "late@example.com", "password": "password123", "name": "Late", "username": "late_one"})
    assert r.status_code == 403
    client.patch("/admin/settings", headers=h, json={"signup_enabled": True, "user_limit": 1})
    r = client.post("/auth/signup", json={"email": "late@example.com", "password": "password123", "name": "Late", "username": "late_one"})
    assert r.status_code == 403
    client.patch("/admin/settings", headers=h, json={"user_limit": 1000})

    a = client.post("/admin/announcements", headers=h, json={"title": "Update", "body": "New version", "kind": "update"}).json()
    assert client.get("/config").json()["announcement"]["id"] == a["id"]
    # Turning the account off signed it out: sign in again.
    again = client.post("/auth/login", json={"email": user["email"], "password": "password123"}).json()
    uh = {"Authorization": f"Bearer {again['access_token']}"}
    assert client.get("/announcements", headers=uh).json()[0]["id"] == a["id"]
    client.patch(f"/admin/announcements/{a['id']}", headers=h, json={"active": False})
    assert client.get("/config").json()["announcement"] is None


def test_delete_account(client):
    a = signup(client, "Leaving")
    b = signup(client, "Staying")
    chat = client.post("/chats/direct", headers=a["h"], json={"user_id": b["id"]}).json()
    send(client, a, chat["id"], "bye")
    g = client.post("/chats/groups", headers=a["h"], json={"name": "Left behind", "member_ids": [b["id"]]}).json()
    assert client.delete("/me", headers=a["h"]).status_code == 200
    assert client.get("/me", headers=a["h"]).status_code == 401
    assert chat_of(client, b, chat["id"])["name"] == "Deleted account"
    assert chat_of(client, b, g["id"])["my_role"] == "admin"
    r = client.post(f"/chats/{chat['id']}/messages", headers=b["h"], json={"client_id": "d1", "kind": "text", "body": "?"})
    assert r.status_code == 403
    # The email can be used again.
    signup(client, "Again", email=a["email"])


def test_websocket_events(client):
    a = signup(client, "Wsa")
    b = signup(client, "Wsb")
    chat = client.post("/chats/direct", headers=a["h"], json={"user_id": b["id"]}).json()
    def next_of(ws, kind):
        # Online status can arrive at any moment: skip what we don't test.
        for _ in range(20):
            event = ws.receive_json()
            if event["type"] == kind:
                return event
        raise AssertionError(f"no {kind} event")

    with client.websocket_connect(f"/ws?token={b['access_token']}") as ws_b:
        with client.websocket_connect(f"/ws?token={a['access_token']}") as ws_a:
            first = next_of(ws_b, "presence")
            assert first["user_id"] == a["id"] and first["online"] is True
            ws_a.send_json({"type": "typing", "chat_id": chat["id"]})
            assert next_of(ws_b, "typing") == {"type": "typing", "chat_id": chat["id"], "user_id": a["id"]}
            send(client, a, chat["id"], "live")
            event = next_of(ws_b, "message.new")
            assert event["message"]["body"] == "live"
            assert next_of(ws_b, "receipt")["user_id"] == a["id"]
            assert client.get(f"/users/{a['id']}", headers=b["h"]).json()["online"] is True
            ws_a.send_json({"type": "ping"})
            assert next_of(ws_a, "pong")["type"] == "pong"
    with pytest.raises(Exception):
        with client.websocket_connect("/ws?token=bad") as ws:
            ws.receive_json()
