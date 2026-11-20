"""A matplotlib backend for CodeNote: plt.show() puts the figures in the
output instead of opening a window."""
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg

FigureCanvas = FigureCanvasAgg
FigureManager = FigureManagerBase


def show(*args, **kwargs):
    from codenote_display import show_figures
    show_figures()
