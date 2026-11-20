import '../../helpers/helper_methods.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';

/// Sample notes that run code: a YouTube downloader (Python backend + web
/// page), a FastAPI todo app (backend + frontend), a Snake mini app that
/// saves its best score, and small Python and Bash scripts. Each folder
/// shares one sandbox and starts with ▶ Run folder.
class RunnerDemos {
  RunnerDemos._();

  static ({List<NoteEntity> notes, List<NoteGroupEntity> groups}) build() {
    final now = DateTime.now();
    String id() => uuid.generate();
    NoteEntity note(String title, List<BlockEntity> blocks, List<String> tags, int minutesAgo) => NoteEntity(
          id: id(),
          title: title,
          tags: tags,
          blocks: blocks,
          lastModified: now.subtract(Duration(minutes: minutesAgo)),
        );
    CodeBlockEntity code(Language l, String text, {RunRole role = RunRole.normal}) =>
        CodeBlockEntity(id: id(), text: text, language: l, runRole: role);
    MarkdownBlockEntity md(String text) => MarkdownBlockEntity(id: id(), text: text);

    // ── youtube-downloader/ ──────────────────────────────────
    final ytBackend = note('Downloader backend (yt-dlp)', [
      md('''### How to use
1. First time only: **Settings → Runtimes and sandbox** → set up Python.
2. Open the **youtube-downloader** folder and press **▶ Run folder**.
   This installs yt-dlp, starts this backend and opens the **Downloader** page.
3. Downloads stay in this folder's sandbox. Press the **folder** button under the output to **Save a copy**.

YouTube changes often. Keep yt-dlp fresh in **Settings → Runtimes and sandbox → Check for updates**.
Only download videos you have the right to save.'''),
      code(Language.bash, '''# Installs yt-dlp and a bundled ffmpeg into CodeNote's Python (once).
python -m pip install --quiet yt-dlp imageio-ffmpeg
python -m pip show yt-dlp | head -2'''),
      code(Language.python, _yt_backend),
    ], const ['youtube', 'python', 'demo'], 1);

    final ytPage = note('Downloader', [
      md('The page for the backend note in this folder. Run the folder with **▶**, '
          'or start the backend note first and then press ▶ here.'),
      code(Language.html, _yt_html),
      code(Language.css, _yt_css),
      code(Language.javaScript, _yt_js),
    ], const ['youtube', 'mini-app', 'demo'], 1);

    // ── fastapi-todo/ ────────────────────────────────────────
    final apiNote = note('FastAPI: todo API', [
      md('A backend in one note, the frontend in another. Both live in this folder, so they share a sandbox: '
          'the API saves **todos.json** there, and the page calls it with `codenote.api(8000, \'/todos\')`.'),
      code(Language.bash, 'python -m pip install --quiet fastapi uvicorn'),
      code(Language.python, _api_py),
    ], const ['fastapi', 'python', 'demo'], 2);

    final todoPage = note('Todo app', [
      code(Language.html, _todo_html),
      code(Language.css, _todo_css),
      code(Language.javaScript, _todo_js),
    ], const ['fastapi', 'mini-app', 'demo'], 2);

    // ── mini apps and scripts ────────────────────────────────
    final snake = note('Mini app: Snake', [
      md('Press **▶** to play. The best score is saved with `localStorage`, which CodeNote keeps for this note '
          '(and in backups). Reset it from the **⋯** menu.'),
      code(Language.html, _snake_html),
      code(Language.css, _snake_css),
      code(Language.javaScript, _snake_js),
    ], const ['game', 'mini-app', 'demo'], 3);

    final pyFile = note('Python: save a file in the sandbox', [
      md('Press **▶** on the code. It writes `commits.csv` and asks your name (type it in the box under the output).'),
      code(Language.python, _py_file),
    ], const ['python', 'demo'], 4);

    final bashInfo = note('Bash: look around the sandbox', [
      code(Language.bash, _bash_info),
    ], const ['bash', 'demo'], 4);

    final groups = [
      NoteGroupEntity(id: id(), name: 'youtube-downloader', noteIds: [ytBackend.id, ytPage.id], lastModified: now),
      NoteGroupEntity(id: id(), name: 'fastapi-todo', noteIds: [apiNote.id, todoPage.id], lastModified: now),
      NoteGroupEntity(id: id(), name: 'run-code', noteIds: [snake.id, pyFile.id, bashInfo.id], lastModified: now),
    ];
    return (notes: [ytBackend, ytPage, apiNote, todoPage, snake, pyFile, bashInfo], groups: groups);
  }
}

