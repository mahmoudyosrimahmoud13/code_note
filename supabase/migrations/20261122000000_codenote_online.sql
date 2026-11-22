-- CodeNote Online on Supabase.
-- The same tables and rules as the FastAPI server (docs/online/CONTRACT.md).
-- The app reads through these functions and a few plain selects; every
-- write goes through a function, so the rules can't be skipped.
--
-- Run it once: Supabase dashboard > SQL Editor > paste this file > Run.
-- Or with the Supabase CLI:  supabase db push

create extension if not exists pgcrypto;

do $$ begin
  create extension if not exists pg_net;  -- for push (database to Edge Function)
exception when others then
  raise notice 'pg_net is not available: push notifications stay off.';
end $$;

-- ─── Tables ──────────────────────────────────────────────────────────

create table if not exists public.profiles (
  id uuid primary key,
  email text not null default '',
  name text not null default '',
  username text,
  avatar_url text,
  about text not null default '',
  is_admin boolean not null default false,
  is_disabled boolean not null default false,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  sync_rev bigint not null default 0
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  dm_key text unique,
  name text not null default '',
  description text not null default '',
  image_url text,
  admin_only boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_seq bigint
);

create table if not exists public.chat_members (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  read_seq bigint not null default 0,
  delivered_seq bigint not null default 0,
  hidden_seq bigint not null default 0,
  hidden boolean not null default false,
  muted boolean not null default false,
  primary key (chat_id, user_id)
);
create index if not exists chat_members_user on public.chat_members (user_id);

create table if not exists public.messages (
  seq bigserial unique,
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid,
  client_id text,
  kind text not null default 'text' check (kind in ('text', 'note', 'block', 'image', 'system')),
  body text not null default '',
  payload jsonb,
  reply_to_id uuid,
  reply_preview jsonb,
  reactions jsonb not null default '{}'::jsonb,
  pinned_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (sender_id, client_id)
);
create index if not exists messages_chat_seq on public.messages (chat_id, seq);

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);

create table if not exists public.synced_items (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('note', 'group')),
  item_id text not null,
  data jsonb,
  deleted boolean not null default false,
  modified_at timestamptz not null default now(),
  rev bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (owner_id, kind, item_id)
);
create index if not exists synced_owner_rev on public.synced_items (owner_id, rev);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  kind text not null default 'info' check (kind in ('info', 'warning', 'update')),
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  signup_enabled boolean not null default true,
  user_limit int not null default 1000,
  maintenance_message text not null default ''
);
insert into public.app_settings (id) values (1) on conflict do nothing;

-- Where the database sends new messages for push (filled in by you, see
-- docs/online/SUPABASE.md). Not readable by the app.
create schema if not exists private;
create table if not exists private.push_config (
  id int primary key default 1 check (id = 1),
  url text not null,
  secret text not null
);

-- ─── Helpers ─────────────────────────────────────────────────────────

-- The signed-in person. Stops anyone signed out, deleted or turned off.
create or replace function public._me() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p public.profiles;
begin
  if uid is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;
  select * into p from public.profiles where id = uid;
  if not found or p.is_deleted then
    raise exception 'This account no longer exists.' using errcode = '28000';
  end if;
  if p.is_disabled then
    raise exception 'This account was turned off by an admin.' using errcode = '42501';
  end if;
  if p.last_seen_at is null or p.last_seen_at < now() - interval '1 minute' then
    update public.profiles set last_seen_at = now() where id = uid;
  end if;
  return uid;
end $$;

create or replace function public._is_member(p_chat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_members m
    join public.profiles p on p.id = m.user_id
    where m.chat_id = p_chat and m.user_id = auth.uid() and not p.is_disabled
  )
$$;

create or replace function public._iso(t timestamptz) returns text
language sql immutable as $$
  select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

create or replace function public._profile(p public.profiles, viewer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  show_email boolean;
begin
  if p.is_deleted then
    return jsonb_build_object('id', p.id, 'name', 'Deleted account', 'username', null, 'avatar_url', null,
      'about', '', 'is_admin', false, 'is_disabled', false, 'is_deleted', true,
      'created_at', _iso(p.created_at), 'last_seen_at', null);
  end if;
  show_email := viewer = p.id or exists (select 1 from public.profiles where id = viewer and is_admin);
  return jsonb_build_object('id', p.id, 'name', p.name, 'username', p.username, 'avatar_url', p.avatar_url,
    'about', p.about, 'is_admin', p.is_admin, 'is_disabled', p.is_disabled, 'is_deleted', false,
    'created_at', _iso(p.created_at), 'last_seen_at', _iso(p.last_seen_at))
    || case when show_email then jsonb_build_object('email', p.email) else '{}'::jsonb end;
end $$;

create or replace function public._message(m public.messages) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', m.id, 'seq', m.seq, 'chat_id', m.chat_id, 'sender_id', m.sender_id, 'client_id', m.client_id,
    'kind', m.kind,
    'body', case when m.deleted_at is null then m.body else '' end,
    'payload', case when m.deleted_at is null then m.payload else null end,
    'reply_to', case when m.deleted_at is null then m.reply_preview else null end,
    'reactions', case when m.deleted_at is null then m.reactions else '{}'::jsonb end,
    'pinned', m.pinned_at is not null and m.deleted_at is null,
    'edited', m.edited_at is not null,
    'deleted', m.deleted_at is not null,
    'created_at', _iso(m.created_at))
$$;

create or replace function public._snippet(p_kind text, p_body text, p_payload jsonb) returns text
language sql immutable as $$
  select case p_kind
    when 'image' then case when p_body <> '' then '📷 ' || p_body else '📷 Photo' end
    when 'note' then '📝 Note: ' || coalesce(nullif(p_payload->>'title', ''), 'Untitled')
    when 'block' then case when p_body <> '' then left('‹/› Code: ' || p_body, 120) else '‹/› Code block' end
    else left(p_body, 200)
  end
