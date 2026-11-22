"""Push notifications through Firebase Cloud Messaging (HTTP v1).

Only used when FCM_SERVICE_ACCOUNT_FILE is set. Everything else in the
server works without it.
"""

import asyncio
import json
import logging

from .config import get_settings

log = logging.getLogger("codenote.push")

_credentials = None
_project_id: str | None = None


def enabled() -> bool:
    return bool(get_settings().fcm_service_account_file)


def _token() -> tuple[str, str] | None:
    global _credentials, _project_id
    path = get_settings().fcm_service_account_file
    if not path:
        return None
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    if _credentials is None:
        with open(path) as f:
            info = json.load(f)
        _project_id = info["project_id"]
        _credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
        )
    if not _credentials.valid:
        _credentials.refresh(Request())
    return _credentials.token, _project_id  # type: ignore[return-value]


def _send_one(access: str, project: str, token: str, title: str, body: str, data: dict) -> bool:
    """Sends to one device. False if the device token is gone."""
    import requests

    r = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
        headers={"Authorization": f"Bearer {access}"},
        json={
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {k: str(v) for k, v in data.items()},
                "android": {
                    "priority": "high",
                    "notification": {
                        "channel_id": "chat",
                        "tag": data.get("chat_id", ""),
                        "color": "#7B5CFF",
                    },
                },
                "apns": {"payload": {"aps": {"thread-id": data.get("chat_id", ""), "sound": "default"}}},
            }
        },
        timeout=10,
    )
    # 404 UNREGISTERED: the app was removed or the token expired.
    if r.status_code == 404 or (r.status_code == 400 and "registration token" in r.text.lower()):
        return False
    if r.status_code >= 300:
        log.warning("FCM refused a push: %s %s", r.status_code, r.text[:300])
    return True


async def send(tokens: list[str], title: str, body: str, data: dict) -> list[str]:
    """Sends a push to [tokens]. Returns the tokens that no longer work."""
    if not tokens or not enabled():
        return []

    def work() -> list[str]:
        try:
            auth = _token()
        except Exception as e:  # bad file, no network
            log.warning("Push is set up but can't sign in to FCM: %s", e)
            return []
        if auth is None:
            return []
        access, project = auth
        dead = []
        for t in tokens:
            try:
                if not _send_one(access, project, t, title, body, data):
                    dead.append(t)
            except Exception as e:
                log.warning("Push failed: %s", e)
        return dead

    return await asyncio.to_thread(work)