const _yt_backend = r'''
# YouTube downloader backend: a small web server around yt-dlp.
# It runs in this folder's sandbox. Downloads go to ./downloads and stay
# there until you press "Save a copy" in the Files button.
# The "Downloader" note in this folder is the page that talks to it.
import json, os, threading, time, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

import yt_dlp
from yt_dlp.utils import DownloadCancelled, parse_bytes

PORT = 8765
DOWNLOADS = os.path.abspath("downloads")
os.makedirs(DOWNLOADS, exist_ok=True)

try:  # ffmpeg is needed to merge video+audio, convert audio and embed extras
    import imageio_ffmpeg
    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except Exception:
    FFMPEG = None

jobs = {}
lock = threading.Lock()


def build_options(o, job):
    mode = o.get("mode", "video")
    quality = str(o.get("quality", "best"))
    playlist = bool(o.get("playlist"))
    # Video and audio go to their own folders, so getting the audio of a
    # video you already have never overwrites (or deletes) the video.
    kind = "audio" if mode == "audio" else "video"
    template = (o.get("template") or "").strip() or (
        "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s" if playlist
        else "%(title)s [%(id)s].%(ext)s")
    template = f"{kind}/{template}"
    opts = {
        "outtmpl": os.path.join(DOWNLOADS, template),
        "noplaylist": not playlist,
        "restrictfilenames": bool(o.get("safe_names")),
        "progress_hooks": [lambda d: progress(job, d)],
        "postprocessor_hooks": [lambda d: post(job, d)],
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "postprocessors": [],
    }
    if FFMPEG:
        opts["ffmpeg_location"] = FFMPEG
    if playlist and (o.get("items") or "").strip():
        opts["playlist_items"] = o["items"].strip()
    if (o.get("rate") or "").strip():
        rate = parse_bytes(o["rate"].strip())
        if rate:
            opts["ratelimit"] = rate

    pps = opts["postprocessors"]
    sponsor = o.get("sponsorblock")
    if sponsor:
        cats = ["sponsor", "selfpromo", "interaction"]
        pps.append({"key": "SponsorBlock", "categories": cats, "when": "after_filter"})
        pps.append({"key": "ModifyChapters", "remove_sponsor_segments": cats})

    if mode == "audio":
        opts["format"] = "ba/b"
        codec = o.get("audio_format", "m4a")
        pps.append({"key": "FFmpegExtractAudio", "preferredcodec": codec,
                    "preferredquality": str(o.get("audio_quality", "192"))})
    else:
        container = o.get("container", "mp4")
        sort = [] if quality == "best" else [f"res:{quality}"]
        if container == "mp4":
            sort.append("ext:mp4:m4a")
        elif container == "webm":
            sort.append("ext:webm:webm")
        opts["format"] = "bv*+ba/b" if FFMPEG else "b"
        opts["format_sort"] = sort
        opts["merge_output_format"] = container

    if o.get("subtitles"):
        opts["writesubtitles"] = True
        opts["writeautomaticsub"] = bool(o.get("auto_subs"))
        opts["subtitleslangs"] = [s.strip() for s in (o.get("sub_langs") or "en").split(",") if s.strip()]
        opts["subtitlesformat"] = "srt/vtt/best"
        if o.get("embed_subs") and mode == "video" and FFMPEG:
            pps.append({"key": "FFmpegEmbedSubtitle"})
    if o.get("metadata") and FFMPEG:
        pps.append({"key": "FFmpegMetadata", "add_chapters": True, "add_metadata": True})
    if o.get("thumbnail"):
        opts["writethumbnail"] = True
        if FFMPEG and (mode == "video" or o.get("audio_format") in ("m4a", "mp3", "flac", "opus")):
            pps.append({"key": "EmbedThumbnail"})
    return opts


def progress(job, d):
    if job["cancel"]:
        raise DownloadCancelled("Cancelled")
    with lock:
        if d["status"] == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            job.update(status="downloading",
                       percent=round(d.get("downloaded_bytes", 0) * 100 / total, 1) if total else None,
                       speed=d.get("speed"), eta=d.get("eta"),
                       file=os.path.basename(d.get("filename") or ""))
            info = d.get("info_dict") or {}
            if info.get("playlist_index"):
                job["item"] = f'{info.get("playlist_index")} of {info.get("n_entries") or "?"}'
        elif d["status"] == "finished":
            job.update(status="processing", percent=100)


def post(job, d):
    if d["status"] == "started":
        with lock:
            job.update(status="processing", step=d.get("postprocessor"))


def run_job(job, o):
    try:
        with yt_dlp.YoutubeDL(build_options(o, job)) as ydl:
            info = ydl.extract_info(o["url"], download=True)
            with lock:
                job["title"] = (info or {}).get("title") or job["title"]
        with lock:
            job.update(status="done", percent=100, step=None)
    except DownloadCancelled:
        with lock:
            job.update(status="cancelled")
    except Exception as e:
        with lock:
            job.update(status="error", error=str(e).replace("\x1b[0;31m", "").replace("\x1b[0m", ""))


def get_info(url, playlist):
    opts = {"quiet": True, "no_warnings": True, "skip_download": True,
            "noplaylist": not playlist, "extract_flat": "in_playlist"}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    entries = info.get("entries")
    if entries is not None:
        entries = list(entries)
        return {"playlist": True, "title": info.get("title"), "uploader": info.get("uploader"),
                "count": len(entries),
                "items": [{"title": e.get("title"), "duration": e.get("duration")} for e in entries[:50]]}
    heights = sorted({f.get("height") for f in info.get("formats") or [] if f.get("height")}, reverse=True)
    subs = sorted(set((info.get("subtitles") or {}).keys()))
    return {"playlist": False, "title": info.get("title"), "uploader": info.get("uploader"),
            "duration": info.get("duration"), "thumbnail": info.get("thumbnail"),
            "views": info.get("view_count"), "heights": heights, "subtitles": subs[:40],
            "auto_subtitles": len(info.get("automatic_captions") or {})}


def list_files():
    out = []
    for root, _, names in os.walk(DOWNLOADS):
        for n in names:
            if n.endswith((".part", ".ytdl")):
                continue
            full = os.path.join(root, n)
            out.append({"path": os.path.relpath(full, os.getcwd()).replace(os.sep, "/"),
                        "name": os.path.relpath(full, DOWNLOADS).replace(os.sep, "/"),
                        "size": os.path.getsize(full), "time": os.path.getmtime(full)})
    return sorted(out, key=lambda f: -f["time"])


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"ok": True, "yt_dlp": yt_dlp.version.__version__, "ffmpeg": bool(FFMPEG)})
        if self.path == "/jobs":
            with lock:
                return self._send(200, sorted(jobs.values(), key=lambda j: -j["created"]))
        if self.path == "/files":
            return self._send(200, list_files())
        self._send(404, {"error": "not found"})

    def do_POST(self):
        try:
            o = self._body()
            if self.path == "/info":
                return self._send(200, get_info(o["url"], bool(o.get("playlist"))))
            if self.path == "/download":
                if not (o.get("url") or "").strip():
                    return self._send(400, {"error": "Paste a link first."})
                job = {"id": uuid.uuid4().hex[:8], "url": o["url"], "title": o["url"], "status": "queued",
                       "percent": 0, "created": time.time(), "cancel": False, "mode": o.get("mode", "video")}
                with lock:
                    jobs[job["id"]] = job
                threading.Thread(target=run_job, args=(job, o), daemon=True).start()
                return self._send(200, {"id": job["id"]})
            if self.path == "/cancel":
                with lock:
                    if o.get("id") in jobs:
                        jobs[o["id"]]["cancel"] = True
                return self._send(200, {"ok": True})
            if self.path == "/clear":
                with lock:
                    for k in [k for k, j in jobs.items() if j["status"] in ("done", "error", "cancelled")]:
                        del jobs[k]
                return self._send(200, {"ok": True})
            self._send(404, {"error": "not found"})
        except Exception as e:
            self._send(500, {"error": str(e)})

    def log_message(self, *args):
        pass


print(f"yt-dlp {yt_dlp.version.__version__} · ffmpeg: {'yes' if FFMPEG else 'no (install imageio-ffmpeg)'}")
print(f"Downloader backend running on port {PORT}. Open the Downloader note, or press Stop to end.")
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()''';

