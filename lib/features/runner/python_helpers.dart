// Generated from lib/features/runner/python/*.py: edit those files and
// keep this map in sync (test/features/runner/python_helpers_test.dart checks).

/// Small Python files CodeNote puts next to every Python run: Jupyter-style
/// rich output (plots, tables, images), a matplotlib backend, a one-shot
/// runner and the per-note kernel that lets blocks share variables.
const pythonHelpers = <String, String>{
  'codenote_display.py': r'''"""Rich output for CodeNote, like Jupyter: plots become images, DataFrames
become tables, and the last expression of a block is shown.

CodeNote reads lines that start with MARK from the output and draws them.
Everything stays in the folder's sandbox (.codenote/out)."""
import json
import os
import sys
import uuid

MARK = "\x1ecodenote:"
OUT = os.environ.get("CODENOTE_OUT") or os.path.join(os.getcwd(), ".codenote", "out")
MAX_ROWS = 200


def _path(ext):
    os.makedirs(OUT, exist_ok=True)
    return os.path.join(OUT, f"{uuid.uuid4().hex[:12]}.{ext}")


def _emit(kind, path, note=""):
    sys.stdout.flush()
    sys.stdout.write(f"{MARK}{kind}:{path}" + (f"|{note}" if note else "") + "\n")
    sys.stdout.flush()


def show_figures():
    """Saves every open matplotlib figure as a PNG and shows it."""
    plt = sys.modules.get("matplotlib.pyplot")
    if plt is None:
        return
    for num in plt.get_fignums():
        fig = plt.figure(num)
        path = _path("png")
        fig.savefig(path, dpi=110, bbox_inches="tight", facecolor="white")
        _emit("image", path)
        plt.close(fig)


def _table(df):
    shape = f"{df.shape[0]} rows × {df.shape[1]} columns"
    data = json.loads(df.head(MAX_ROWS).to_json(orient="split", date_format="iso", default_handler=str))
    payload = {
        "columns": [str(c) for c in data.get("columns", [])],
        "index": [str(i) for i in data.get("index", [])],
        "data": data.get("data", []),
        "shape": shape,
        "truncated": df.shape[0] > MAX_ROWS,
    }
    path = _path("json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, default=str)
    _emit("table", path, shape)


def _write(ext, data, mode="w"):
    path = _path(ext)
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as f:
        f.write(data)
    return path


def _first(data):
    """Some _repr_*_ methods return (data, metadata)."""
    return data[0] if isinstance(data, tuple) else data


def _bundle(obj):
    """The object's Jupyter display data as {mime type: data}."""
    bundle = {}
    mb = getattr(obj, "_repr_mimebundle_", None)
    if callable(mb):
        try:
            got = mb(include=None, exclude=None)
        except TypeError:
            got = mb()
        got = _first(got)
        if isinstance(got, dict):
            bundle.update(got)
    for mime, attr in (("image/png", "_repr_png_"), ("image/jpeg", "_repr_jpeg_"),
                       ("image/svg+xml", "_repr_svg_"), ("text/markdown", "_repr_markdown_"),
                       ("text/latex", "_repr_latex_"), ("text/html", "_repr_html_"),
                       ("application/json", "_repr_json_")):
        if mime in bundle:
            continue
        fn = getattr(obj, attr, None)
        if callable(fn):
            try:
                val = _first(fn())
            except Exception:
                val = None
            if val:
                bundle[mime] = val
    return bundle


def _as_dataframe(obj):
    """pandas DataFrame/Series, or something that converts to one (polars...)."""
    mod = type(obj).__module__ or ""
    name = type(obj).__name__
    if mod.startswith("pandas") and name == "DataFrame":
        return obj
    if mod.startswith("pandas") and name == "Series":
        return obj.to_frame()
    if not mod.startswith("pandas") and name in ("DataFrame", "Series", "LazyFrame") and hasattr(obj, "to_pandas"):
        try:
            frame = obj.collect().to_pandas() if name == "LazyFrame" else obj.to_pandas()
            return frame.to_frame() if type(frame).__name__ == "Series" else frame
        except Exception:
            return None
    return None


def display(*objs):
    """Shows objects the way Jupyter would, for any library that supports
    Jupyter's display methods (pandas, matplotlib, seaborn, plotly, Pillow,
    sympy, altair, torch/torchvision images and more)."""
    import base64

    for obj in objs:
        if obj is None:
            continue
        name = type(obj).__name__
        mod = type(obj).__module__ or ""
        try:
            frame = _as_dataframe(obj)
            if frame is not None:
                _table(frame)
                continue
            # Figures: matplotlib Figure, seaborn FacetGrid/PairGrid/JointGrid...
            fig = obj if hasattr(obj, "savefig") else getattr(obj, "figure", None) if mod.startswith("seaborn") else None
            if fig is not None and callable(getattr(fig, "savefig", None)):
                path = _path("png")
                fig.savefig(path, dpi=110, bbox_inches="tight", facecolor="white")
                _emit("image", path)
                plt = sys.modules.get("matplotlib.pyplot")
                if plt is not None and hasattr(fig, "number"):
                    plt.close(fig)
                continue
            if mod.startswith("matplotlib"):
                # An Axes or artists from a plot call: show the figure.
                show_figures()
                continue
            b = _bundle(obj)
            if "image/png" in b:
                data = b["image/png"]
                _emit("image", _write("png", base64.b64decode(data) if isinstance(data, str) else data, "wb"))
                continue
            if "image/jpeg" in b:
                data = b["image/jpeg"]
                _emit("image", _write("jpg", base64.b64decode(data) if isinstance(data, str) else data, "wb"))
                continue
            if "text/markdown" in b:
                _emit("markdown", _write("md", b["text/markdown"]))
                continue
            if "text/html" in b or "image/svg+xml" in b:
                body = b.get("text/html") or b["image/svg+xml"]
                if isinstance(body, bytes):
                    body = body.decode("utf-8", "replace")
                _emit("html", _write("html", "<!DOCTYPE html><meta charset='utf-8'>" + body), name)
                if "text/plain" in b:
                    print(b["text/plain"])
                continue
            if "text/latex" in b:
                print(b["text/latex"])
                continue
            if "application/json" in b:
                print(json.dumps(b["application/json"], indent=2, default=str))
                continue
            if "text/plain" in b:
                print(b["text/plain"])
                continue
        except Exception as e:  # never let display break the script
            print(f"(couldn't show {name} as rich output: {e})", file=sys.stderr)
        print(repr(obj))
''',
  'codenote_mpl.py': r'''"""A matplotlib backend for CodeNote: plt.show() puts the figures in the
output instead of opening a window."""
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg

FigureCanvas = FigureCanvasAgg
FigureManager = FigureManagerBase


def show(*args, **kwargs):
    from codenote_display import show_figures
    show_figures()
''',
  'codenote_run.py': r'''"""Runs a CodeNote Python block like a Jupyter cell: the value of the last
line is shown, and figures still open at the end are shown too."""
import ast
import builtins
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
os.environ.setdefault("MPLBACKEND", "module://codenote_mpl")

from codenote_display import display, show_figures  # noqa: E402

builtins.display = display  # display(x) works anywhere, like in Jupyter


def main(path):
    with open(path, encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=path)
    last = None
    if tree.body and isinstance(tree.body[-1], ast.Expr):
        last = ast.Expression(tree.body.pop().value)
    g = {"__name__": "__main__", "__file__": path, "__builtins__": builtins, "display": display}
    sys.argv = [path]
    sys.path.insert(0, os.getcwd())
    exec(compile(tree, path, "exec"), g)
    if last is not None:
        value = eval(compile(last, path, "eval"), g)
        if value is not None:
            display(value)
    show_figures()


if __name__ == "__main__":
    main(sys.argv[1])
''',
  'codenote_kernel.py': r'''"""A small Jupyter-like kernel for one CodeNote note: Python blocks run in
it one after another and share their variables, like notebook cells.

CodeNote sends one JSON line per block: {"cell": "<id>", "path": "<file>"}.
After each block the kernel prints MARK + "done:<id>:ok|error|interrupted".
While a block runs, input() reads the answer typed under the output."""
import ast
import builtins
import json
import os
import re
import signal
import subprocess
import sys
import traceback

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
sys.path.insert(0, os.getcwd())
os.environ.setdefault("MPLBACKEND", "module://codenote_mpl")

from codenote_display import MARK, display, show_figures  # noqa: E402

builtins.display = display
_stdin = sys.stdin


def _input(prompt=""):
    # The prompt gets its own line so CodeNote can show it right away.
    print(str(prompt), flush=True)
    line = _stdin.readline()
    if not line:
        raise EOFError("No input")
    return line.rstrip("\n")


builtins.input = _input


def _sh(cmd, pip=False):
    """Runs a shell command for `!cmd` and `%pip ...` lines.

    The command can't read the kernel's input (that's how CodeNote talks to
    the kernel). For `%pip`, a quiet install shows a ticking "still working"
    line so a long download never looks stuck, and the end says how it went.
    Interrupt stops the command too."""
    import time
    quiet = pip and any(a in ("-q", "--quiet", "-qq") for a in cmd.split())
    start = time.time()
    if pip:
        print("pip: " + cmd.split(" -m pip ", 1)[-1], flush=True)
    proc = subprocess.Popen(cmd, shell=True, stdin=subprocess.DEVNULL)
    ticked = False
    try:
        while True:
            try:
                code = proc.wait(timeout=2)
                break
            except subprocess.TimeoutExpired:
                if quiet:
                    sys.stdout.write(f"\rpip is downloading and installing… {int(time.time() - start)}s")
                    sys.stdout.flush()
                    ticked = True
    except BaseException:
        proc.kill()
        proc.wait()
        if ticked:
            print(flush=True)
        raise
    if pip:
        took = int(time.time() - start)
        end = "\r" if ticked else ""
        if code == 0:
            print(f"{end}✓ pip finished in {took}s", flush=True)
        else:
            print(f"{end}✗ pip stopped with exit code {code} after {took}s", flush=True)


_magic = re.compile(r"^(\s*)(!|%pip\s|%pip$)(.*)$")


def _expand(source):
    """Turns Jupyter's `!ls` and `%pip install x` lines into Python."""
    out = []
    for line in source.split("\n"):
        m = _magic.match(line)
        if not m:
            out.append(line)
            continue
        indent, kind, rest = m.groups()
        pip = kind != "!"
        cmd = rest if not pip else f'"{sys.executable}" -m pip {rest.strip()}'
        out.append(f"{indent}__codenote_sh__({cmd!r}, {pip!r})")
    return "\n".join(out)


namespace = {"__name__": "__main__", "__builtins__": builtins, "display": display, "__codenote_sh__": _sh}
count = 0


def run_cell(path):
    global count
    count += 1
    print(f"{MARK}count:{count}", flush=True)
    with open(path, encoding="utf-8") as f:
        source = _expand(f.read())
    tree = ast.parse(source, filename=path)
    last = None
    if tree.body and isinstance(tree.body[-1], ast.Expr):
        last = ast.Expression(tree.body.pop().value)
    namespace["__file__"] = path
    exec(compile(tree, path, "exec"), namespace)
    if last is not None:
        value = eval(compile(last, path, "eval"), namespace)
        if value is not None:
            display(value)
            namespace["_"] = value
    show_figures()


def _watch_interrupts():
    """CodeNote asks to stop the running block by creating a file (signals
    don't reach Python inside the sandbox, and Windows has none)."""
    import _thread
    import threading
    import time

    flag = os.environ.get("CODENOTE_INTERRUPT")
    if not flag:
        return

    def loop():
        while True:
            time.sleep(0.2)
            if os.path.exists(flag):
                try:
                    os.remove(flag)
                except OSError:
                    pass
                _thread.interrupt_main()

    threading.Thread(target=loop, daemon=True).start()


def main():
    signal.signal(signal.SIGINT, signal.default_int_handler)
    _watch_interrupts()
    print(f"{MARK}ready:{sys.version.split()[0]}", flush=True)
    while True:
        line = _stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue  # stray answer meant for input(); ignore
        cell = msg.get("cell", "")
        status = "ok"
        try:
            run_cell(msg["path"])
        except KeyboardInterrupt:
            status = "interrupted"
            print("KeyboardInterrupt: stopped", file=sys.stderr, flush=True)
        except SystemExit:
            status = "ok"
        except BaseException:
            status = "error"
            etype, value, tb = sys.exc_info()
            # Hide the kernel's own frames, like Jupyter does.
            frames = [f for f in traceback.extract_tb(tb) if os.path.basename(f.filename) != "codenote_kernel.py"]
            print("Traceback (most recent call last):", file=sys.stderr)
            print("".join(traceback.format_list(frames)).rstrip(), file=sys.stderr)
            print("".join(traceback.format_exception_only(etype, value)).rstrip(), file=sys.stderr, flush=True)
        sys.stdout.flush()
        sys.stderr.flush()
        print(f"{MARK}done:{cell}:{status}", flush=True)


if __name__ == "__main__":
    main()
''',
};
