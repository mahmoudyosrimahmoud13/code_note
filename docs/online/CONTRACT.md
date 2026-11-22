# CodeNote Online: backend contract

CodeNote Online is the local CodeNote plus accounts, chat and notes sync.
It ships as two builds from the same code:

| Build | Backend | Who runs it |
|---|---|---|
| `BACKEND=supabase` | Supabase (Postgres, Auth, Realtime, Storage, an Edge Function for push) | Supabase hosts it. You paste the project URL and anon key at build time. |
| `BACKEND=fastapi` | The FastAPI server in `server/` (Postgres or SQLite) | You host it. The app asks for the server address the first time it opens. |

Both backends store the same data with the same rules, and the app talks to
them through one Dart interface (`lib/online/backend/backend.dart`). Firebase
is used only for Cloud Messaging (push when the app is closed).

## Data

All ids are UUID strings. Times are UTC ISO 8601 (`2026-11-22T10:00:00Z`).

**Profile**
`{id, email?, name, username, avatar_url, about, is_admin, is_disabled, created_at, last_seen_at, online?}`
`email` is only shown to the person themself and to admins.

**Chat summary** (the chat list)
```
{id, is_group, name, description, image_url, admin_only, created_by,
 created_at, updated_at, last_message, unread, muted, my_role,
 member_count, other_user}
```
- `other_user` is the other person's profile in a direct chat, null in groups.
- `my_role` is `admin` or `member`. Direct chats have no admins.
- `unread` counts messages after my read mark that I didn't send.

**Chat details** = summary + `members: [{user: Profile, role, joined_at, read_seq, delivered_seq}]`.

**Message**
```
{id, seq, chat_id, sender_id, client_id, kind, body, payload,
 reply_to, reactions, pinned, edited, deleted, created_at}
```
- `seq` is a number that only goes up, across all chats. Pages and read
  marks use it.
- `kind`: `text`, `note` (payload is a whole note), `block` (payload is one
  block), `image` (payload `{url, width?, height?}`, body is the caption),
  `system` (payload `{event, actor_id, target_id?, name?}`; events:
  `created`, `added`, `removed`, `left`, `renamed`, `promoted`, `demoted`).
- `reply_to`: `{id, sender_id, kind, body}`, a copy made when sending, so it
  still shows if the original changes.
- `reactions`: `{user_id: emoji}`. One reaction per person per message.
- A deleted message keeps its place: `deleted: true`, `body: ""`, no payload.
- `client_id` is made by the app. Sending the same `client_id` twice gives
  back the first message, so a retry never sends twice.

**Message ticks** come from each member's `read_seq` and `delivered_seq`:
seen when every other member has `read_seq >= seq`, delivered when every
other member has `delivered_seq >= seq`, otherwise sent. This works the same
in groups (the info sheet lists who has seen it).

**Synced item** (notes sync)
`{kind: "note" | "group", id, data, deleted, rev, updated_at}`
`data` is the note or folder JSON the app already uses. `rev` goes up per
account. Last change wins, by the note's own `lastModified` (or the time it
was deleted).

**Announcement** `{id, title, body, kind: info|warning|update, created_at, active}`
**App settings** `{signup_enabled, user_limit, maintenance_message}`

## Rules (both backends)

- The first account ever created is an admin. Admins can make others admins.
- A disabled account can't sign in or do anything.
- Sign-up fails when it's turned off or the user limit is reached.
- Usernames: 3 to 24 characters, `a-z 0-9 _ .`, unique, not case sensitive.
- Direct chats: one per pair of people. Either person blocking the other
  stops new messages and new direct chats. Search hides blocked people.
- Deleting a direct chat hides it and its history for me only. A new
  message brings it back without the old history.
- Groups: the creator is an admin. Admins rename, change the picture and
  description, add or remove people, make or remove admins, turn on
  "only admins can send", pin messages and delete anyone's message.
  The last admin leaving makes the longest member an admin.
  An admin can delete the group for everyone.
- In direct chats either person can pin.
- Only the sender edits a message (text only). The sender, or a group
  admin, deletes it for everyone.

## FastAPI server API

Auth uses `Authorization: Bearer <access token>`. Errors are
`{"detail": "plain words"}` with a normal HTTP status.