const _yt_html = r'''
<div class="app">
  <header>
    <h1>▶ YouTube downloader</h1>
    <span id="status" class="pill">checking backend…</span>
  </header>

  <div class="row">
    <input id="url" placeholder="Paste a YouTube link (video or playlist)" autocomplete="off">
    <button id="info" class="ghost">Info</button>
    <button id="go">Download</button>
  </div>
  <div id="preview" class="card hidden"></div>

  <div class="tabs">
    <button data-mode="video" class="on">🎬 Video</button>
    <button data-mode="audio">🎵 Audio only</button>
  </div>

  <div class="grid">
    <label class="video">Quality
      <select id="quality">
        <option value="best">Best available</option><option value="2160">4K (2160p)</option>
        <option value="1440">1440p</option><option value="1080">1080p</option>
        <option value="720">720p</option><option value="480">480p</option><option value="360">360p</option>
      </select></label>
    <label class="video">Format
      <select id="container"><option>mp4</option><option>webm</option><option>mkv</option></select></label>
    <label class="audio">Audio format
      <select id="audio_format"><option>m4a</option><option>mp3</option><option>opus</option><option>flac</option><option>wav</option></select></label>
    <label class="audio">Audio quality
      <select id="audio_quality"><option value="320">320 kbps</option><option value="192" selected>192 kbps</option><option value="128">128 kbps</option><option value="0">Best (VBR)</option></select></label>
    <label>Speed limit <input id="rate" placeholder="e.g. 2M (empty = no limit)"></label>
    <label>File name <input id="template" placeholder="%(title)s [%(id)s].%(ext)s (inside video/ or audio/)"></label>
  </div>

  <div class="checks">
    <label><input type="checkbox" id="subtitles"> Subtitles</label>
    <label class="sub"><input id="sub_langs" value="en" class="small"> languages</label>
    <label class="sub"><input type="checkbox" id="auto_subs"> include auto-generated</label>
    <label class="sub video"><input type="checkbox" id="embed_subs" checked> embed in video</label>
    <label><input type="checkbox" id="thumbnail" checked> Thumbnail</label>
    <label><input type="checkbox" id="metadata" checked> Metadata and chapters</label>
    <label><input type="checkbox" id="sponsorblock"> Skip sponsors (SponsorBlock)</label>
    <label><input type="checkbox" id="playlist"> Whole playlist</label>
    <label class="pl"><input id="items" placeholder="items, e.g. 1-5,8" class="small"></label>
    <label><input type="checkbox" id="safe_names"> Simple file names</label>
  </div>

  <h2>Downloads <button id="clear" class="link">clear finished</button></h2>
  <div id="jobs"><p class="muted">Nothing yet.</p></div>

  <h2>Files <span class="muted small">in this folder's sandbox · use the Files button in CodeNote to save a copy</span></h2>
  <div id="files"><p class="muted">No files yet.</p></div>
</div>''';