$$;

-- 'me' if I blocked them, 'them' if they blocked me.
create or replace function public._blocked(a uuid, b uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.blocks where blocker_id = a and blocked_id = b) then 'me'
    when exists (select 1 from public.blocks where blocker_id = b and blocked_id = a) then 'them'
  end
$$;

create or replace function public._clean_username(p text) returns text
language plpgsql immutable as $$
declare u text := lower(ltrim(trim(coalesce(p, '')), '@'));
begin
  if u !~ '^[a-z0-9_.]{3,24}$' then
    raise exception 'Usernames are 3 to 24 characters: letters, numbers, _ and .' using errcode = '22023';
  end if;
  return u;
end $$;

-- ─── Chat summaries ──────────────────────────────────────────────────

create or replace function public._summaries(p_me uuid, p_chat uuid default null, p_include_hidden boolean default false)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row order by updated_at desc), '[]'::jsonb) from (
    select c.updated_at, jsonb_build_object(
      'id', c.id,
      'is_group', c.is_group,
      'name', case when c.is_group then c.name
                   when o.id is null or o.is_deleted then 'Deleted account' else o.name end,
      'description', c.description,
      'image_url', case when c.is_group then c.image_url
                        when o.is_deleted then null else o.avatar_url end,
      'admin_only', c.admin_only,
      'created_by', c.created_by,
      'created_at', _iso(c.created_at),
      'updated_at', _iso(c.updated_at),
      'last_message', (select _message(lm) from public.messages lm
                        where lm.seq = c.last_message_seq and lm.seq > me.hidden_seq),
      'unread', (select count(*) from public.messages u
                  where u.chat_id = c.id and u.seq > me.read_seq and u.seq > me.hidden_seq
                    and u.deleted_at is null and u.kind <> 'system'
                    and u.sender_id is distinct from p_me),
      'muted', me.muted,
      'my_role', me.role,
      'member_count', (select count(*) from public.chat_members x where x.chat_id = c.id),
      'other_user', case when o.id is null then null else _profile(o, p_me) end,
      'blocked', case when c.is_group or o.id is null then null else _blocked(p_me, o.id) end,
      'my_read_seq', me.read_seq,
      'hidden_seq', me.hidden_seq
    ) as row
    from public.chats c
    join public.chat_members me on me.chat_id = c.id and me.user_id = p_me
    left join lateral (
      select p.* from public.chat_members om join public.profiles p on p.id = om.user_id
      where not c.is_group and om.chat_id = c.id and om.user_id <> p_me limit 1
    ) o on true
    where (p_include_hidden or not me.hidden)
      and (p_chat is null or c.id = p_chat)
  ) s
$$;

create or replace function public.my_chats() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return _summaries(_me());
end $$;

create or replace function public.chat_details(p_chat uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  out jsonb;
begin
  out := _summaries(uid, p_chat, true) -> 0;
  if out is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  return out || jsonb_build_object('members', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user', _profile(p, uid), 'role', m.role, 'joined_at', _iso(m.joined_at),
      'read_seq', m.read_seq, 'delivered_seq', m.delivered_seq) order by m.joined_at), '[]'::jsonb)
    from public.chat_members m join public.profiles p on p.id = m.user_id
    where m.chat_id = p_chat));
end $$;

-- ─── Posting ─────────────────────────────────────────────────────────

create or replace function public._post(p_chat uuid, p_sender uuid, p_kind text, p_body text, p_payload jsonb,
  p_reply uuid default null, p_client text default null) returns public.messages
language plpgsql security definer set search_path = public as $$
declare
  m public.messages;
  r public.messages;
begin
  if p_reply is not null then
    select * into r from public.messages where id = p_reply and chat_id = p_chat and deleted_at is null;
  end if;
  insert into public.messages (chat_id, sender_id, client_id, kind, body, payload, reply_to_id, reply_preview)
  values (p_chat, p_sender, p_client, p_kind, coalesce(p_body, ''), p_payload,
          r.id, case when r.id is null then null else jsonb_build_object(
            'id', r.id, 'sender_id', r.sender_id, 'kind', r.kind, 'body', _snippet(r.kind, r.body, r.payload)) end)
  returning * into m;
  update public.chats set last_message_seq = m.seq, updated_at = now() where id = p_chat;
  update public.chat_members set hidden = false where chat_id = p_chat and hidden;
  if p_sender is not null then
    update public.chat_members set read_seq = m.seq, delivered_seq = m.seq
    where chat_id = p_chat and user_id = p_sender;
  end if;
  return m;
end $$;

