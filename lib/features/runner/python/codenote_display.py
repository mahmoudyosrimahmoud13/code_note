"""Rich output for CodeNote, like Jupyter: plots become images, DataFrames
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