const _yt_css = r'''
:root { color-scheme: dark; --bg:#0F0E1A; --card:#17162A; --line:#2A2846; --text:#ECEAF6; --muted:#9C98B8; --violet:#7B5CFF; --mint:#3DDC97; --red:#FF6B7A; --amber:#FFB547; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 system-ui, -apple-system, 'Segoe UI', sans-serif; }
.app { max-width: 820px; margin: 0 auto; padding: 22px 18px 60px; }
header { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
h1 { font-size: 22px; margin: 0; }
h2 { font-size: 15px; margin: 26px 0 10px; color: var(--muted); font-family: ui-monospace, monospace; font-weight: 600; }
h2::before { content: '// '; color: var(--violet); }
.pill { font: 12px ui-monospace, monospace; padding: 4px 10px; border-radius: 99px; border: 1px solid var(--line); color: var(--muted); }
.pill.ok { color: var(--mint); border-color: #2c6b52; } .pill.bad { color: var(--red); border-color: #6b2c36; }
.row { display: flex; gap: 8px; margin-top: 18px; }
input, select { background: var(--card); color: var(--text); border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; font: inherit; width: 100%; outline: none; }
input:focus, select:focus { border-color: var(--violet); }
button { background: var(--violet); color: #fff; border: 0; border-radius: 10px; padding: 10px 16px; font: 600 14px system-ui, sans-serif; cursor: pointer; white-space: nowrap; }
button.ghost { background: var(--card); border: 1px solid var(--line); color: var(--text); }
button.link { background: none; color: var(--violet); padding: 0 6px; font-size: 12px; }
button:disabled { opacity: .5; cursor: default; }
.tabs { display: flex; gap: 6px; margin: 18px 0 12px; }
.tabs button { background: var(--card); border: 1px solid var(--line); color: var(--muted); }
.tabs button.on { background: color-mix(in srgb, var(--violet) 25%, var(--card)); color: var(--text); border-color: var(--violet); }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; }
.grid label { display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: var(--muted); }
.checks { display: flex; flex-wrap: wrap; gap: 8px 16px; margin-top: 14px; font-size: 14px; }
.checks label { display: flex; align-items: center; gap: 6px; }
.checks input[type=checkbox] { width: auto; accent-color: var(--violet); }
input.small { width: 130px; padding: 5px 8px; }
.hidden { display: none !important; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px; margin-top: 12px; }
.preview { display: flex; gap: 12px; } .preview img { width: 160px; border-radius: 8px; object-fit: cover; }
.muted { color: var(--muted); } .small { font-size: 12px; font-weight: 400; }
.job { display: grid; grid-template-columns: 1fr auto; gap: 4px 10px; align-items: center; }
.job .title { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.job .meta { font: 12px ui-monospace, monospace; color: var(--muted); grid-column: 1 / -1; }
.bar { grid-column: 1 / -1; height: 6px; border-radius: 3px; background: var(--line); overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--violet); transition: width .4s; }
.done .bar i { background: var(--mint); } .error .bar i, .cancelled .bar i { background: var(--red); }
.err { color: var(--red); font-size: 13px; grid-column: 1 / -1; }
.file { display: flex; justify-content: space-between; gap: 10px; padding: 8px 0; border-bottom: 1px solid var(--line); font-size: 14px; }
.file a { color: var(--text); text-decoration: none; overflow: hidden; text-overflow: ellipsis; }
.file a:hover { color: var(--violet); }
video, audio { width: 100%; margin-top: 8px; border-radius: 10px; }''';

