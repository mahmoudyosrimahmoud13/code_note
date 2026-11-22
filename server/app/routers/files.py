import os
import secrets

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse

from ..config import get_settings
from ..models import User
from ..security import current_user

router = APIRouter(tags=["files"])

_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/heic": ".heic",
}
# What the first bytes of each picture type look like, so a renamed file
# can't pretend to be a picture.
_MAGIC = [b"\xff\xd8\xff", b"\x89PNG", b"RIFF", b"GIF8", b"\x00\x00\x00"]


def _dir() -> str:
    d = get_settings().upload_dir
    os.makedirs(d, exist_ok=True)
    return d


@router.post("/files")
async def upload(request: Request, file: UploadFile = File(...), user: User = Depends(current_user)):
    ext = _TYPES.get((file.content_type or "").lower())
    if ext is None:
        raise HTTPException(415, "Only pictures can be uploaded (JPEG, PNG, WebP, GIF, HEIC).")
    limit = get_settings().max_upload_mb * 1024 * 1024
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(413, f"That picture is too big ({get_settings().max_upload_mb} MB at most).")
    if not any(data.startswith(m) for m in _MAGIC):
        raise HTTPException(415, "That file isn't a picture.")
    name = f"{user.id[:8]}-{secrets.token_urlsafe(18)}{ext}"
    with open(os.path.join(_dir(), name), "wb") as f:
        f.write(data)
    base = get_settings().public_url.rstrip("/") or str(request.base_url).rstrip("/")
    return {"url": f"{base}/files/{name}"}


@router.get("/files/{name}")
async def download(name: str):
    if "/" in name or "\\" in name or name.startswith("."):
        raise HTTPException(404, "Not found.")
    path = os.path.join(_dir(), name)
    if not os.path.isfile(path):
        raise HTTPException(404, "Not found.")
    return FileResponse(path, headers={"Cache-Control": "public, max-age=31536000, immutable"})
