# Set up Supabase for CodeNote Online

This is for the **CodeNote Online** build (the Supabase one). It takes about
15 minutes, all in the Supabase website. The free plan is enough to start.

## 1. Make the project

1. Go to [supabase.com](https://supabase.com), sign in, and click **New project**.
2. Pick a name (for example `codenote`), a database password (save it in your
   password manager) and the region closest to your users.
3. Wait a minute while it starts.

## 2. Make the tables and rules

1. In the left menu open **SQL Editor**, then **New query**.
2. Open `supabase/migrations/20261122000000_codenote_online.sql` from this
   repository, copy all of it, paste it in, and click **Run**.
3. It should say "Success. No rows returned". Running it again later (after an
   update) is safe.

This makes every table, the rules for who can see and change what, the live
updates, and a `media` storage bucket for pictures.

**The first account that signs up becomes the admin.**

## 3. Sign-in emails use a 6-digit code

The app asks for a code (it doesn't open links). Two email templates need
the code in them:

1. **Authentication → Emails → Templates → Confirm signup.** Put this in the
   message (keep the rest if you like):
   `Your CodeNote code is {{ .Token }}`
2. **Reset password** template: the same line, `Your CodeNote code is {{ .Token }}`.

If you don't want people to confirm their email at all, turn off
**Authentication → Sign In / Providers → Email → Confirm email**.

For real use, set up your own email sender in **Authentication → Emails →
SMTP Settings**. Supabase's built-in sender only sends a few emails an hour.

## 4. The keys for the app

Open **Project Settings → API** (or **Data API**). You need two values:

- **Project URL**, like `https://abcdxyz.supabase.co`
- **anon public** key, a long text starting with `eyJ`

Put them in GitHub as the secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`
(see [BUILD.md](BUILD.md)). The anon key is meant to be inside apps: the
rules from step 2 decide what it can do.

Never put the **service_role** key in the app or in GitHub.

## 5. Google sign-in (optional)

1. Make the OAuth client ids in Google Cloud ([BUILD.md](BUILD.md#google-sign-in)).
2. In Supabase: **Authentication → Sign In / Providers → Google**. Turn it on and
   paste the **Web** client id and its secret. Under **Authorized Client IDs**
   also add the Android client id.
3. Turn on **Skip nonce check** (needed for sign-in from the Android app).

## 6. Push notifications (optional)

Without this, messages still arrive live while the app is open or in the
background. Push makes them arrive when the app is closed.

1. Set up Firebase ([BUILD.md](BUILD.md#push-notifications-firebase)) and download
   the **service account** JSON file.
2. In Supabase open **Edge Functions → Deploy a new function → Via editor**.
   Name it `push`, paste all of `supabase/functions/push/index.ts`, and deploy.
3. Open the function's settings and turn **off** "Verify JWT" (the database
   calls it with its own secret instead).
4. **Edge Functions → Secrets**: add
   - `FCM_SERVICE_ACCOUNT`: the whole content of the service account JSON file
   - `PUSH_SECRET`: a long random text you make up (save it for the next step)
5. Tell the database where to send new messages. In **SQL Editor** run (with
   your project address and the same secret):

   ```sql
   insert into private.push_config (id, url, secret)
   values (1, 'https://YOUR-PROJECT.supabase.co/functions/v1/push', 'THE-SAME-PUSH-SECRET')
   on conflict (id) do update set url = excluded.url, secret = excluded.secret;
   ```

6. Check **Database → Extensions** shows `pg_net` turned on (the migration turns
   it on; if not, turn it on and run the migration again).

## Admin

- The first account is an admin. In the app: **Account → Admin dashboard**.
- To make someone else an admin, use the dashboard, or in SQL:
  `update profiles set is_admin = true where email = 'them@example.com';`