const _yt_js = r'''
// Talks to the backend note in this folder through CodeNote
// (codenote.api avoids browser CORS problems). Your last options are
// remembered with codenote.storage.
const PORT = 8765;
const api = (path) => window.codenote ? codenote.api(PORT, path) : 'http://127.0.0.1:' + PORT + path;
const store = window.codenote ? codenote.storage : { get: (k, d) => d, set: () => {} };
const $ = (id) => document.getElementById(id);
const FIELDS = ['quality', 'container', 'audio_format', 'audio_quality', 'rate', 'template',
  'subtitles', 'sub_langs', 'auto_subs', 'embed_subs', 'thumbnail', 'metadata', 'sponsorblock',
  'playlist', 'items', 'safe_names'];
let mode = store.get('mode', 'video');

async function call(path, body) {
  const res = await fetch(api(path), body === undefined ? {} : {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await res.json().catch(() => ({ error: 'The backend answered strangely.' }));
  if (!res.ok || data.error) throw new Error(data.error || ('HTTP ' + res.status));
  return data;
}

function options() {
  const o = { url: $('url').value.trim(), mode };
  for (const f of FIELDS) { const el = $(f); o[f] = el.type === 'checkbox' ? el.checked : el.value; }
  return o;
}

function remember() {
  const o = options(); delete o.url;
  store.set('options', o); store.set('mode', mode);
}

function restore() {
  const o = store.get('options', null);
  if (o) for (const f of FIELDS) { const el = $(f); if (el && f in o) el.type === 'checkbox' ? el.checked = o[f] : el.value = o[f]; }
  setMode(mode);
}

function setMode(m) {
  mode = m;
  document.querySelectorAll('.tabs button').forEach(b => b.classList.toggle('on', b.dataset.mode === m));
  document.querySelectorAll('.video').forEach(e => e.classList.toggle('hidden', m !== 'video'));
  document.querySelectorAll('.audio').forEach(e => e.classList.toggle('hidden', m !== 'audio'));
  syncChecks();
}

function syncChecks() {
  document.querySelectorAll('.sub').forEach(e => e.classList.toggle('hidden', !$('subtitles').checked || (e.classList.contains('video') && mode !== 'video')));
  document.querySelectorAll('.pl').forEach(e => e.classList.toggle('hidden', !$('playlist').checked));
}

const time = (s) => s == null ? '' : (s >= 3600 ? Math.floor(s / 3600) + ':' : '') + String(Math.floor(s % 3600 / 60)).padStart(s >= 3600 ? 2 : 1, '0') + ':' + String(Math.floor(s % 60)).padStart(2, '0');
const size = (b) => b == null ? '' : b > 1073741824 ? (b / 1073741824).toFixed(2) + ' GB' : b > 1048576 ? (b / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(b / 1024)) + ' KB';
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

async function info() {
  const url = $('url').value.trim();
  if (!url) return;
  const box = $('preview');
  box.classList.remove('hidden');
  box.innerHTML = '<span class="muted">Looking it up…</span>';
  try {
    const i = await call('/info', { url, playlist: $('playlist').checked });
    if (i.playlist) {
      box.innerHTML = `<b>${esc(i.title)}</b> <span class="muted">· playlist · ${i.count} videos</span>` +
        `<ol class="small muted">${i.items.slice(0, 10).map(e => `<li>${esc(e.title)} ${time(e.duration)}</li>`).join('')}</ol>`;
    } else {
      box.innerHTML = `<div class="preview">${i.thumbnail ? `<img src="${esc(i.thumbnail)}" alt="">` : ''}<div>` +
        `<b>${esc(i.title)}</b><div class="muted small">${esc(i.uploader || '')} · ${time(i.duration)}${i.views ? ' · ' + i.views.toLocaleString() + ' views' : ''}</div>` +
        `<div class="small">Qualities: ${i.heights.length ? i.heights.map(h => h + 'p').join(', ') : 'single file'}</div>` +
        `<div class="small muted">Subtitles: ${i.subtitles.length ? esc(i.subtitles.join(', ')) : 'none'}${i.auto_subtitles ? ' · auto-generated in ' + i.auto_subtitles + ' languages' : ''}</div></div></div>`;
    }
  } catch (e) { box.innerHTML = `<span class="err">${esc(e.message)}</span>`; }
}

async function download() {
  remember();
  try { await call('/download', options()); $('url').value = ''; $('preview').classList.add('hidden'); refresh(); }
  catch (e) { alertBox(e.message); }
}

function alertBox(msg) {
  const box = $('preview'); box.classList.remove('hidden'); box.innerHTML = `<span class="err">${esc(msg)}</span>`;
}

function renderJobs(jobs) {
  if (!jobs.length) { $('jobs').innerHTML = '<p class="muted">Nothing yet.</p>'; return; }
  $('jobs').innerHTML = jobs.map(j => {
    const pct = j.percent == null ? 5 : j.percent;
    const what = { queued: 'waiting', downloading: 'downloading', processing: 'finishing' + (j.step ? ' (' + j.step.replace('FFmpeg', '') + ')' : ''), done: '✓ done', error: '✗ failed', cancelled: 'cancelled' }[j.status] || j.status;
    const meta = [what, j.item ? 'item ' + j.item : '', j.status === 'downloading' && j.percent != null ? j.percent + '%' : '', j.speed ? size(j.speed) + '/s' : '', j.eta ? 'eta ' + time(j.eta) : ''].filter(Boolean).join(' · ');
    const live = j.status === 'queued' || j.status === 'downloading' || j.status === 'processing';
    return `<div class="card job ${j.status}"><div class="title">${j.mode === 'audio' ? '🎵' : '🎬'} ${esc(j.title)}</div>` +
      (live ? `<button class="link" data-cancel="${j.id}">cancel</button>` : '<span></span>') +
      `<div class="bar"><i style="width:${pct}%"></i></div><div class="meta">${esc(meta)}</div>` +
      (j.error ? `<div class="err">${esc(j.error)}</div>` : '') + '</div>';
  }).join('');
}

function renderFiles(files) {
  if (!files.length) { $('files').innerHTML = '<p class="muted">No files yet.</p>'; return; }
  $('files').innerHTML = files.map((f, i) => {
    const link = window.codenote && codenote.file(f.path);
    const play = /\.(mp4|webm|m4a|mp3|opus|wav|flac)$/i.test(f.name) && link;
    return `<div class="file"><a href="${link || '#'}" data-play="${play ? i : ''}">${esc(f.name)}</a><span class="muted small">${size(f.size)}</span></div>` +
      `<div id="player-${i}"></div>`;
  }).join('');
  document.querySelectorAll('[data-play]').forEach(a => a.onclick = (ev) => {
    if (a.dataset.play === '') return;
    ev.preventDefault();
    const box = $('player-' + a.dataset.play);
    if (box.innerHTML) { box.innerHTML = ''; return; }
    const audio = /\.(m4a|mp3|opus|wav|flac)$/i.test(a.textContent);
    box.innerHTML = audio ? `<audio controls autoplay src="${a.href}"></audio>` : `<video controls autoplay src="${a.href}"></video>`;
  });
}

let lastFiles = '';
async function refresh() {
  try {
    const h = await call('/health');
    $('status').textContent = 'yt-dlp ' + h.yt_dlp + (h.ffmpeg ? ' · ffmpeg ✓' : ' · no ffmpeg');
    $('status').className = 'pill ok';
    renderJobs(await call('/jobs'));
    const files = await call('/files');
    const key = JSON.stringify(files.map(f => [f.path, f.size]));
    if (key !== lastFiles) { lastFiles = key; renderFiles(files); }
  } catch (e) {
    $('status').textContent = 'backend not running: press ▶ Run folder';
    $('status').className = 'pill bad';
  }
}

$('go').onclick = download;
$('info').onclick = info;
$('url').addEventListener('keydown', e => { if (e.key === 'Enter') download(); });
$('clear').onclick = async () => { await call('/clear', {}).catch(() => {}); refresh(); };
$('jobs').addEventListener('click', async e => { const id = e.target.dataset.cancel; if (id) { await call('/cancel', { id }).catch(() => {}); refresh(); } });
document.querySelectorAll('.tabs button').forEach(b => b.onclick = () => { setMode(b.dataset.mode); remember(); });
['subtitles', 'playlist'].forEach(id => $(id).addEventListener('change', syncChecks));
document.querySelectorAll('select, input').forEach(el => el.addEventListener('change', remember));
restore();
refresh();
setInterval(refresh, 1000);''';

