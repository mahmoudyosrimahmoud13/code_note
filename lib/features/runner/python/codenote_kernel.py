"""A small Jupyter-like kernel for one CodeNote note: Python blocks run in
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
