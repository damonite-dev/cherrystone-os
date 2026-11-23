#!/usr/bin/env python3
# First-run setup (the "out-of-box experience"): walks through getting
# online, keyboard and time zone, your name, a password and light or dark,
# one page at a time, then says you're all set.
# "cherrystone-welcome --settings" shows only the keyboard and time zone page.
import os
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

GLib.set_prgname("CherryWelcome")   # window class Cherry*: the window manager focuses it
SETTINGS = "--settings" in sys.argv[1:]
# From the USB stick (not installed): no name or password yet (those come
# with Install), and the answers are kept on the stick for next time
try:
    LIVE = "cherrystone.live" in open("/proc/cmdline").read().split()
except OSError:
    LIVE = False
HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config/cherrystone")
LAYOUTS = ("us gb de fr es it pt br latam ca nl be ch at se no dk fi is ie pl cz sk hu ro bg "
           "gr tr ru ua by lt lv ee si hr rs il ara in jp kr cn th vn").split()


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except OSError:
        return default


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(data)


def current_layout():
    try:
        out = subprocess.run(["setxkbmap", "-query"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            if line.startswith("layout:"):
                return line.split()[1].split(",")[0]
    except OSError:
        pass
    return "us"


def zones():
    found = set()
    try:
        with open("/usr/share/zoneinfo/zone1970.tab") as f:
            for line in f:
                if not line.startswith("#") and len(line.split("\t")) >= 3:
                    found.add(line.split("\t")[2].strip())
    except OSError:
        pass
    return ["UTC"] + sorted(found)


def combo(items, current):
    box = Gtk.ComboBoxText()
    for item in items:
        box.append_text(item)
    box.set_active(items.index(current) if current in items else 0)
    return box


def online():
    r = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True)
    return r.stdout.strip() == "connected"


try:                                       # Personalize > Accent colour
    import sys as _sys
    _sys.path.insert(0, "/usr/lib/cherrystone")
    from accent import accent as _accent
except Exception:
    def _accent(css):
        return css


CSS = b"""
window.oobe { background: #ffffff; }
.oobe .band { background: #d81e3c; }
.oobe .step { color: #d81e3c; font-size: 13px; }
.oobe .title { font-size: 34px; font-weight: 300; color: #202124; }
.oobe .sub { font-size: 14px; color: #5f6368; }
.oobe .field { font-size: 13px; color: #5f6368; }
.oobe .error { color: #c5221f; }
.oobe .dot { min-width: 8px; min-height: 8px; background: #dadce0; }
.oobe .dot.on { background: #d81e3c; }
.oobe button.next { background: #d81e3c; color: #ffffff; border: none; border-radius: 0;
                    padding: 8px 22px; box-shadow: none; }
.oobe button.next:hover { background: #b8172f; }
.oobe button.link { background: none; border: none; box-shadow: none; color: #5f6368; }
.oobe button.link:hover { color: #202124; }
.oobe radiobutton.pick, .oobe togglebutton.pick { padding: 0; }
.oobe .swatch { min-width: 120px; min-height: 76px; border: 2px solid #dadce0; }
.oobe .swatch.light { background: #ffffff; }
.oobe .swatch.dark { background: #18181a; }
.oobe .chosen .swatch { border-color: #d81e3c; }
"""

# Dark: the same page in dark colours, swapped in the moment you pick Dark
DARK_CSS = b"""
window.oobe { background: #18181a; }
.oobe .title { color: #ececef; }
.oobe .sub, .oobe .field { color: #a0a0a6; }
.oobe .dot { background: #3a3a40; }
.oobe button.link { color: #a0a0a6; }
.oobe button.link:hover { color: #ececef; }
.oobe .swatch { border-color: #3a3a40; }
.oobe .swatch.dark { border-color: #3a3a40; }
.oobe entry, .oobe combobox button { background: #26262a; color: #ececef; border-color: #3a3a40; }
.oobe headerbar, .oobe .titlebar { background: #18181a; color: #ececef; }
"""

provider = Gtk.CssProvider()
provider.load_from_data(_accent(CSS))
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider,
                                         Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
dark_provider = Gtk.CssProvider()
dark_provider.load_from_data(_accent(DARK_CSS))
dark_on = {"v": False}


def set_dark(on):
    """Switch this window between light and dark right away."""
    if on == dark_on["v"]:
        return
    dark_on["v"] = on
    screen = Gdk.Screen.get_default()
    Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", on)
    if on:
        Gtk.StyleContext.add_provider_for_screen(screen, dark_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)
    else:
        Gtk.StyleContext.remove_provider_for_screen(screen, dark_provider)


if read(os.path.join(CONF, "theme")) == "dark":
    set_dark(True)


def lab(text, cls, wrap=False):
    l = Gtk.Label(label=text, xalign=0)
    l.get_style_context().add_class(cls)
    if wrap:
        l.set_line_wrap(True)
        l.set_max_width_chars(52)
    return l


win = Gtk.Window(title="Keyboard and time zone" if SETTINGS else "Set up Cherrystone")
win.get_style_context().add_class("oobe")
win.set_icon_name("cherrystone")
win.set_position(Gtk.WindowPosition.CENTER)
win.set_resizable(False)
win.set_default_size(620, 440)
win.connect("destroy", Gtk.main_quit)

root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
band = Gtk.Box()
band.get_style_context().add_class("band")
band.set_size_request(-1, 6)
root.pack_start(band, False, False, 0)

stack = Gtk.Stack()
stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
stack.set_transition_duration(0 if os.environ.get("CHERRYSTONE_OLD_PC") else 220)
body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
body.set_border_width(32)
body.pack_start(stack, True, True, 0)
root.pack_start(body, True, True, 0)

# bottom: progress dots on the left, Back / Skip / Next on the right
bottom = Gtk.Box(spacing=8)
bottom.set_border_width(20)
dots = Gtk.Box(spacing=6)
dots.set_valign(Gtk.Align.CENTER)
bottom.pack_start(dots, False, False, 12)
nextb = Gtk.Button(label="Next")
nextb.get_style_context().add_class("next")
skipb = Gtk.Button(label="Skip")
skipb.get_style_context().add_class("link")
backb = Gtk.Button(label="Back")
backb.get_style_context().add_class("link")
bottom.pack_end(nextb, False, False, 0)
bottom.pack_end(skipb, False, False, 0)
bottom.pack_end(backb, False, False, 0)
root.pack_end(bottom, False, False, 0)

pages = []   # (name, on_next -> True to go on, can_skip)
steps = []   # the "2 of 4" labels, filled in once every page is made


def page(name, step, title, sub, on_next=None, can_skip=False):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    if step:
        sl = lab("", "step")
        steps.append(sl)
        box.pack_start(sl, False, False, 0)
    box.pack_start(lab(title, "title"), False, False, 0)
    if sub:
        box.pack_start(lab(sub, "sub", wrap=True), False, False, 0)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    content.set_margin_top(14)
    box.pack_start(content, True, True, 0)
    stack.add_named(box, name)
    pages.append((name, on_next or (lambda: True), can_skip))
    return content


# ---------------------------------------------------------------- the pages

cur_kb, cur_tz = current_layout(), read("/etc/timezone", "UTC")
kb_box, tz_box = combo(LAYOUTS, cur_kb), combo(zones(), cur_tz)


def save_region():
    kb, tz = kb_box.get_active_text(), tz_box.get_active_text()
    if kb in LAYOUTS and kb != current_layout():
        subprocess.run(["setxkbmap", "-layout", kb])
        write(os.path.join(CONF, "keyboard"), kb + "\n")
    if tz and tz != read("/etc/timezone", "UTC"):
        if subprocess.run(["doas", "/usr/local/sbin/cherrystone-settz", tz]).returncode == 0:
            subprocess.run(["pkill", "-USR1", "-x", "tint2"])   # the clock picks up the new zone
    return True


if not SETTINGS:
    c = page("hello", "", "hi there.",
             "Let's get your computer ready. It only takes a minute, and you can change "
             "all of this later in Settings.")
    c.set_valign(Gtk.Align.CENTER)
    c.pack_start(Gtk.Image.new_from_file("/usr/share/cherrystone/stony/stony-excited-small.png"),
                 False, False, 0)

    # Internet
    c = page("net", "#", "get online.",
             "Pick a Wi-Fi network, or plug in a cable. Most of Cherrystone runs on the web.",
             can_skip=True)
    net_label = lab("", "sub")
    wifi = Gtk.Button(label="Choose a Wi-Fi network")
    wifi.get_style_context().add_class("next")
    wifi.set_halign(Gtk.Align.START)
    wifi.connect("clicked", lambda *_: subprocess.Popen(["cherrystone-wifi"]))
    c.pack_start(net_label, False, False, 0)
    c.pack_start(wifi, False, False, 0)

    def refresh():
        on = online()
        net_label.set_markup("<b>You're online.</b>" if on else "Not connected yet.")
        wifi.set_visible(not on)
        return True
    refresh()
    GLib.timeout_add_seconds(3, refresh)

# Keyboard and time zone
c = page("region", "" if SETTINGS else "#", "keyboard and time.",
         "So the keys type what they say, and the clock shows your time.", save_region)
grid = Gtk.Grid(column_spacing=16, row_spacing=10)
for r, (t, w) in enumerate((("Keyboard layout", kb_box), ("Time zone", tz_box))):
    grid.attach(lab(t, "field"), 0, r, 1, 1)
    w.set_hexpand(True)
    grid.attach(w, 1, r, 1, 1)
c.pack_start(grid, False, False, 0)

if not SETTINGS and not LIVE:
    # Name
    name = Gtk.Entry()
    name.set_max_length(40)
    name.set_placeholder_text("Your name")
    old = read(os.path.join(CONF, "name"))
    if old and old != "Cherrystone":
        name.set_text(old)

    def save_name():
        n = name.get_text().strip()[:40]
        if n:
            write(os.path.join(CONF, "name"), n + "\n")
            subprocess.Popen(["cherrystone-shelf"], stderr=subprocess.DEVNULL)
        return True
    c = page("name", "#", "what's your name?",
             "It's shown when you sign in and on the lock screen.", save_name, can_skip=True)
    c.pack_start(name, False, False, 0)
    name.connect("activate", lambda *_: go(1))

    # Password
    pw1, pw2 = Gtk.Entry(), Gtk.Entry()
    pw_err = lab("", "error")

    def save_pass():
        a, b = pw1.get_text(), pw2.get_text()
        if not a and not b:
            return True
        if a != b:
            pw_err.set_text("The two passwords don't match.")
            return False
        r = subprocess.run(["doas", "/usr/local/sbin/cherrystone-setpass"], input=(a + "\n").encode(),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0:
            pw_err.set_text("Couldn't set the password. You can try again in Settings.")
            return False
        return True
    c = page("pass", "#", "add a password.",
             "Keeps other people out when you sign in or the screen locks. Leave it empty "
             "if nobody else uses this computer.", save_pass, can_skip=True)
    for e, hint in ((pw1, "Password"), (pw2, "Type it again")):
        e.set_visibility(False)
        e.set_placeholder_text(hint)
        c.pack_start(e, False, False, 0)
    c.pack_start(pw_err, False, False, 0)
    pw1.connect("activate", lambda *_: pw2.grab_focus())
    pw2.connect("activate", lambda *_: go(1))

if not SETTINGS:
    # Light or dark, and the accent colour
    c = page("look", "#", "light or dark?", "You can switch any time in Personalize.")
    looks = Gtk.Box(spacing=16)
    choice = {"v": "dark" if read(os.path.join(CONF, "theme")) == "dark" else "light"}
    holders = {}
    for v, t in (("light", "Light"), ("dark", "Dark")):
        b = Gtk.Button()
        b.get_style_context().add_class("link")
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        sw = Gtk.Box()
        sw.get_style_context().add_class("swatch")
        sw.get_style_context().add_class(v)
        inner.pack_start(sw, False, False, 0)
        inner.pack_start(lab(t, "sub"), False, False, 0)
        b.add(inner)
        holders[v] = b

        def pick(_b, v=v):
            choice["v"] = v
            for k, h in holders.items():
                (h.get_style_context().add_class if k == v else h.get_style_context().remove_class)("chosen")
            # everything changes now, not after Next: this window, and the
            # rest of Cherrystone (menus, home page, the window borders)
            set_dark(v == "dark")
            if v != (read(os.path.join(CONF, "theme")) or "light"):
                subprocess.Popen(["cherrystone-theme", v])
        b.connect("clicked", pick)
        looks.pack_start(b, False, False, 0)
    holders[choice["v"]].get_style_context().add_class("chosen")
    c.pack_start(looks, False, False, 0)

    # accent colour chips; this window and everything else change right away
    c.pack_start(lab("Accent colour", "field"), False, False, 8)
    chips_box = Gtk.Box(spacing=8)
    acc = {"v": read(os.path.join(CONF, "accent"), "cherry") or "cherry"}
    chips = {}
    for an, ah in (("cherry", "#d81e3c"), ("blue", "#2b6fd6"), ("green", "#2e9b4f"), ("orange", "#e0701c"),
                   ("purple", "#6b4bc9"), ("teal", "#0f8f8a"), ("pink", "#c43e8a")):
        cb = Gtk.Button()
        cb.set_tooltip_text(an.capitalize())
        cpv = Gtk.CssProvider()
        cpv.load_from_data(("button { background: %s; background-image: none; border-radius: 0; box-shadow: none;"
                            " border: 3px solid transparent; min-width: 30px; min-height: 30px; }"
                            " button.picked { border-color: #202124; }" % ah).encode())
        cb.get_style_context().add_provider(cpv, Gtk.STYLE_PROVIDER_PRIORITY_USER + 3)
        chips[an] = cb

        def pick_accent(_b, an=an):
            acc["v"] = an
            for k, ch in chips.items():
                (ch.get_style_context().add_class if k == an else ch.get_style_context().remove_class)("picked")
            subprocess.run(["cherrystone-theme", "accent", an])
            provider.load_from_data(_accent(CSS))           # this window too
            dark_provider.load_from_data(_accent(DARK_CSS))
        cb.connect("clicked", pick_accent)
        chips_box.pack_start(cb, False, False, 0)
    chips.get(acc["v"], chips["cherry"]).get_style_context().add_class("picked")
    c.pack_start(chips_box, False, False, 0)

    def save_look():
        return True                        # already done when you picked
    pages[-1] = (pages[-1][0], save_look, False)

    # Done
    c = page("done", "", "you're all set.",
             "Press the cherry (or the Windows key) to see your apps. The tour shows the rest."
             + ("\n\nRunning from the USB stick: your name and a password come when you install "
                "Cherrystone. These settings are kept on the stick, so next time you start "
                "straight away." if LIVE else ""))
    tour = Gtk.Button(label="Take the tour")
    tour.get_style_context().add_class("link")
    tour.set_halign(Gtk.Align.START)
    tour.connect("clicked", lambda *_: (subprocess.Popen(["cherrystone-browser", "file:///usr/share/cherrystone/tour.html"]), finish()))
    c.pack_start(tour, False, False, 0)

# ------------------------------------------------------------- moving along

for k, sl in enumerate(steps):
    sl.set_text("%d of %d" % (k + 1, len(steps)))
for _ in pages:
    d = Gtk.Box()
    d.get_style_context().add_class("dot")
    dots.pack_start(d, False, False, 0)
state = {"i": 0}


def show(i):
    state["i"] = i
    name_, _, can_skip = pages[i]
    stack.set_visible_child_name(name_)
    last = i == len(pages) - 1
    nextb.set_label(("Apply" if SETTINGS else "Get started") if last else "Next")
    backb.set_visible(i > 0)
    skipb.set_visible(can_skip)
    dots.set_visible(len(pages) > 1)
    for k, d in enumerate(dots.get_children()):
        (d.get_style_context().add_class if k == i else d.get_style_context().remove_class)("on")
    nextb.grab_focus()
    if name_ == "name":
        name.grab_focus()
    elif name_ == "pass":
        pw1.grab_focus()


def remember_on_stick():
    """From the USB stick: keep these answers on it, so setup doesn't come back."""
    vals = {"keyboard": read(os.path.join(CONF, "keyboard")) or current_layout(),
            "timezone": read("/etc/timezone", "UTC"),
            "theme": read(os.path.join(CONF, "theme"), "light"),
            "accent": read(os.path.join(CONF, "accent"), "cherry")}
    data = "".join("%s=%s\n" % kv for kv in vals.items())
    try:
        subprocess.run(["doas", "/usr/local/sbin/cherrystone-livesetup", "save"], input=data.encode(),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    except (OSError, subprocess.SubprocessError):
        pass


def finish():
    os.makedirs(CONF, exist_ok=True)
    open(os.path.join(CONF, "welcomed"), "a").close()
    if LIVE and not SETTINGS:
        remember_on_stick()
    Gtk.main_quit()


def go(step, skip=False):
    i = state["i"]
    if step > 0 and not skip and not pages[i][1]():
        return
    if step > 0 and i == len(pages) - 1:
        finish()
        return
    show(max(0, min(len(pages) - 1, i + step)))


nextb.connect("clicked", lambda *_: go(1))
skipb.connect("clicked", lambda *_: go(1, skip=True))
backb.connect("clicked", lambda *_: go(-1))
win.add(root)
win.show_all()
if not SETTINGS:
    refresh()
show(0)
Gtk.main()