const _snake_html = r'''
<div class="game">
  <div class="top">
    <span>score <b id="score">0</b></span>
    <span>best <b id="best">0</b></span>
    <span>games <b id="games">0</b></span>
  </div>
  <canvas id="board" width="400" height="400"></canvas>
  <p id="msg">Press Space or tap to start. Arrows, WASD or swipe to move.</p>
  <div class="pad">
    <button data-d="up">▲</button>
    <div><button data-d="left">◀</button><button data-d="down">▼</button><button data-d="right">▶</button></div>
  </div>
  <p class="small">Your best score is saved by CodeNote and kept in backups.
    Reset it from the note's ⋯ menu.</p>
</div>''';

const _snake_css = r'''
:root { color-scheme: dark; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0F0E1A; color: #ECEAF6; font: 15px/1.4 ui-monospace, 'JetBrains Mono', monospace; }
.game { text-align: center; padding: 16px; width: min(420px, 100vw); }
.top { display: flex; justify-content: space-between; margin-bottom: 10px; color: #9C98B8; }
.top b { color: #3DDC97; font-size: 18px; }
canvas { width: 100%; aspect-ratio: 1; background: #17162A; border: 1px solid #2A2846; border-radius: 14px; touch-action: none; }
#msg { color: #A993FF; min-height: 22px; }
.pad { display: grid; justify-items: center; gap: 6px; margin-top: 4px; }
.pad button { width: 56px; height: 44px; margin: 0 3px; border: 1px solid #2A2846; border-radius: 12px; background: #1F1D38; color: #ECEAF6; font-size: 18px; }
.small { color: #6F6A90; font-size: 12px; }
@media (pointer: fine) { .pad { display: none; } }''';

