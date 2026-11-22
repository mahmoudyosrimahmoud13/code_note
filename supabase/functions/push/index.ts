// CodeNote Online: sends a push for each new chat message, through
// Firebase Cloud Messaging. The database calls this (see the
// codenote_push trigger in the migration).
//
// Secrets (Supabase dashboard > Edge Functions > push > Secrets):
//   FCM_SERVICE_ACCOUNT  the whole Firebase service account JSON
//   PUSH_SECRET          the same value you put in private.push_config
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are there automatically.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cached: { token: string; expires: number } | null = null;

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A Google access token for FCM, signed with the service account. */
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.expires > now + 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(signature)}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!r.ok) throw new Error(`Google sign-in failed: ${r.status} ${await r.text()}`);
  const data = await r.json();
  cached = { token: data.access_token, expires: now + (data.expires_in ?? 3600) };
  return cached.token;
}

function snippet(kind: string, body: string, payload: Record<string, unknown> | null): string {
  if (kind === "image") return body ? `📷 ${body}` : "📷 Photo";
  if (kind === "note") return `📝 Note: ${(payload?.title as string) || "Untitled"}`;
  if (kind === "block") return body ? `‹/› Code: ${body}`.slice(0, 120) : "‹/› Code block";
  return body.slice(0, 200);
}

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_SECRET")) {
    return new Response("not allowed", { status: 401 });
  }
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return new Response("push is off (no FCM_SERVICE_ACCOUNT)", { status: 200 });
  const sa = JSON.parse(raw) as ServiceAccount;

  const { message_id } = await req.json();
  const { data: m } = await supabase.from("messages").select("*").eq("id", message_id).single();
  if (!m || !m.sender_id || m.kind === "system") return new Response("skip");

  const [{ data: chat }, { data: sender }, { data: members }] = await Promise.all([
    supabase.from("chats").select("id, is_group, name").eq("id", m.chat_id).single(),
    supabase.from("profiles").select("name").eq("id", m.sender_id).single(),
    supabase.from("chat_members").select("user_id, muted").eq("chat_id", m.chat_id),
  ]);
  const targets = (members ?? []).filter((x) => x.user_id !== m.sender_id && !x.muted).map((x) => x.user_id);
  if (!chat || targets.length === 0) return new Response("nobody to tell");

  const { data: tokens } = await supabase.from("device_tokens").select("token").in("user_id", targets);
  if (!tokens?.length) return new Response("no devices");

  const title = chat.is_group ? `${chat.name} · ${sender?.name ?? ""}` : (sender?.name ?? "CodeNote");
  const body = snippet(m.kind, m.body ?? "", m.payload);
  const access = await accessToken(sa);
  const dead: string[] = [];

  await Promise.all(tokens.map(async ({ token }) => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: { type: "message", chat_id: m.chat_id, message_id: m.id },
          android: { priority: "high", notification: { channel_id: "chat", tag: m.chat_id, color: "#7B5CFF" } },
          apns: { payload: { aps: { "thread-id": m.chat_id, sound: "default" } } },
        },
      }),
    });
    if (r.status === 404 || (r.status === 400 && (await r.text()).toLowerCase().includes("registration token"))) {
      dead.push(token);
    }
  }));
  if (dead.length) await supabase.from("device_tokens").delete().in("token", dead);
  return new Response(`sent to ${tokens.length - dead.length}`);
});
