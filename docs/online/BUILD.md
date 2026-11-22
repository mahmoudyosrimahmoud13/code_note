# Build CodeNote Online

GitHub Actions builds every install twice:

| Build | App name | App id | Backend |
|---|---|---|---|
| Supabase | CodeNote Online | `org.code.note.online` | Supabase ([SUPABASE.md](SUPABASE.md)) |
| FastAPI | CodeNote Server | `org.code.note.online.server` | Your server ([SERVER.md](SERVER.md)) |

They install next to each other and next to the local CodeNote.

## GitHub secrets

In the repository on GitHub: **Settings → Secrets and variables → Actions →
New repository secret**. Only the signing key ones are needed for releases;
the rest turn features on.

| Secret | For | Needed? |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Signing Android builds (the same key as CodeNote) | For releases |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | The Supabase build | Yes, for the Supabase build to sign in |
| `SERVER_URL` | FastAPI build: an address filled in on the first screen | No |
| `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` | Google sign-in | No |
| `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | Push | No |
| `FIREBASE_APP_ID` | Push, Supabase build's Android app id from Firebase | No |
| `FIREBASE_APP_ID_SERVER` | Push, FastAPI build's Android app id from Firebase | No |
| `FIREBASE_IOS_APP_ID` | Push on iPhone and Mac | No |

CodeNote Online is built from the main `code_note` repository, so the
signing key secrets it already has keep working. Never commit the keystore
or `key.properties`. The secrets live only in GitHub, never in the code, so
the repository can stay public.

## Push notifications (Firebase)

Firebase is used only to deliver pushes. Everything else is Supabase or your
server.

1. [console.firebase.google.com](https://console.firebase.google.com) → **Add project**.
2. **Add app → Android** twice: package `org.code.note.online`, then
   `org.code.note.online.server`. You don't need to download
   `google-services.json`; the app gets its settings from the secrets.
3. **Project settings → General**: copy the **Web API key** (`FIREBASE_API_KEY`),
   the **Project ID** (`FIREBASE_PROJECT_ID`), and each Android app's
   **App ID** (`FIREBASE_APP_ID` and `FIREBASE_APP_ID_SERVER`).
4. **Project settings → Cloud Messaging**: copy the **Sender ID** (`FIREBASE_SENDER_ID`).
5. **Project settings → Service accounts → Generate new private key**. This file
   is for the backend only (Supabase Edge Function secret, or the server's
   `FCM_SERVICE_ACCOUNT_FILE`). Never put it in the app or in Git.

## Google sign-in

1. [console.cloud.google.com](https://console.cloud.google.com) → **APIs & Services →
   Credentials → Create credentials → OAuth client ID**.
2. Make a **Web application** client. Its id is `GOOGLE_WEB_CLIENT_ID`.
3. Make an **Android** client for each build's package name, with the SHA-1 of
   your signing key. To see the SHA-1:

   ```bash
   keytool -list -v -keystore ~/codenote-release.jks -alias codenote | grep SHA1
   ```

   `keytool` reads your keystore (it asks for its password) and `grep SHA1`
   shows only the SHA-1 line.
4. Supabase build: add the ids in Supabase ([SUPABASE.md](SUPABASE.md#5-google-sign-in-optional)).
   FastAPI build: put the Web and Android ids in the server's `GOOGLE_CLIENT_IDS`.

Google sign-in shows on Android and iPhone. On computers people use email
and password.

## Building on your own computer

```bash
flutter build apk --release --dart-define=BACKEND=fastapi
```

`--dart-define=BACKEND=fastapi` picks the backend. For the Supabase build add
`--dart-define=BACKEND=supabase --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