const _snake_js = r'''
// Snake, as a CodeNote mini app. localStorage here is saved by CodeNote,
// so the best score survives restarts and travels in backups.
const N = 20, S = 20;
const ctx = document.getElementById('board').getContext('2d');
const el = (id) => document.getElementById(id);
let best = Number(localStorage.getItem('best') || 0);
let games = Number(localStorage.getItem('games') || 0);
let snake, dir, next, food, score, timer = null, speed;
el('best').textContent = best;
el('games').textContent = games;

function reset() {
  snake = [{ x: 9, y: 10 }, { x: 8, y: 10 }, { x: 7, y: 10 }];
  dir = next = { x: 1, y: 0 };
  score = 0; speed = 130;
  el('score').textContent = 0;
  placeFood();
}

function placeFood() {
  do { food = { x: Math.floor(Math.random() * N), y: Math.floor(Math.random() * N) }; }
  while (snake.some(p => p.x === food.x && p.y === food.y));
}

function start() {
  if (timer) return;
  reset();
  el('msg').textContent = '';
  timer = setInterval(step, speed);
}

function over() {
  clearInterval(timer); timer = null;
  games++;
  localStorage.setItem('games', games);
  el('games').textContent = games;
  if (score > best) {
    best = score;
    localStorage.setItem('best', best);
    el('best').textContent = best;
    el('msg').textContent = 'New best: ' + best + '! Space or tap to play again.';
  } else {
    el('msg').textContent = 'Game over. Space or tap to play again.';
  }
}

function step() {
  dir = next;
  const head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };
  if (head.x < 0 || head.y < 0 || head.x >= N || head.y >= N || snake.some(p => p.x === head.x && p.y === head.y)) return over();
  snake.unshift(head);
  if (head.x === food.x && head.y === food.y) {
    score++;
    el('score').textContent = score;
    placeFood();
    if (score % 5 === 0 && speed > 60) { speed -= 10; clearInterval(timer); timer = setInterval(step, speed); }
  } else {
    snake.pop();
  }
  draw();
}

function draw() {
  ctx.clearRect(0, 0, 400, 400);
  ctx.fillStyle = '#FFB547';
  ctx.beginPath(); ctx.arc(food.x * S + S / 2, food.y * S + S / 2, S / 2 - 3, 0, Math.PI * 2); ctx.fill();
  snake.forEach((p, i) => {
    ctx.fillStyle = i === 0 ? '#3DDC97' : 'rgba(123, 92, 255, ' + (1 - i / (snake.length + 6)) + ')';
    ctx.beginPath(); ctx.roundRect(p.x * S + 1, p.y * S + 1, S - 2, S - 2, 5); ctx.fill();
  });
}

function turn(d) {
  const v = { up: { x: 0, y: -1 }, down: { x: 0, y: 1 }, left: { x: -1, y: 0 }, right: { x: 1, y: 0 } }[d];
  if (!v) return;
  if (!timer) { start(); return; }
  if (v.x !== -dir.x || v.y !== -dir.y) next = v;
}

addEventListener('keydown', (e) => {
  const k = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', w: 'up', s: 'down', a: 'left', d: 'right' }[e.key];
  if (k) { e.preventDefault(); turn(k); }
  if (e.key === ' ') { e.preventDefault(); start(); }
});
document.querySelectorAll('.pad button').forEach(b => b.onclick = () => turn(b.dataset.d));
let touch = null;
el('board').addEventListener('touchstart', (e) => { touch = e.touches[0]; if (!timer) start(); });
el('board').addEventListener('touchend', (e) => {
  if (!touch) return;
  const t = e.changedTouches[0], dx = t.clientX - touch.clientX, dy = t.clientY - touch.clientY;
  if (Math.max(Math.abs(dx), Math.abs(dy)) > 20) turn(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up'));
  touch = null;
});
el('board').addEventListener('click', start);
reset();
draw();''';

const _api_py = r'''
# A small FastAPI server. It runs in this folder's sandbox, so todos.json
# is saved there. The "Todo app" note in this folder is its frontend.
import json
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DB = Path("todos.json")
app = FastAPI(title="Todo API")


class NewTodo(BaseModel):
    text: str


def load():
    return json.loads(DB.read_text()) if DB.exists() else []


def save(todos):
    DB.write_text(json.dumps(todos, indent=2))


@app.get("/todos")
def list_todos():
    return load()


@app.post("/todos")
def add_todo(todo: NewTodo):
    todos = load()
    item = {"id": max([t["id"] for t in todos], default=0) + 1, "text": todo.text.strip(), "done": False}
    todos.append(item)
    save(todos)
    return item


@app.post("/todos/{todo_id}/toggle")
def toggle(todo_id: int):
    todos = load()
    for t in todos:
        if t["id"] == todo_id:
            t["done"] = not t["done"]
            save(todos)
            return t
    raise HTTPException(404, "No such todo")


@app.delete("/todos/{todo_id}")
def delete(todo_id: int):
    save([t for t in load() if t["id"] != todo_id])
    return {"ok": True}


print("Todo API on port 8000 · docs at http://127.0.0.1:8000/docs")
uvicorn.run(app, host="127.0.0.1", port=8000, log_level="warning")''';

