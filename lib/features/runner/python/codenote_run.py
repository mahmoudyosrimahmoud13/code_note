"""Runs a CodeNote Python block like a Jupyter cell: the value of the last
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
