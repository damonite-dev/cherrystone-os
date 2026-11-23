# Accent colour (Settings > Personalize): Cherrystone's own apps run their
# CSS through accent() to swap the cherry reds for the chosen colour.
# cherrystone-theme writes the swaps to ~/.config/cherrystone/accent-map as
# "d81e3c:2b6fd6 b3122f:245cb2 ..." (nothing there = cherry, no change).
# Installed as /usr/lib/cherrystone/accent.py.
import os
import re


def pairs():
    try:
        words = open(os.path.expanduser("~/.config/cherrystone/accent-map")).read().split()
    except OSError:
        return []
    return [w.split(":", 1) for w in words if ":" in w]


def accent(css):
    p = pairs()
    if not p:
        return css
    raw = isinstance(css, bytes)
    s = css.decode() if raw else css
    # two passes, so a new colour is never swapped again by a later pair
    for i, (a, _) in enumerate(p):
        s = re.sub("#" + re.escape(a), "@ACC%d@" % i, s, flags=re.I)
    for i, (_, b) in enumerate(p):
        s = s.replace("@ACC%d@" % i, "#" + b)
    return s.encode() if raw else s


def colour():
    """The main accent colour, like "#d81e3c"."""
    for a, b in pairs():
        if a.lower() == "d81e3c":
            return "#" + b
    return "#d81e3c"