const _todo_html = r'''
<main>
  <h1>✓ Todo app</h1>
  <p class="sub">Frontend note → <code>codenote.api(8000, '/todos')</code> → the FastAPI note in this folder.</p>
  <form id="add"><input id="text" placeholder="What needs doing?" autocomplete="off"><button>Add</button></form>
  <ul id="list"></ul>
  <p id="state" class="sub"></p>
</main>''';

const _todo_css = r'''
:root { color-scheme: dark; }
body { margin: 0; background: #0F0E1A; color: #ECEAF6; font: 16px/1.5 system-ui, sans-serif; }
main { max-width: 560px; margin: 0 auto; padding: 28px 18px; }
h1 { margin: 0; } .sub { color: #9C98B8; font-size: 13px; }
code { background: #1F1D38; padding: 2px 6px; border-radius: 6px; }
form { display: flex; gap: 8px; margin: 18px 0; }
input { flex: 1; background: #17162A; color: inherit; border: 1px solid #2A2846; border-radius: 10px; padding: 11px 12px; font: inherit; outline: none; }
input:focus { border-color: #7B5CFF; }
button { background: #7B5CFF; color: #fff; border: 0; border-radius: 10px; padding: 0 18px; font: 600 15px system-ui; cursor: pointer; }
ul { list-style: none; padding: 0; }
li { display: flex; align-items: center; gap: 10px; background: #17162A; border: 1px solid #2A2846; border-radius: 12px; padding: 10px 12px; margin-bottom: 8px; }
li span { flex: 1; cursor: pointer; } li.done span { text-decoration: line-through; color: #6F6A90; }
li .x { background: none; color: #FF6B7A; padding: 0 6px; font-size: 18px; }''';

const _todo_js = r'''
const url = (path) => window.codenote ? codenote.api(8000, path) : 'http://127.0.0.1:8000' + path;
const list = document.getElementById('list'), state = document.getElementById('state');

async function call(method, path, body) {
  const res = await fetch(url(path), { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

async function load() {
  try {
    const todos = await call('GET', '/todos');
    list.innerHTML = '';
    for (const t of todos) {
      const li = document.createElement('li');
      li.className = t.done ? 'done' : '';
      li.innerHTML = `<input type="checkbox" ${t.done ? 'checked' : ''}><span></span><button class="x" title="Delete">×</button>`;
      li.querySelector('span').textContent = t.text;
      li.querySelector('input').onchange = li.querySelector('span').onclick = () => call('POST', `/todos/${t.id}/toggle`).then(load);
      li.querySelector('.x').onclick = () => call('DELETE', `/todos/${t.id}`).then(load);
      list.appendChild(li);
    }
    state.textContent = todos.length ? `${todos.filter(t => !t.done).length} left · saved in todos.json in this folder's sandbox` : 'Nothing to do. Add something above.';
  } catch (e) {
    state.textContent = 'The API isn\'t running. Press ▶ Run folder on this folder (or ▶ on the FastAPI note).';
  }
}

document.getElementById('add').onsubmit = async (e) => {
  e.preventDefault();
  const input = document.getElementById('text');
  if (!input.value.trim()) return;
  await call('POST', '/todos', { text: input.value }).catch(() => {});
  input.value = '';
  load();
};
load();''';

const _py_file = r'''
# Runs in this folder's sandbox: files you write stay here until you
# open Files and press "Save a copy".
import csv, datetime, platform, random

rows = [("day", "commits")] + [(f"day {d}", random.randint(1, 12)) for d in range(1, 8)]
with open("commits.csv", "w", newline="") as f:
    csv.writer(f).writerows(rows)

total = sum(r[1] for r in rows[1:])
print(f"Python {platform.python_version()} · {datetime.date.today()}")
print(f"Wrote commits.csv with {len(rows) - 1} days, {total} commits in total.")
name = input("What's your name? ")
print(f"Nice to meet you, {name}!")''';

const _bash_info = r'''
# A quick look at the sandbox. Try the terminal button for a full shell.
echo "Shell: $0"
echo "You are in: $PWD"
echo "Home (inside the sandbox): $HOME"
echo
echo "Files here:"
ls -la
echo
echo "Can I see the real home folder?"
ls /home 2>/dev/null | head -5 || echo "no"
echo "(empty or missing = the sandbox is hiding it)"''';