create or replace function public._system(p_chat uuid, p_actor uuid, p_event text, p_target uuid default null,
  p_name text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _post(p_chat, null, 'system', '', jsonb_strip_nulls(jsonb_build_object(
    'event', p_event, 'actor_id', p_actor, 'target_id', p_target, 'name', p_name)));
end $$;

create or replace function public.send_message(p_chat uuid, p_client_id text, p_kind text, p_body text default '',
  p_payload jsonb default null, p_reply_to uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  c public.chats;
  me_row public.chat_members;
  existing public.messages;
  other public.profiles;
  b text;
  m public.messages;
begin
  select * into c from public.chats where id = p_chat;
  select * into me_row from public.chat_members where chat_id = p_chat and user_id = uid;
  if c.id is null or me_row.chat_id is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  -- A retry of a message that already arrived: give back the first one.
  select * into existing from public.messages where sender_id = uid and client_id = p_client_id;
  if existing.id is not null then
    return _message(existing);
  end if;
  if p_kind not in ('text', 'note', 'block', 'image') then
    raise exception 'Unknown message kind.' using errcode = '22023';
  end if;
  if p_kind = 'text' and trim(coalesce(p_body, '')) = '' then
    raise exception 'The message is empty.' using errcode = '22023';
  end if;
  if p_kind = 'image' and coalesce(p_payload->>'url', '') = '' then
    raise exception 'The picture is missing.' using errcode = '22023';
  end if;
  if p_kind in ('note', 'block') and p_payload is null then
    raise exception 'The note is missing.' using errcode = '22023';
  end if;
  if length(coalesce(p_body, '')) > 20000 or length(coalesce(p_payload::text, '')) > 1000000 then
    raise exception 'That message is too big to send.' using errcode = '22023';
  end if;
  if c.is_group and c.admin_only and me_row.role <> 'admin' then
    raise exception 'Only admins can send messages in this group.' using errcode = '42501';
  end if;
  if not c.is_group then
    select p.* into other from public.chat_members om join public.profiles p on p.id = om.user_id
    where om.chat_id = p_chat and om.user_id <> uid;
    if other.id is null or other.is_deleted then
      raise exception 'This account was deleted.' using errcode = '42501';
    end if;
    b := _blocked(uid, other.id);
    if b = 'me' then
      raise exception 'You blocked this person. Unblock them to send messages.' using errcode = '42501';
    elsif b = 'them' then
      raise exception 'You can''t message this person.' using errcode = '42501';
    end if;
  end if;
  m := _post(p_chat, uid, p_kind, p_body, p_payload, p_reply_to, p_client_id);
  return _message(m);
end $$;

create or replace function public.get_messages(p_chat uuid, p_before bigint default null, p_after bigint default null,
  p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  hidden bigint;
  lim int := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  select hidden_seq into hidden from public.chat_members where chat_id = p_chat and user_id = uid;
  if hidden is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  if p_after is not null then
    return (select coalesce(jsonb_agg(_message(x) order by x.seq desc), '[]'::jsonb) from (
      select * from public.messages where chat_id = p_chat and seq > hidden and seq > p_after
      order by seq asc limit lim) x);
  end if;
  return (select coalesce(jsonb_agg(_message(x) order by x.seq desc), '[]'::jsonb) from (
    select * from public.messages where chat_id = p_chat and seq > hidden
      and (p_before is null or seq < p_before)
    order by seq desc limit lim) x);
end $$;

create or replace function public.pinned_messages(p_chat uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  hidden bigint;
begin
  select hidden_seq into hidden from public.chat_members where chat_id = p_chat and user_id = uid;
  if hidden is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  return (select coalesce(jsonb_agg(_message(m) order by m.pinned_at desc), '[]'::jsonb)
    from public.messages m where m.chat_id = p_chat and m.pinned_at is not null
      and m.deleted_at is null and m.seq > hidden);
end $$;

-- Loads a message the caller may change. Returns (message, chat, my membership).
create or replace function public._my_message(p_id uuid, out m public.messages, out c public.chats,
  out mem public.chat_members)
language plpgsql security definer set search_path = public as $$
begin
  select * into m from public.messages where id = p_id;
  select * into c from public.chats where id = m.chat_id;
  select * into mem from public.chat_members where chat_id = m.chat_id and user_id = _me();
  if m.id is null or mem.chat_id is null or m.seq <= mem.hidden_seq then
    raise exception 'This message doesn''t exist.' using errcode = 'P0002';
  end if;
end $$;

create or replace function public.edit_message(p_id uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record;
  m public.messages;
begin
  select * into x from _my_message(p_id);
  m := x.m;
  if m.sender_id is distinct from auth.uid() then
    raise exception 'You can only edit your own messages.' using errcode = '42501';
  end if;
  if m.deleted_at is not null then
    raise exception 'This message was deleted.' using errcode = '22023';
  end if;
  if m.kind not in ('text', 'image') then
    raise exception 'Only text and captions can be edited.' using errcode = '22023';
  end if;
  if trim(coalesce(p_body, '')) = '' then
    raise exception 'The message is empty.' using errcode = '22023';
  end if;
  if trim(p_body) <> trim(m.body) then
    update public.messages set body = p_body, edited_at = now() where id = p_id returning * into m;
  end if;
  return _message(m);
end $$;

create or replace function public.delete_message(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record;
  m public.messages;
begin
  select * into x from _my_message(p_id);
  m := x.m;
  if m.sender_id is distinct from auth.uid() and not ((x.c).is_group and (x.mem).role = 'admin') then
    raise exception 'You can only delete your own messages.' using errcode = '42501';
  end if;
  if m.kind = 'system' then
    raise exception 'That can''t be deleted.' using errcode = '22023';
  end if;
  update public.messages set deleted_at = coalesce(deleted_at, now()), body = '', payload = null,
    reactions = '{}'::jsonb, pinned_at = null where id = p_id returning * into m;
  return _message(m);
end $$;

create or replace function public.pin_message(p_id uuid, p_pinned boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record;
  m public.messages;
begin
  select * into x from _my_message(p_id);
  if (x.c).is_group and (x.mem).role <> 'admin' then
    raise exception 'Only group admins can pin messages.' using errcode = '42501';
  end if;
  if (x.m).deleted_at is not null or (x.m).kind = 'system' then
    raise exception 'That message can''t be pinned.' using errcode = '22023';
  end if;
  update public.messages set pinned_at = case when p_pinned then now() end where id = p_id returning * into m;
  return _message(m);
end $$;

create or replace function public.react(p_id uuid, p_emoji text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record;
  m public.messages;
begin
  select * into x from _my_message(p_id);
  if (x.m).deleted_at is not null or (x.m).kind = 'system' then
    raise exception 'You can''t react to that.' using errcode = '22023';
  end if;
  if p_emoji is null or length(p_emoji) = 0 or length(p_emoji) > 16 then
    raise exception 'Pick an emoji.' using errcode = '22023';
  end if;
  update public.messages set reactions = reactions || jsonb_build_object(auth.uid()::text, p_emoji)
  where id = p_id returning * into m;
  return _message(m);
end $$;

create or replace function public.unreact(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  x record;
  m public.messages;
begin
  select * into x from _my_message(p_id);
  update public.messages set reactions = reactions - auth.uid()::text where id = p_id returning * into m;
  return _message(m);
end $$;

-- ─── Chats and groups ────────────────────────────────────────────────

create or replace function public.start_direct(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  other public.profiles;
  key text;
  cid uuid;
  b text;
begin
  if p_user = uid then
    raise exception 'You can''t start a chat with yourself.' using errcode = '22023';
  end if;
  select * into other from public.profiles where id = p_user;
  if other.id is null or other.is_deleted or other.is_disabled then
    raise exception 'This person isn''t available.' using errcode = 'P0002';
  end if;
  key := least(uid::text, p_user::text) || ':' || greatest(uid::text, p_user::text);
  select id into cid from public.chats where dm_key = key;
  if cid is null then
    b := _blocked(uid, p_user);
    if b = 'me' then
      raise exception 'You blocked this person. Unblock them to chat.' using errcode = '42501';
    elsif b = 'them' then
      raise exception 'You can''t message this person.' using errcode = '42501';
    end if;
    insert into public.chats (is_group, dm_key, created_by) values (false, key, uid)
    on conflict (dm_key) do update set dm_key = excluded.dm_key
    returning id into cid;
    insert into public.chat_members (chat_id, user_id) values (cid, uid), (cid, p_user)
    on conflict do nothing;
  end if;
  return chat_details(cid);
end $$;

create or replace function public.create_group(p_name text, p_description text default '', p_image_url text default null,
  p_member_ids uuid[] default '{}', p_admin_only boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  cid uuid;
begin
  if trim(coalesce(p_name, '')) = '' or length(p_name) > 80 then
    raise exception 'Give the group a name (80 characters at most).' using errcode = '22023';
  end if;
  insert into public.chats (is_group, name, description, image_url, admin_only, created_by)
  values (true, trim(p_name), trim(coalesce(p_description, '')), p_image_url, coalesce(p_admin_only, false), uid)
  returning id into cid;
  insert into public.chat_members (chat_id, user_id, role) values (cid, uid, 'admin');
  insert into public.chat_members (chat_id, user_id)
  select cid, p.id from public.profiles p
  where p.id = any(p_member_ids) and p.id <> uid and not p.is_deleted and not p.is_disabled
  on conflict do nothing;
  perform _system(cid, uid, 'created', null, trim(p_name));
  return chat_details(cid);
end $$;

create or replace function public._admin_of(p_chat uuid) returns public.chats
language plpgsql security definer set search_path = public as $$
declare
  c public.chats;
  r text;
begin
  select * into c from public.chats where id = p_chat;
  select role into r from public.chat_members where chat_id = p_chat and user_id = _me();
  if c.id is null or r is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  if not c.is_group then
    raise exception 'That only works in groups.' using errcode = '22023';
  end if;
  if r <> 'admin' then
    raise exception 'Only group admins can do this.' using errcode = '42501';
  end if;
  return c;
end $$;

create or replace function public.update_group(p_chat uuid, p_name text default null, p_description text default null,
  p_image_url text default null, p_admin_only boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.chats := _admin_of(p_chat);
begin
  if p_name is not null and (trim(p_name) = '' or length(p_name) > 80) then
    raise exception 'Give the group a name (80 characters at most).' using errcode = '22023';
  end if;
  update public.chats set
    name = coalesce(trim(p_name), name),
    description = coalesce(trim(p_description), description),
    image_url = case when p_image_url is null then image_url else nullif(p_image_url, '') end,
    admin_only = coalesce(p_admin_only, admin_only),
    updated_at = now()
  where id = p_chat;
  if p_name is not null and trim(p_name) <> c.name then
    perform _system(p_chat, auth.uid(), 'renamed', null, trim(p_name));
  end if;
  return chat_details(p_chat);
end $$;

create or replace function public.delete_chat(p_chat uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  c public.chats;
  mem public.chat_members;
begin
  select * into c from public.chats where id = p_chat;
  select * into mem from public.chat_members where chat_id = p_chat and user_id = uid;
  if c.id is null or mem.chat_id is null then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  if c.is_group then
    perform _admin_of(p_chat);
    delete from public.chats where id = p_chat;
  else
    update public.chat_members set hidden = true, hidden_seq = coalesce(c.last_message_seq, 0),
      read_seq = greatest(read_seq, coalesce(c.last_message_seq, 0))
    where chat_id = p_chat and user_id = uid;
  end if;
end $$;

create or replace function public.add_members(p_chat uuid, p_user_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.chats := _admin_of(p_chat);
  p record;
begin
  for p in
    select pr.id from public.profiles pr
    where pr.id = any(p_user_ids) and not pr.is_deleted and not pr.is_disabled
      and not exists (select 1 from public.chat_members m where m.chat_id = p_chat and m.user_id = pr.id)
  loop
    -- New people start after the current last message (old ones aren't unread).
    insert into public.chat_members (chat_id, user_id, read_seq, delivered_seq)
    values (p_chat, p.id, coalesce(c.last_message_seq, 0), coalesce(c.last_message_seq, 0));
    perform _system(p_chat, auth.uid(), 'added', p.id);
  end loop;
  return chat_details(p_chat);
end $$;

create or replace function public.set_member_role(p_chat uuid, p_user uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.chats := _admin_of(p_chat);
  current_role_ text;
begin
  if p_role not in ('admin', 'member') then
    raise exception 'The role is admin or member.' using errcode = '22023';
  end if;
  select role into current_role_ from public.chat_members where chat_id = p_chat and user_id = p_user;
  if current_role_ is null then
    raise exception 'This person isn''t in the group.' using errcode = 'P0002';
  end if;
  if p_role = 'member' and current_role_ = 'admin'
     and (select count(*) from public.chat_members where chat_id = p_chat and role = 'admin') <= 1 then
    raise exception 'A group needs at least one admin. Make someone else an admin first.' using errcode = '22023';
  end if;
  if current_role_ <> p_role then
    update public.chat_members set role = p_role where chat_id = p_chat and user_id = p_user;
    perform _system(p_chat, auth.uid(), case when p_role = 'admin' then 'promoted' else 'demoted' end, p_user);
  end if;
  return chat_details(p_chat);
end $$;

-- Takes someone out of a group (yourself = leave). Keeps one admin; an
-- empty group is deleted.
create or replace function public._remove_member(p_chat uuid, p_user uuid, p_actor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  was_admin boolean;
  next_member uuid;
begin
  delete from public.chat_members where chat_id = p_chat and user_id = p_user returning role = 'admin' into was_admin;
  if was_admin is null then
    return;
  end if;
  if not exists (select 1 from public.chat_members where chat_id = p_chat) then
    delete from public.chats where id = p_chat;
    return;
  end if;
  if was_admin and not exists (select 1 from public.chat_members where chat_id = p_chat and role = 'admin') then
    select user_id into next_member from public.chat_members where chat_id = p_chat order by joined_at limit 1;
    update public.chat_members set role = 'admin' where chat_id = p_chat and user_id = next_member;
  end if;
  if p_actor = p_user then
    perform _system(p_chat, p_actor, 'left');
  else
    perform _system(p_chat, p_actor, 'removed', p_user);
  end if;
end $$;

create or replace function public.remove_member(p_chat uuid, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  c public.chats;
begin
  select * into c from public.chats where id = p_chat;
  if c.id is null or not exists (select 1 from public.chat_members where chat_id = p_chat and user_id = uid) then
    raise exception 'This chat doesn''t exist, or you''re not in it.' using errcode = 'P0002';
  end if;
  if not c.is_group then
    raise exception 'That only works in groups.' using errcode = '22023';
  end if;
  if p_user <> uid then
    perform _admin_of(p_chat);
  end if;
  if not exists (select 1 from public.chat_members where chat_id = p_chat and user_id = p_user) then
    raise exception 'This person isn''t in the group.' using errcode = 'P0002';
  end if;
  perform _remove_member(p_chat, p_user, uid);
  if p_user = uid then
    return null;
  end if;
  return chat_details(p_chat);
end $$;

create or replace function public.set_muted(p_chat uuid, p_muted boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.chat_members set muted = p_muted where chat_id = p_chat and user_id = _me();
end $$;

create or replace function public.mark_read(p_chat uuid, p_seq bigint default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  top bigint;
  v bigint;
begin
  select coalesce(last_message_seq, 0) into top from public.chats where id = p_chat;
  v := least(coalesce(p_seq, top), top);
  update public.chat_members set read_seq = greatest(read_seq, v), delivered_seq = greatest(delivered_seq, v)
  where chat_id = p_chat and user_id = _me() and (read_seq < v or delivered_seq < v);
end $$;

create or replace function public.mark_delivered(p_chat uuid, p_seq bigint default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  top bigint;
  v bigint;
begin
  select coalesce(last_message_seq, 0) into top from public.chats where id = p_chat;
  v := least(coalesce(p_seq, top), top);
  update public.chat_members set delivered_seq = v
  where chat_id = p_chat and user_id = _me() and delivered_seq < v;
end $$;

create or replace function public.mark_all_delivered() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.chat_members m set delivered_seq = c.last_message_seq
  from public.chats c
  where c.id = m.chat_id and m.user_id = _me() and c.last_message_seq > m.delivered_seq;
end $$;

-- ─── People ──────────────────────────────────────────────────────────

create or replace function public.me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  return (select _profile(p, uid) from public.profiles p where id = uid);
end $$;

create or replace function public.update_profile(p_name text default null, p_username text default null,
  p_about text default null, p_avatar_url text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  u text;
begin
  if p_username is not null then
    u := _clean_username(p_username);
    if exists (select 1 from public.profiles where lower(username) = u and id <> uid) then
      raise exception 'That username is taken. Try another one.' using errcode = '23505';
    end if;
  end if;
  if p_name is not null and (trim(p_name) = '' or length(p_name) > 80) then
    raise exception 'Your name can''t be empty (80 characters at most).' using errcode = '22023';
  end if;
  update public.profiles set
    name = coalesce(trim(p_name), name),
    username = coalesce(u, username),
    about = coalesce(left(trim(p_about), 300), about),
    avatar_url = case when p_avatar_url is null then avatar_url else nullif(p_avatar_url, '') end
  where id = uid;
  -- Chats with me show the new name and picture.
  update public.chats c set updated_at = c.updated_at
  from public.chat_members m where m.chat_id = c.id and m.user_id = uid;
  return me();
end $$;

create or replace function public.username_available(p_username text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare u text;
begin
  begin
    u := _clean_username(p_username);
  exception when others then
    return false;
  end;
  return not exists (select 1 from public.profiles where lower(username) = u
                     and id is distinct from auth.uid());
end $$;

create or replace function public.search_users(p_query text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  q text := lower(ltrim(trim(coalesce(p_query, '')), '@'));
begin
  if length(q) < 2 then
    return '[]'::jsonb;
  end if;
  return (select coalesce(jsonb_agg(_profile(p, uid) order by
      (lower(p.username) <> q), (lower(p.username) not like q || '%'), p.username), '[]'::jsonb)
    from (select * from public.profiles p
          where p.id <> uid and not p.is_deleted and not p.is_disabled
            and (lower(p.name) like '%' || q || '%' or lower(p.username) like '%' || q || '%' or lower(p.email) = q)
            and _blocked(uid, p.id) is null
          limit 30) p);
end $$;

create or replace function public.get_user(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  p public.profiles;
begin
  select * into p from public.profiles where id = p_id;
  if p.id is null then
    raise exception 'This person doesn''t exist.' using errcode = 'P0002';
  end if;
  return _profile(p, uid) || jsonb_build_object(
    'blocked_by_me', exists (select 1 from public.blocks where blocker_id = uid and blocked_id = p_id),
    'common_groups', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'image_url', c.image_url)), '[]'::jsonb)
      from public.chats c
      where c.is_group
        and exists (select 1 from public.chat_members a where a.chat_id = c.id and a.user_id = uid)
        and exists (select 1 from public.chat_members b where b.chat_id = c.id and b.user_id = p_id)));
end $$;

create or replace function public.my_blocks() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  return (select coalesce(jsonb_agg(_profile(p, uid)), '[]'::jsonb)
    from public.profiles p join public.blocks b on b.blocked_id = p.id where b.blocker_id = uid);
end $$;

create or replace function public.block_user(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  if p_id = uid then
    raise exception 'You can''t block yourself.' using errcode = '22023';
  end if;
  insert into public.blocks (blocker_id, blocked_id) values (uid, p_id) on conflict do nothing;
  update public.chats set updated_at = updated_at
  where dm_key = least(uid::text, p_id::text) || ':' || greatest(uid::text, p_id::text);
end $$;

create or replace function public.unblock_user(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  delete from public.blocks where blocker_id = uid and blocked_id = p_id;
  update public.chats set updated_at = updated_at
  where dm_key = least(uid::text, p_id::text) || ':' || greatest(uid::text, p_id::text);
end $$;

-- Deletes the account. Messages stay, from "Deleted account".
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  uid uuid := _me();
  g record;
begin
  for g in select c.id from public.chats c join public.chat_members m on m.chat_id = c.id
           where m.user_id = uid and c.is_group loop
    perform _remove_member(g.id, uid, uid);
  end loop;
  delete from public.synced_items where owner_id = uid;
  delete from public.device_tokens where user_id = uid;
  delete from public.blocks where blocker_id = uid or blocked_id = uid;
  update public.profiles set is_deleted = true, email = 'deleted-' || uid || '@deleted.invalid',
    username = null, name = 'Deleted account', avatar_url = null, about = '' where id = uid;
  delete from auth.users where id = uid;
end $$;

create or replace function public.register_device(p_token text, p_platform text default 'android') returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  insert into public.device_tokens (token, user_id, platform) values (p_token, uid, coalesce(p_platform, 'android'))
  on conflict (token) do update set user_id = uid, platform = excluded.platform, updated_at = now();
end $$;

create or replace function public.unregister_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
end $$;

-- ─── Notes sync ──────────────────────────────────────────────────────

create or replace function public._synced(s public.synced_items) returns jsonb
language sql stable as $$
  select jsonb_build_object('kind', s.kind, 'id', s.item_id,
    'data', case when s.deleted then null else s.data end,
    'deleted', s.deleted, 'rev', s.rev, 'updated_at', _iso(s.updated_at))
$$;

create or replace function public.sync_pull(p_since bigint default 0, p_limit int default 500) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  items jsonb;
  top bigint;
begin
  select coalesce(jsonb_agg(_synced(s) order by s.rev), '[]'::jsonb), max(s.rev) into items, top
  from (select * from public.synced_items where owner_id = uid and rev > coalesce(p_since, 0)
        order by rev limit greatest(1, least(coalesce(p_limit, 500), 1000))) s;
  return jsonb_build_object('rev', coalesce(top, greatest(coalesce(p_since, 0), 0)),
    'latest', (select sync_rev from public.profiles where id = uid), 'items', items);
end $$;

create or replace function public.sync_push(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _me();
  it jsonb;
  existing public.synced_items;
  is_deleted boolean;
  item_when timestamptz;
  rev bigint;
  applied jsonb := '[]'::jsonb;
  conflicts jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 then
    raise exception 'Send up to 500 items at once.' using errcode = '22023';
  end if;
  -- One device at a time per account, so revisions never repeat.
  select sync_rev into rev from public.profiles where id = uid for update;
  for it in select * from jsonb_array_elements(p_items) loop
    if it->>'kind' not in ('note', 'group') or coalesce(it->>'id', '') = '' then
      raise exception 'Unknown item kind.' using errcode = '22023';
    end if;
    is_deleted := coalesce((it->>'deleted')::boolean, false);
    if not is_deleted and (it->'data') is null then
      raise exception 'The note is missing.' using errcode = '22023';
    end if;
    if length(coalesce((it->'data')::text, '')) > 2000000 then
      raise exception 'A note is too big to sync (2 MB at most).' using errcode = '22023';
    end if;
    item_when := coalesce((it->>'modified_at')::timestamptz, (it->'data'->>'lastModified')::timestamptz, now());
    select * into existing from public.synced_items
    where owner_id = uid and kind = it->>'kind' and item_id = it->>'id';
    if existing.item_id is not null and existing.modified_at > item_when then
      conflicts := conflicts || jsonb_build_array(_synced(existing));  -- the cloud copy is newer
      continue;
    end if;
    rev := rev + 1;
    insert into public.synced_items (owner_id, kind, item_id, data, deleted, modified_at, rev, updated_at)
    values (uid, it->>'kind', it->>'id', case when is_deleted then null else it->'data' end, is_deleted, item_when, rev, now())
    on conflict (owner_id, kind, item_id) do update set data = excluded.data, deleted = excluded.deleted,
      modified_at = excluded.modified_at, rev = excluded.rev, updated_at = now();
    applied := applied || jsonb_build_array(it->>'id');
  end loop;
  update public.profiles set sync_rev = rev where id = uid;
  return jsonb_build_object('rev', rev, 'applied', applied, 'conflicts', conflicts);
end $$;

-- ─── Admin, settings, announcements ──────────────────────────────────

create or replace function public._admin() returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := _me();
begin
  if not (select is_admin from public.profiles where id = uid) then
    raise exception 'Only admins can do this.' using errcode = '42501';
  end if;
  return uid;
end $$;

create or replace function public._announcement(a public.announcements) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'kind', a.kind,
    'active', a.active, 'created_at', _iso(a.created_at))
$$;

-- Readable before signing in (sign-up screen).
create or replace function public.app_config() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('signup_enabled', s.signup_enabled, 'maintenance_message', s.maintenance_message,
    'announcement', (select _announcement(a) from public.announcements a where a.active
                     order by a.created_at desc limit 1))
  from public.app_settings s where id = 1
$$;

create or replace function public.announcements_list() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _me();
  return (select coalesce(jsonb_agg(_announcement(a) order by a.created_at desc), '[]'::jsonb)
    from (select * from public.announcements order by created_at desc limit 50) a);
end $$;

create or replace function public.admin_stats() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin();
  return jsonb_build_object(
    'users', (select count(*) from public.profiles where not is_deleted),
    'active_today', (select count(*) from public.profiles where last_seen_at > now() - interval '1 day'),
    'chats', (select count(*) from public.chats),
    'groups', (select count(*) from public.chats where is_group),
    'messages', (select count(*) from public.messages),
    'messages_today', (select count(*) from public.messages where created_at > now() - interval '1 day'));
end $$;

create or replace function public.admin_users(p_query text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _admin();
  q text := lower(trim(coalesce(p_query, '')));
begin
  return (select coalesce(jsonb_agg(_profile(p, uid) order by p.created_at desc), '[]'::jsonb)
    from (select * from public.profiles p where not p.is_deleted
            and (q = '' or lower(p.name) like '%' || q || '%' or lower(p.username) like '%' || q || '%'
                 or lower(p.email) like '%' || q || '%')
          order by created_at desc limit 200) p);
end $$;

create or replace function public.admin_update_user(p_id uuid, p_disabled boolean default null, p_admin boolean default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := _admin();
begin
  if p_id = uid and (p_disabled or p_admin = false) then
    raise exception 'You can''t turn off or demote your own account.' using errcode = '22023';
  end if;
  update public.profiles set is_disabled = coalesce(p_disabled, is_disabled), is_admin = coalesce(p_admin, is_admin)
  where id = p_id and not is_deleted;
  if not found then
    raise exception 'This person doesn''t exist.' using errcode = 'P0002';
  end if;
  return (select _profile(p, uid) from public.profiles p where id = p_id);
end $$;

create or replace function public.admin_settings() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin();
  return (select jsonb_build_object('signup_enabled', signup_enabled, 'user_limit', user_limit,
    'maintenance_message', maintenance_message) from public.app_settings where id = 1);
end $$;

create or replace function public.admin_update_settings(p_signup_enabled boolean default null, p_user_limit int default null,
  p_maintenance_message text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _admin();
  update public.app_settings set signup_enabled = coalesce(p_signup_enabled, signup_enabled),
    user_limit = greatest(1, coalesce(p_user_limit, user_limit)),
    maintenance_message = coalesce(left(p_maintenance_message, 500), maintenance_message)
  where id = 1;
  return admin_settings();
end $$;

create or replace function public.admin_announce(p_title text, p_body text default '', p_kind text default 'info')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _admin();
  a public.announcements;
begin
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'Give the announcement a title.' using errcode = '22023';
  end if;
  insert into public.announcements (title, body, kind, created_by)
  values (left(trim(p_title), 120), left(trim(coalesce(p_body, '')), 5000), coalesce(p_kind, 'info'), uid)
  returning * into a;
  return _announcement(a);
end $$;

create or replace function public.admin_set_announcement(p_id uuid, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.announcements;
begin
  perform _admin();
  update public.announcements set active = p_active where id = p_id returning * into a;
  if a.id is null then
    raise exception 'Not found.' using errcode = 'P0002';
  end if;
  return _announcement(a);
end $$;

-- ─── New accounts ────────────────────────────────────────────────────

-- Makes the profile when someone signs up, and refuses sign-up when it's
-- off or full. The first account is an admin.
create or replace function public._new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s public.app_settings;
  n int;
  base text;
  u text;
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  select * into s from public.app_settings where id = 1;
  select count(*) into n from public.profiles where not is_deleted;
  if n > 0 and not s.signup_enabled then
    raise exception 'Sign-up is closed on this server right now.';
  end if;
  if n > 0 and n >= s.user_limit then
    raise exception 'This server is full. Ask its admin to raise the limit.';
  end if;
  base := regexp_replace(lower(coalesce(meta->>'username', split_part(new.email, '@', 1))), '[^a-z0-9_.]', '', 'g');
  base := left(base, 18);
  if length(base) < 3 then
    base := base || 'user';
  end if;
  u := base;
  while exists (select 1 from public.profiles where lower(username) = u) loop
    u := base || '_' || substr(md5(random()::text), 1, 4);
  end loop;
  insert into public.profiles (id, email, name, username, avatar_url, is_admin)
  values (new.id, lower(coalesce(new.email, '')),
          left(coalesce(nullif(meta->>'name', ''), nullif(meta->>'full_name', ''), split_part(new.email, '@', 1)), 80),
          u, coalesce(meta->>'avatar_url', meta->>'picture'), n = 0)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists codenote_new_user on auth.users;
create trigger codenote_new_user after insert on auth.users
  for each row execute function public._new_user();

-- ─── Push: tell the Edge Function about new messages ─────────────────

create or replace function public._push_new_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare cfg record;
begin
  if new.kind = 'system' or new.sender_id is null then
    return new;
  end if;
  select * into cfg from private.push_config where id = 1;
  if cfg.url is null or to_regproc('net.http_post') is null then
    return new;
  end if;
  begin
    perform net.http_post(
      url := cfg.url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', cfg.secret),
      body := jsonb_build_object('message_id', new.id));
  exception when others then
    raise warning 'CodeNote push: %', sqlerrm;  -- never block a message because of push
  end;
  return new;
end $$;

drop trigger if exists codenote_push on public.messages;
create trigger codenote_push after insert on public.messages
  for each row execute function public._push_new_message();

-- ─── Who can read what (row-level security) ──────────────────────────

alter table public.profiles enable row level security;
alter table public.blocks enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.device_tokens enable row level security;
alter table public.synced_items enable row level security;
alter table public.announcements enable row level security;
alter table public.app_settings enable row level security;

-- Live updates read these tables directly, so each person only gets rows
-- about their own chats and notes. Nobody writes to them directly.
drop policy if exists "members read chats" on public.chats;
create policy "members read chats" on public.chats for select to authenticated using (_is_member(id));

drop policy if exists "members read members" on public.chat_members;
create policy "members read members" on public.chat_members for select to authenticated using (_is_member(chat_id));

drop policy if exists "members read messages" on public.messages;
create policy "members read messages" on public.messages for select to authenticated using (
  exists (select 1 from public.chat_members m
          where m.chat_id = messages.chat_id and m.user_id = auth.uid() and messages.seq > m.hidden_seq));

drop policy if exists "own notes" on public.synced_items;
create policy "own notes" on public.synced_items for select to authenticated using (owner_id = auth.uid());

drop policy if exists "everyone reads announcements" on public.announcements;
create policy "everyone reads announcements" on public.announcements for select to authenticated using (true);

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for select to authenticated using (id = auth.uid());

revoke all on public.profiles, public.blocks, public.chats, public.chat_members, public.messages,
  public.device_tokens, public.synced_items, public.announcements, public.app_settings from anon, authenticated;
grant select on public.chats, public.chat_members, public.messages, public.synced_items, public.announcements,
  public.profiles to authenticated;
revoke all on schema private from anon, authenticated;

-- Functions: helpers stay private, the rest are for signed-in people.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.my_chats(), public.chat_details(uuid), public.send_message(uuid, text, text, text, jsonb, uuid),
  public.get_messages(uuid, bigint, bigint, int), public.pinned_messages(uuid),
  public.edit_message(uuid, text), public.delete_message(uuid), public.pin_message(uuid, boolean),
  public.react(uuid, text), public.unreact(uuid),
  public.start_direct(uuid), public.create_group(text, text, text, uuid[], boolean),
  public.update_group(uuid, text, text, text, boolean), public.delete_chat(uuid),
  public.add_members(uuid, uuid[]), public.set_member_role(uuid, uuid, text), public.remove_member(uuid, uuid),
  public.set_muted(uuid, boolean), public.mark_read(uuid, bigint), public.mark_delivered(uuid, bigint),
  public.mark_all_delivered(),
  public.me(), public.update_profile(text, text, text, text), public.search_users(text), public.get_user(uuid),
  public.my_blocks(), public.block_user(uuid), public.unblock_user(uuid), public.delete_my_account(),
  public.register_device(text, text), public.unregister_device(text),
  public.sync_pull(bigint, int), public.sync_push(jsonb),
  public.announcements_list(), public.admin_stats(), public.admin_users(text),
  public.admin_update_user(uuid, boolean, boolean), public.admin_settings(),
  public.admin_update_settings(boolean, int, text), public.admin_announce(text, text, text),
  public.admin_set_announcement(uuid, boolean)
  to authenticated;
-- The policies above call these as the signed-in person.
grant execute on function public._is_member(uuid) to authenticated;
grant execute on function public.username_available(text), public.app_config() to anon, authenticated;

-- ─── Live updates ────────────────────────────────────────────────────

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
    begin alter publication supabase_realtime add table public.chat_members; exception when others then null; end;
    begin alter publication supabase_realtime add table public.chats; exception when others then null; end;
    begin alter publication supabase_realtime add table public.synced_items; exception when others then null; end;
    begin alter publication supabase_realtime add table public.announcements; exception when others then null; end;
  end if;
end $$;
-- Updates and deletes carry the whole row (needed for receipts and removals).
alter table public.chat_members replica identity full;
alter table public.messages replica identity full;

-- ─── Pictures (Storage) ──────────────────────────────────────────────

do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('media', 'media', true, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic'])
    on conflict (id) do nothing;
  end if;
end $$;

do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "codenote upload own folder" on storage.objects;
    create policy "codenote upload own folder" on storage.objects for insert to authenticated
      with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
    drop policy if exists "codenote read media" on storage.objects;
    create policy "codenote read media" on storage.objects for select using (bucket_id = 'media');
  end if;
end $$;