| Method | Path | Body / query | Returns |
|---|---|---|---|
| GET | `/health` | | `{app: "codenote", version, name}` (the app checks this when you enter the address) |
| GET | `/config` | | `{signup_enabled, maintenance_message, google_client_ids, email_verification, announcement}` |
| POST | `/auth/signup` | `{email, password, name, username}` | Session |
| POST | `/auth/login` | `{email, password}` | Session |
| POST | `/auth/google` | `{id_token}` | Session |
| POST | `/auth/refresh` | `{refresh_token}` | Session |
| POST | `/auth/logout` | `{refresh_token}` | |
| POST | `/auth/verify/send` | | sends a 6-digit code |
| POST | `/auth/verify` | `{code}` | Profile |
| POST | `/auth/password/forgot` | `{email}` | sends a 6-digit code |
| POST | `/auth/password/reset` | `{email, code, password}` | |
| POST | `/auth/password/change` | `{old_password, password}` | |
| GET / PATCH / DELETE | `/me` | `{name?, username?, about?, avatar_url?}` | Profile |
| GET | `/users/username-available?username=` | | `{available}` |
| GET | `/users/search?q=` | | `[Profile]` |
| GET | `/users/{id}` | | Profile + `{blocked_by_me, common_groups}` |
| GET | `/me/blocks` | | `[Profile]` |
| PUT / DELETE | `/users/{id}/block` | | |
| GET | `/chats` | | `[Chat summary]` |
| POST | `/chats/direct` | `{user_id}` | Chat summary |
| POST | `/chats/groups` | `{name, description?, image_url?, member_ids, admin_only?}` | Chat details |
| GET / PATCH / DELETE | `/chats/{id}` | `{name?, description?, image_url?, admin_only?}` | Chat details |
| POST | `/chats/{id}/members` | `{user_ids}` | Chat details |
| PATCH / DELETE | `/chats/{id}/members/{user_id}` | `{role}` | Chat details (DELETE of yourself = leave) |
| PATCH | `/chats/{id}/me` | `{muted}` | |
| POST | `/chats/{id}/read` | `{seq?}` | |
| POST | `/chats/{id}/delivered` | `{seq?}` | |
| GET | `/chats/{id}/messages` | `before_seq?, after_seq?, limit?` | `[Message]` newest first |
| GET | `/chats/{id}/pinned` | | `[Message]` |
| POST | `/chats/{id}/messages` | `{client_id, kind, body, payload?, reply_to_id?}` | Message |
| PATCH / DELETE | `/messages/{id}` | `{body}` | Message |
| PUT | `/messages/{id}/pin` | `{pinned}` | Message |
| PUT / DELETE | `/messages/{id}/reaction` | `{emoji}` | Message |
| POST | `/files` | multipart `file` (images, 15 MB) | `{url}` |
| POST / DELETE | `/devices` | `{token, platform}` | |
| GET | `/sync` | `since` | `{rev, items}` |
| POST | `/sync` | `{items: [{kind, id, data, deleted}]}` | `{rev, applied, conflicts: [Synced item]}` |
| GET | `/announcements` | | `[Announcement]` |
| GET | `/admin/stats` | | `{users, active_today, chats, messages, groups}` |
| GET | `/admin/users` | `q?` | `[Profile]` with email |
| PATCH | `/admin/users/{id}` | `{is_disabled?, is_admin?}` | Profile |
| GET / PATCH | `/admin/settings` | App settings | App settings |
| POST | `/admin/announcements` | `{title, body, kind}` | Announcement |
| PATCH | `/admin/announcements/{id}` | `{active}` | Announcement |

Session: `{access_token, refresh_token, expires_in, user: Profile}`.

### Live updates: `GET /ws?token=<access token>` (WebSocket)

The server sends JSON events. The app sends `{"type": "typing", "chat_id"}`
and `{"type": "ping"}`.

| Event | Fields |
|---|---|
| `message.new` | `chat_id, message` |
| `message.updated` | `chat_id, message` (edit, delete, pin, reactions) |
| `chat.updated` | `chat_id` (details, members, settings changed: fetch again) |
| `chat.removed` | `chat_id` (removed, left or deleted) |
| `receipt` | `chat_id, user_id, read_seq, delivered_seq` |
| `typing` | `chat_id, user_id` |
| `presence` | `user_id, online, last_seen_at` |
| `announcement` | `announcement` |
| `sync` | `rev` (another device changed notes) |
| `account.disabled` | |

## Supabase

The same tables live in Postgres (`supabase/migrations`). The app reads with
plain selects (row-level security lets you see only your own chats) and
writes through SQL functions (`rpc`) that apply the rules above. Live
updates come from Realtime changes on `messages`, `chat_members`, `chats`,
`synced_items` and `announcements`, turned into the same events as the
WebSocket. Typing and online status use Realtime broadcast and presence.
Push: a database trigger calls the `push` Edge Function, which sends
through FCM.
