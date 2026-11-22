# Run the CodeNote server (FastAPI)

This is for the **CodeNote Server** build. The server keeps accounts,
chats, pictures and synced notes. People type its address in the app the
first time they open it.

There are two ways to run it. Docker is the easiest for a real server.

## Option A: Docker (recommended)

You need a computer or cloud server with Docker. On Ubuntu or Zorin:

```bash
sudo apt install -y docker.io docker-compose-v2 && sudo usermod -aG docker $USER
```

- `sudo apt install -y docker.io docker-compose-v2` installs Docker and its
  "compose" tool, which starts several programs together (here: the database
  and the server).
- `sudo usermod -aG docker $USER` lets your user run Docker without `sudo`.
  Log out and back in once after this.

Then, in the `server` folder of this repository:

```bash
cd server && cp .env.example .env && python3 -c "import secrets; print(secrets.token_urlsafe(48))"
```

- `cd server` goes into the server folder.
- `cp .env.example .env` makes your own settings file from the example.
- The `python3 -c ...` part prints a long random text. Copy it.

Open `.env` in a text editor and paste that text after `SECRET_KEY=`. Fill in
the rest if you want them (each line is explained in the file). Then start it:

```bash
docker compose up -d --build && docker compose logs -f server
```

- `docker compose up -d --build` builds the server and starts it together
  with its Postgres database. `-d` keeps them running in the background.
- `docker compose logs -f server` shows what the server is doing. Press
  Ctrl+C to stop watching (the server keeps running).

The server now answers on port 8000. Check it in a browser:
`http://YOUR-SERVER-IP:8000/health` should show `{"app":"codenote",...}`.

### Use a real address with HTTPS

Phones need HTTPS for a server on the internet. The simplest way is
[Caddy](https://caddyserver.com), which gets the certificate for you. With a
domain like `chat.example.com` pointing to your server, the whole Caddy
setting (`/etc/caddy/Caddyfile`) is:

```
chat.example.com {
    reverse_proxy localhost:8000
}
```

Then set `PUBLIC_URL=https://chat.example.com` in `.env` and restart with
`docker compose up -d`. In the app, people type `https://chat.example.com`.

On your own Wi-Fi only, HTTPS isn't needed: type
`http://192.168.x.x:8000` (your computer's address on the network).

## Option B: Python, for trying it on your computer

```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- `python3 -m venv .venv` makes a private Python folder for the server.
- `.venv/bin/pip install -r requirements.txt` installs what the server needs.
- `.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000` starts it, open
  to other devices on your network, on port 8000.

This uses a SQLite file (`codenote.db`) instead of Postgres. Fine for trying
and for a few people.

## Settings (`.env`)

| Setting | What it does |
|---|---|
| `SERVER_NAME` | The name the app shows after you type the address |
| `SECRET_KEY` | Signs sign-ins. Long and random. Changing it signs everyone out |
| `PUBLIC_URL` | The address people use, for picture links |
| `GOOGLE_CLIENT_IDS` | Google sign-in: the Web and Android client ids, comma separated |
| `FCM_SERVICE_ACCOUNT_FILE` | Push: the Firebase service account file (put it in the `data` volume, then `/data/firebase.json`) |
| `SMTP_*` | Sends the 6-digit email codes. Without it, codes are in the server log |
| `REQUIRE_EMAIL_VERIFICATION` | `true` makes new accounts confirm their email |
| `ADMIN_EMAILS` | More admins. The first account is always an admin |

## Backups

Everything is in two Docker volumes: `db` (the database) and `data`
(pictures). To back up the database:

```bash
docker compose exec db pg_dump -U codenote codenote > codenote-backup.sql
```

`docker compose exec db` runs a command inside the database container;
`pg_dump` writes the whole database to the file `codenote-backup.sql`.

## Updating

```bash
git pull && cd server && docker compose up -d --build
```

`git pull` gets the new code; `docker compose up -d --build` rebuilds and
restarts the server. The database tables update themselves.

## Tests

```bash
cd server && .venv/bin/pip install pytest && .venv/bin/pytest -q
```

Runs 11 tests that use the whole API: accounts, chats, groups, blocking,
sync, admin and live updates.
