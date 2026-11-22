#!/usr/bin/env python3
# Cherrystone's small screens, all in the same look as Settings and the
# sign-in screen. Installed as /usr/local/bin/cherrystone-ui:
#   wifi | power | slider volume|brightness | password | notifications |
#   profile | wallpaper | display | touchpad | about | shortcuts | tiles |
#   message TITLE HEADING TEXT
import atexit, json, os, re, shutil, signal, subprocess, sys, threading, time
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib, Pango

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config", "cherrystone")
GUEST = os.environ.get("USER") == "guest"

CSS = b"""
window.cherry { background: #ffffff; }
window.pop { border-top: 3px solid #d81e3c; }
.title { font-size: 24px; font-weight: 300; color: #202124; }
.big { font-size: 30px; font-weight: 300; color: #202124; }
.sub { color: #5f6368; }
.small { font-size: 9px; color: #5f6368; }
.error { color: #c5221f; }
.bold { font-weight: bold; color: #202124; }
.kbd { background: #f1f3f4; border-radius: 0; padding: 2px 8px; color: #202124; font-weight: bold; }
.card { background: #f1f3f4; border-radius: 0; padding: 10px 14px; }
button.main { background: #d81e3c; background-image: none; color: #ffffff; border: none;
              border-radius: 0; padding: 7px 18px; box-shadow: none; text-shadow: none; }
button.main label { color: #ffffff; }
button.main:hover { background: #b3122f; }
button.main:disabled { background: #e8a3ae; }
button.plain { background: #f1f3f4; background-image: none; border: none; border-radius: 0;
               padding: 7px 18px; box-shadow: none; color: #202124; text-shadow: none; }
button.plain:hover { background: #fde4e8; }
button.link { background: none; background-image: none; border: none; box-shadow: none;
              color: #d81e3c; padding: 4px 6px; }
button.link label { color: #d81e3c; }
button.round { background: #f1f3f4; background-image: none; border: none; border-radius: 24px;
               min-width: 46px; min-height: 46px; padding: 0; box-shadow: none; }
button.round:hover { background: #fde4e8; }
button.icon { background: none; background-image: none; border: none; box-shadow: none;
              border-radius: 0; padding: 4px; }
button.icon:hover { background: #fde4e8; }
radiobutton.seg, button.seg { background: #f1f3f4; background-image: none; border: none; box-shadow: none;
              border-radius: 0; padding: 6px 14px; color: #202124; }
button.seg:checked { background: #d81e3c; color: #ffffff; }
button.seg:checked label { color: #ffffff; }
list.cherry, list.cherry row { background: #ffffff; }
list.cherry row { padding: 8px 10px; border-radius: 0; }
list.cherry row:hover { background: #f8eef0; }
list.cherry row:selected { background: #fde4e8; color: #202124; }
entry { border-radius: 0; padding: 6px 14px; }
entry:focus { border-color: #d81e3c; box-shadow: inset 0 0 0 1px #d81e3c; }
scale highlight { background: #d81e3c; }
scale slider { background: #ffffff; border: 2px solid #d81e3c; }
switch { background: #ffffff; border: 2px solid #202124; border-radius: 0; }
switch slider { background: #202124; border: none; border-radius: 0; min-width: 18px; min-height: 18px; margin: 1px; }
switch:checked { background: #d81e3c; border-color: #d81e3c; }
switch:checked slider { background: #ffffff; }
flowbox flowboxchild { padding: 6px; border-radius: 0; }
flowbox flowboxchild:hover { background: #f8eef0; }
flowbox flowboxchild:selected { background: #fde4e8; }
progressbar trough { min-height: 8px; border-radius: 0; background: #f1f3f4; border: none; }
progressbar progress { min-height: 8px; border-radius: 0; background: #d81e3c; border: none; }
/* smooth hover and a darker press, like a real button */
button, list.cherry row, flowbox flowboxchild { transition: background-color 150ms ease-out, color 150ms ease-out; }
button label, button image { transition: none; -gtk-icon-transform: none; }
button.main:active { background: #8e0f26; }
button.plain:active, button.round:active, button.icon:active, list.cherry row:active { background: #f9c9d2; }
"""


# ------------------------------------------------------------------ helpers

def run(cmd):
    """Start something and don't wait (a shell command, or an argv list)."""
    subprocess.Popen(cmd, shell=isinstance(cmd, str), start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def out(cmd, timeout=10):
    try:
        return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True,
                              text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


def ok(cmd, **kw):
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw).returncode == 0
    except Exception:
        return False


def notify(title, body="", icon="cherrystone"):
    run(["notify-send", "-i", icon, title, body])


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(data)


def icon(names, size):
    theme = Gtk.IconTheme.get_default()
    names = names.split()
    pick = next((n for n in names if theme.has_icon(n)), names[-1])
    img = Gtk.Image.new_from_icon_name(pick, Gtk.IconSize.DIALOG)
    img.set_pixel_size(size)
    return img


def label(text, *classes, xalign=0, wrap=False, markup=False):
    lab = Gtk.Label(xalign=xalign)
    lab.set_markup(text) if markup else lab.set_text(text)
    for c in classes:
        lab.get_style_context().add_class(c)
    if wrap:
        lab.set_line_wrap(True)
        lab.set_max_width_chars(48)
    return lab


def button(text, kind="plain", action=None):
    b = Gtk.Button(label=text)
    b.get_style_context().add_class(kind)
    if action:
        b.connect("clicked", lambda *_: action())
    return b


def picture(path, size):
    try:
        return Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True))
    except Exception:
        return icon("avatar-default", size)


def face_path():
    p = os.path.join(HOME, ".face")
    return p if os.path.isfile(p) else "/usr/share/icons/hicolor/128x128/apps/cherrystone.png"


def window(title, icon_name="cherrystone", width=440, heading=None):
    """A normal window: white, a big title, Esc closes it."""
    win = Gtk.Window(title=title)
    win.set_icon_name(icon_name)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_resizable(False)
    win.get_style_context().add_class("cherry")
    win.connect("destroy", Gtk.main_quit)
    # Esc closes it (not while it can't be closed, like halfway through installing)
    win.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and w.get_deletable() and w.destroy())
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.set_border_width(22)
    box.set_size_request(width, -1)
    box.pack_start(label(heading or title, "title"), False, False, 0)
    win.add(box)
    return win, box


def buttons(box, *items):
    """A row of buttons at the bottom right; items are Gtk.Buttons."""
    row = Gtk.Box(spacing=8)
    for b in reversed(items):
        row.pack_end(b, False, False, 0)
    box.pack_end(row, False, False, 0)
    return row


def single(name):
    """Only one of these at a time: a second click on the same thing closes it."""
    pidf = "/tmp/cherrystone-%s.%d" % (name, os.getuid())
    try:
        pid = int(open(pidf).read())
        if "cherrystone-ui" in read("/proc/%d/cmdline" % pid).replace("\0", " "):
            os.kill(pid, signal.SIGTERM)
            os.remove(pidf)
            sys.exit(0)
    except (OSError, ValueError):
        pass
    write(pidf, str(os.getpid()))
    atexit.register(lambda: os.path.exists(pidf) and os.remove(pidf))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))


def popup(name, width=320):
    """A little panel above the shelf at the bottom right; clicking elsewhere closes it."""
    single(name)
    win = Gtk.Window(title=name)
    win.set_wmclass("CherryQuick", "CherryQuick")
    win.set_decorated(False)
    win.set_skip_taskbar_hint(True)
    win.set_keep_above(True)
    win.set_resizable(False)
    for c in ("cherry", "pop"):
        win.get_style_context().add_class(c)
    win.connect("destroy", Gtk.main_quit)
    win.connect("focus-out-event", lambda *_: win.destroy())
    win.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and w.destroy())
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.set_border_width(18)
    box.set_size_request(width, -1)
    win.add(box)

    def place():
        win.show_all()
        w, h = win.get_size()
        d = Gdk.Display.get_default()
        g = (d.get_primary_monitor() or d.get_monitor(0)).get_geometry()
        win.move(g.x + g.width - w, g.y + g.height - h - 40)   # sits on the shelf
        win.present()
    return win, box, place


def round_button(text, icons, action, close=None):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    b = Gtk.Button()
    b.get_style_context().add_class("round")
    b.add(icon(icons, 20))
    b.set_halign(Gtk.Align.CENTER)
    b.set_tooltip_text(text)

    def go(*_):
        if close:
            close()
        action() if callable(action) else run(action)
    b.connect("clicked", go)
    box.pack_start(b, False, False, 0)
    box.pack_start(label(text, "small", xalign=0.5), False, False, 0)
    return box


def in_thread(work, done):
    """Run work() in the background, then done(result) back in the window."""
    def go():
        r = work()
        GLib.idle_add(lambda: done(r) and False)
    threading.Thread(target=go, daemon=True).start()


def mixer():
    for ctl in ("Master", "PCM"):
        if ok(["amixer", "sget", ctl]):
            return ctl
    return None


def has_backlight():
    return "backlight" in out("brightnessctl -l -c backlight")


def brightness():
    m, c = out("brightnessctl -c backlight max"), out("brightnessctl -c backlight get")
    return int(c) * 100 // int(m) if m.isdigit() and c.isdigit() and int(m) > 0 else 100


def scale_row(icons, value, minimum, on_change):
    row = Gtk.Box(spacing=10)
    row.pack_start(icon(icons, 22), False, False, 0)
    sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, minimum, 100, 5)
    sc.set_draw_value(False)
    sc.set_value(value)
    pending = {}

    def changed(s):
        if "id" in pending:
            GLib.source_remove(pending.pop("id"))

        def apply():
            pending.pop("id", None)
            on_change(int(s.get_value()))
            return False
        pending["id"] = GLib.timeout_add(120, apply)
    sc.connect("value-changed", changed)
    row.pack_start(sc, True, True, 0)
    return row


# ------------------------------------------------------------------ message

STONY = "/usr/share/cherrystone/stony/stony-%s-small.png"   # Stony, the mascot: happy, excited, sad, sleepy


def stony(mood):
    img = Gtk.Image.new_from_file(STONY % mood)
    img.set_halign(Gtk.Align.START)
    return img


def message(title, heading, text, extra=None, mood="sad"):
    win, box = window(title, heading=heading, width=380)
    face = stony(mood)
    box.pack_start(face, False, False, 0)
    box.reorder_child(face, 0)         # Stony above the heading (sad, unless it's good news)
    box.pack_start(label(text, "sub", wrap=True), False, False, 0)
    items = []
    if extra:
        items.append(button(extra[0], "plain", lambda: (run(extra[1]), win.destroy())))
    items.append(button("Close", "main", win.destroy))
    buttons(box, *items)
    win.show_all()


# --------------------------------------------------------------------- Wi-Fi

def signal_icon(strength):
    s = int(strength or 0)
    n = "excellent" if s >= 75 else "good" if s >= 50 else "ok" if s >= 25 else "weak"
    return "network-wireless-signal-%s-symbolic" % n


def wifi():
    if "wifi" not in out("nmcli -t -f type dev").split():
        return message("Wi-Fi", "No Wi-Fi adapter found",
                       "Your Wi-Fi chip may need firmware Cherrystone doesn't include. "
                       "A small USB Wi-Fi adapter usually works.",
                       ("Network settings", "nm-connection-editor"))
    single("wifi")
    win, box = window("Wi-Fi", "network-wireless", 420)
    status = label("Looking for networks...", "sub", wrap=True)
    spin = Gtk.Spinner()
    top = Gtk.Box(spacing=8)
    top.pack_start(spin, False, False, 0)
    top.pack_start(status, True, True, 0)
    box.pack_start(top, False, False, 0)
    lb = Gtk.ListBox()
    lb.get_style_context().add_class("cherry")
    lb.set_selection_mode(Gtk.SelectionMode.NONE)
    sc = Gtk.ScrolledWindow()
    sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sc.set_size_request(-1, 300)
    sc.add(lb)
    box.pack_start(sc, True, True, 0)
    state = {"busy": False}

    def networks():
        known = set(out(["nmcli", "-t", "--escape", "no", "-f", "NAME", "con", "show"]).splitlines())
        nets, seen = [], set()
        for line in out(["nmcli", "-t", "--escape", "no", "-f", "IN-USE,SIGNAL,SECURITY,SSID",
                         "dev", "wifi", "list"]).splitlines():
            parts = line.split(":", 3)
            if len(parts) < 4 or not parts[3] or parts[3] in seen:
                continue
            seen.add(parts[3])
            nets.append({"on": parts[0] == "*", "signal": parts[1], "secure": parts[2] not in ("", "--"),
                         "ssid": parts[3], "known": parts[3] in known})
        nets.sort(key=lambda n: (not n["on"], -int(n["signal"] or 0)))
        return nets

    def busy(on):
        spin.set_visible(on)
        spin.start() if on else spin.stop()

    def fill(nets, final=True):
        for r in lb.get_children():
            lb.remove(r)
        if final:
            busy(False)
        on = next((n["ssid"] for n in nets if n["on"]), None)
        status.get_style_context().remove_class("error")
        status.set_text(("Connected to %s." % on) if on else "Pick a network." if nets else
                        "Looking for networks..." if not final else "No networks found nearby.")
        if not nets:
            # Nothing (yet): thinking Stony while it looks, sleepy Stony if there's nothing
            row = Gtk.ListBoxRow()
            row.set_activatable(False)
            row.net = None
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            v.set_margin_top(40)
            p = stony("sleepy" if final else "thinking")
            p.set_halign(Gtk.Align.CENTER)
            v.pack_start(p, False, False, 0)
            v.pack_start(label("Stony couldn't find any Wi-Fi. Move closer to the router, "
                               "then press Refresh." if final else "Stony is looking around...",
                               "sub", xalign=0.5, wrap=True), False, False, 0)
            row.add(v)
            lb.add(row)
        for n in nets:
            row = Gtk.ListBoxRow()
            row.net = n
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            h = Gtk.Box(spacing=12)
            h.pack_start(icon(signal_icon(n["signal"]), 20), False, False, 0)
            names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            nm = label(n["ssid"], "bold")
            nm.set_ellipsize(Pango.EllipsizeMode.END)
            names.pack_start(nm, False, False, 0)
            names.pack_start(label("Connected" if n["on"] else "Saved" if n["known"]
                                   else "Secured" if n["secure"] else "Open", "small"), False, False, 0)
            h.pack_start(names, True, True, 0)
            if n["secure"]:
                h.pack_end(icon("changes-prevent-symbolic system-lock-screen-symbolic", 16), False, False, 0)
            v.pack_start(h, False, False, 0)
            rev = Gtk.Revealer()
            pw_row = Gtk.Box(spacing=8)
            entry = Gtk.Entry()
            entry.set_visibility(False)
            entry.set_placeholder_text("Password")
            go = button("Connect", "main")
            pw_row.pack_start(entry, True, True, 0)
            pw_row.pack_start(go, False, False, 0)
            rev.add(pw_row)
            v.pack_start(rev, False, False, 0)
            row.add(v)
            row.rev, row.entry = rev, entry
            entry.connect("activate", lambda e, n=n: connect(n, e.get_text()))
            go.connect("clicked", lambda b, n=n, e=entry: connect(n, e.get_text()))
            lb.add(row)
        lb.show_all()

    def activated(lb, row):
        n = row.net
        if n is None or state["busy"] or n["on"]:
            return
        if n["secure"] and not n["known"]:
            for r in lb.get_children():
                if r is not row:
                    r.rev.set_reveal_child(False)
            row.rev.set_reveal_child(True)
            row.entry.grab_focus()
        else:
            connect(n, None)
    lb.set_activate_on_single_click(True)
    lb.connect("row-activated", activated)

    def connect(n, pw):
        if state["busy"] or (n["secure"] and not n["known"] and not pw):
            return
        state["busy"] = True
        status.get_style_context().remove_class("error")
        status.set_text("Connecting to %s..." % n["ssid"])

        def work():
            if n["known"]:
                return ok(["nmcli", "con", "up", "id", n["ssid"]], timeout=60)
            cmd = ["nmcli", "dev", "wifi", "connect", n["ssid"]] + (["password", pw] if pw else [])
            if ok(cmd, timeout=60):
                return True
            ok(["nmcli", "con", "delete", "id", n["ssid"]])
            return False

        busy(True)

        def done(good):
            state["busy"] = False
            busy(False)
            if good:
                notify("Wi-Fi", "Connected to %s" % n["ssid"], "network-wireless")
                win.destroy()
            else:
                status.set_text("Couldn't connect to %s. Check the password and try again." % n["ssid"])
                status.get_style_context().add_class("error")
                n["known"] = False
            return False
        in_thread(work, done)

    def refresh(rescan=True):
        if rescan:
            status.set_text("Looking for networks...")
            busy(True)
            if not [r for r in lb.get_children() if getattr(r, "net", None)]:
                fill([], final=False)      # thinking Stony while it looks

        def work():
            if rescan:
                ok(["nmcli", "dev", "wifi", "rescan"], timeout=15)
                time.sleep(2)
            return networks()
        in_thread(work, fill)

    adv = button("Hidden network or advanced...", "link", lambda: run("nm-connection-editor"))
    row = buttons(box, button("Refresh", "plain", refresh), button("Done", "main", win.destroy))
    row.pack_start(adv, False, False, 0)
    win.show_all()
    fill(networks(), final=False)
    refresh()


# --------------------------------------------------------------------- power

def power():
    win, box, place = popup("power", 300)
    top = Gtk.Box(spacing=12)
    top.pack_start(picture(face_path(), 48), False, False, 0)
    names = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    names.set_valign(Gtk.Align.CENTER)
    names.pack_start(label("Guest" if GUEST else (read(CONF + "/name") or "Cherrystone"), "bold"), False, False, 0)
    names.pack_start(label("Browsing as a guest" if GUEST else "Signed in", "small"), False, False, 0)
    top.pack_start(names, True, True, 0)
    box.pack_start(top, False, False, 0)
    grid = Gtk.Grid(column_spacing=8, column_homogeneous=True)
    items = [] if GUEST else [("Lock", "system-lock-screen-symbolic", "cherrystone-lock")]
    items += [("Sign out", "system-log-out-symbolic", "openbox --exit"),
              ("Restart", "system-reboot-symbolic", "doas /sbin/reboot"),
              ("Shut down", "system-shutdown-symbolic", "doas /sbin/poweroff")]
    for i, (t, ic, cmd) in enumerate(items):
        grid.attach(round_button(t, ic, cmd, win.destroy), i, 0, 1, 1)
    box.pack_start(grid, False, False, 0)
    box.pack_start(label("Anything not saved to a USB stick or online is lost when it turns off."
                         if not (os.path.isdir("/persist") or os.path.ismount("/media/.save"))
                         else "Your stuff is kept when it turns off.",
                         "small", wrap=True), False, False, 0)
    place()


# ------------------------------------------------------------------- sliders

def slider(kind):
    if kind == "volume":
        ctl = mixer()
        if not ctl:
            return notify("Volume", "No sound card found", "audio-volume-muted")
        m = re.search(r"\[(\d+)%\]", out(["amixer", "sget", ctl]))
        value, minimum, icons, title = int(m.group(1)) if m else 50, 0, "audio-volume-high-symbolic", "Volume"
        apply = lambda v: run(["amixer", "-q", "sset", ctl, "%d%%" % v, "unmute"])
    else:
        if not has_backlight():
            return notify("Brightness", "This screen's brightness can't be changed from here", "display-brightness")
        value, minimum, icons, title = brightness(), 5, "display-brightness-symbolic", "Brightness"
        apply = lambda v: run(["doas", "/usr/bin/brightnessctl", "-c", "backlight", "-q", "set", "%d%%" % v])
    win, box, place = popup("slider", 320)
    box.pack_start(label(title, "bold"), False, False, 0)
    box.pack_start(scale_row(icons, value, minimum, apply), False, False, 0)
    place()
    return True


# ------------------------------------------------------------------ password

def password():
    win, box = window("Password", "dialog-password", 400)
    box.pack_start(label("For signing in, unlocking the screen and the rescue console. "
                         "Leave both empty to remove it (then Enter is enough).", "sub", wrap=True), False, False, 0)
    a, b = Gtk.Entry(), Gtk.Entry()
    for e, hint in ((a, "New password"), (b, "Type it again")):
        e.set_visibility(False)
        e.set_placeholder_text(hint)
        box.pack_start(e, False, False, 0)
    err = label("", "error")
    box.pack_start(err, False, False, 0)

    def save(*_):
        if a.get_text() != b.get_text():
            err.set_text("The two passwords don't match.")
            return
        r = subprocess.run(["doas", "/usr/local/sbin/cherrystone-setpass"], input=(a.get_text() + "\n").encode(),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0:
            err.set_text("Couldn't change the password.")
            return
        notify("Password", "Password set." if a.get_text() else "Password removed.", "dialog-password")
        win.destroy()
    b.connect("activate", save)
    a.connect("activate", lambda *_: b.grab_focus())
    buttons(box, button("Cancel", "plain", win.destroy), button("Save", "main", save))
    win.show_all()


# ------------------------------------------------------------- notifications

def notifications():
    single("notifications")
    win, box = window("Notifications", "preferences-system-notifications", 420)
    dnd = Gtk.Box(spacing=10)
    dnd.pack_start(label("Do not disturb", "bold"), True, True, 0)
    sw = Gtk.Switch()
    sw.set_active(out("dunstctl is-paused") == "true")
    sw.connect("notify::active", lambda s, *_: run(["dunstctl", "set-paused", "true" if s.get_active() else "false"]))
    dnd.pack_end(sw, False, False, 0)
    box.pack_start(dnd, False, False, 0)
    lst = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    sc = Gtk.ScrolledWindow()
    sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sc.set_size_request(-1, 280)
    sc.add(lst)
    box.pack_start(sc, True, True, 0)

    def fill():
        for c in lst.get_children():
            lst.remove(c)
        try:
            items = json.loads(out("dunstctl history"))["data"][0]
        except Exception:
            items = []
        items = [i for i in items if i.get("appname", {}).get("data") != "osd"]
        if not items:
            zz = stony("sleepy")
            zz.set_halign(Gtk.Align.CENTER)
            lst.pack_start(zz, False, False, 24)
            lst.pack_start(label("No notifications. Stony is taking a nap.", "sub", xalign=0.5), False, False, 0)
        for i in items:
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            card.get_style_context().add_class("card")
            card.pack_start(label(i.get("appname", {}).get("data", ""), "small"), False, False, 0)
            card.pack_start(label(i.get("summary", {}).get("data", ""), "bold", wrap=True), False, False, 0)
            body = re.sub(r"<[^>]*>", "", i.get("body", {}).get("data", ""))
            if body.strip():
                card.pack_start(label(body, "sub", wrap=True), False, False, 0)
            lst.pack_start(card, False, False, 0)
        lst.show_all()

    buttons(box, button("Clear all", "plain", lambda: (ok(["dunstctl", "history-clear"]), fill())),
            button("Close", "main", win.destroy))
    fill()
    win.show_all()


# ------------------------------------------------------------------- profile

def profile():
    win, box = window("Your name and picture", "avatar-default", 400)
    box.pack_start(label("Shown on the sign-in screen, the lock screen and the shelf.", "sub", wrap=True),
                   False, False, 0)
    state = {"pic": None}
    row = Gtk.Box(spacing=16)
    img = Gtk.Image()
    img.set_from_pixbuf(picture(face_path(), 96).get_pixbuf() or None)
    holder = Gtk.Box()
    holder.pack_start(img, False, False, 0)
    row.pack_start(holder, False, False, 0)
    right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    right.set_valign(Gtk.Align.CENTER)
    name = Gtk.Entry()
    name.set_text(read(CONF + "/name") or "Cherrystone")
    name.set_max_length(40)
    right.pack_start(name, False, False, 0)

    def choose():
        f = pick_picture(win)
        if f:
            try:
                img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(f, 96, 96, True))
                state["pic"] = f
            except GLib.Error:
                notify("Your picture", "That file isn't a picture Cherrystone can read.")
    right.pack_start(button("Change picture...", "plain", choose), False, False, 0)
    row.pack_start(right, True, True, 0)
    box.pack_start(row, False, False, 0)

    def save(*_):
        write(CONF + "/name", name.get_text().strip()[:40] + "\n")
        if state["pic"]:
            try:
                p = GdkPixbuf.Pixbuf.new_from_file_at_scale(state["pic"], 112, 112, True)
                p.savev(os.path.join(HOME, ".face"), "png", [], [])
            except GLib.Error:
                pass
        run("cherrystone-shelf")
        notify("Your name and picture", "Saved.")
        win.destroy()
    name.connect("activate", save)
    buttons(box, button("Cancel", "plain", win.destroy), button("Save", "main", save))
    win.show_all()


def pick_picture(parent):
    d = Gtk.FileChooserDialog(title="Choose a picture", transient_for=parent, action=Gtk.FileChooserAction.OPEN)
    d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.OK)
    f = Gtk.FileFilter()
    f.set_name("Pictures")
    for p in ("*.png", "*.jpg", "*.jpeg", "*.PNG", "*.JPG", "*.JPEG", "*.webp", "*.gif"):
        f.add_pattern(p)
    d.add_filter(f)
    pics = os.path.join(HOME, "Pictures")
    if os.path.isdir(pics):
        d.set_current_folder(pics)
    prev = Gtk.Image()
    d.set_preview_widget(prev)

    def update(chooser):
        fn = chooser.get_preview_filename()
        try:
            prev.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(fn, 180, 180, True))
            chooser.set_preview_widget_active(True)
        except Exception:
            chooser.set_preview_widget_active(False)
    d.connect("update-preview", update)
    r = d.run()
    fn = d.get_filename() if r == Gtk.ResponseType.OK else None
    d.destroy()
    return fn


# ----------------------------------------------------------------- wallpaper

def wallpaper():
    W = "/usr/share/backgrounds/cherrystone"
    # Personalize: how Cherrystone looks (dark mode, wallpaper)
    win, box = window("Personalize", "preferences-desktop-wallpaper", 460)
    row = Gtk.Box(spacing=12)
    t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    t.pack_start(label("Dark mode", "bold"), False, False, 0)
    t.pack_start(label("Dark windows, menus and home page. Apps that are open change when you "
                       "open them again.", "small", wrap=True), False, False, 0)
    row.pack_start(t, True, True, 0)
    dk = Gtk.Switch()
    dk.set_valign(Gtk.Align.CENTER)
    dk.set_active(read(CONF + "/theme", "light").strip() == "dark")
    dk.connect("notify::active", lambda s, *_: run(["cherrystone-theme", "dark" if s.get_active() else "light"]))
    row.pack_end(dk, False, False, 0)
    box.pack_start(row, False, False, 0)
    box.pack_start(label("Wallpaper", "bold"), False, False, 0)
    box.pack_start(label("Shows behind the sign-in screen, the lock screen and the home page.", "sub", wrap=True),
                   False, False, 0)
    fb = Gtk.FlowBox()
    fb.set_max_children_per_line(3)
    fb.set_min_children_per_line(3)
    fb.set_selection_mode(Gtk.SelectionMode.SINGLE)
    fb.set_homogeneous(True)
    current = read(CONF + "/wallpaper")
    choices = []
    for f in sorted(os.listdir(W)) if os.path.isdir(W) else []:
        if f.endswith(".png") and not f.startswith("."):
            n = f[:-4]
            choices.append((n.replace("-", " ").capitalize(), os.path.join(W, f), os.path.join(W, "." + n + "-thumb.png")))
    choices.append(("Plain", "none", None))
    changed = {"yes": False}
    for name, path, thumb in choices:
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        try:
            src = thumb if thumb and os.path.isfile(thumb) else path
            if path == "none":
                pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, 120, 68)
                pb.fill(0xf1f3f4ff)
            else:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(src, 120, 68, False)
            v.pack_start(Gtk.Image.new_from_pixbuf(pb), False, False, 0)
        except GLib.Error:
            v.pack_start(icon("image-x-generic", 48), False, False, 0)
        v.pack_start(label(name, "small", xalign=0.5), False, False, 0)
        child = Gtk.FlowBoxChild()
        child.add(v)
        child.path = path
        fb.add(child)
        if path == current or (path == "none" and not current):
            fb.select_child(child)

    def use(path):
        if path == "none":
            for p in (CONF + "/wallpaper", os.path.join(HOME, ".fehbg")):
                if os.path.exists(p):
                    os.remove(p)
            run(["feh", "--no-fehbg", "--bg-fill", "/usr/share/backgrounds/cherrystone-plain.png"])
        else:
            write(CONF + "/wallpaper", path + "\n")
            run(["feh", "--bg-fill", path])
        changed["yes"] = True
    fb.connect("child-activated", lambda f, c: use(c.path))
    box.pack_start(fb, False, False, 0)

    def own():
        f = pick_picture(win)
        if f:
            use(f)
            fb.unselect_all()

    def close(*_):
        if changed["yes"]:
            run("cherrystone-home")
            notify("Wallpaper", "Changed. Reload the home page to see it there.")
        win.destroy()
    win.connect("delete-event", lambda *_: (close(), True)[1])
    row = buttons(box, button("Done", "main", close))
    row.pack_start(button("Your own picture...", "plain", own), False, False, 0)
    win.show_all()


# ------------------------------------------------------------------- display

def display():
    win, box = window("Display", "preferences-desktop-display", 420)
    if has_backlight():
        box.pack_start(label("Brightness", "bold"), False, False, 0)
        box.pack_start(scale_row("display-brightness-symbolic", brightness(), 5,
                                 lambda v: run(["doas", "/usr/bin/brightnessctl", "-c", "backlight", "-q", "set", "%d%%" % v])),
                       False, False, 0)
    # Resolution: every mode the screen reports (with no graphics driver
    # that's often just a few, but it's still a choice)
    outs = [l.split()[0] for l in out("xrandr --query").splitlines() if " connected" in l]
    if outs:
        main = outs[0]
        modes, cur_mode, seen = [], None, set()
        grab = False
        for l in out("xrandr --query").splitlines():
            if not l.startswith(" "):
                grab = l.split()[0] == main
                continue
            if grab:
                m = l.split()[0]
                if "x" in m and m not in seen:
                    seen.add(m)
                    modes.append(m)
                    if "*" in l:
                        cur_mode = m
        if modes:
            box.pack_start(label("Resolution", "bold"), False, False, 0)
            rc = Gtk.ComboBoxText()
            for m in modes:
                rc.append(m, m.replace("x", " × ") + ("  (recommended)" if m == modes[0] else ""))
            rc.set_active_id(cur_mode or modes[0])
            state = {"old": cur_mode or modes[0], "busy": False}

            def set_res(c):
                m = c.get_active_id()
                if state["busy"] or not m or m == state["old"]:
                    return
                run(["xrandr", "--output", main, "--mode", m])
                d = Gtk.MessageDialog(transient_for=win, modal=True, message_type=Gtk.MessageType.QUESTION,
                                      buttons=Gtk.ButtonsType.NONE, text="Keep this resolution?")
                d.add_buttons("Go back", Gtk.ResponseType.CANCEL, "Keep", Gtk.ResponseType.OK)
                left = {"n": 15}
                d.format_secondary_text("Going back in %d seconds." % left["n"])

                def tick():
                    left["n"] -= 1
                    if left["n"] <= 0:
                        d.response(Gtk.ResponseType.CANCEL)
                        return False
                    d.format_secondary_text("Going back in %d seconds." % left["n"])
                    return True
                tid = GLib.timeout_add_seconds(1, tick)
                r = d.run()
                GLib.source_remove(tid) if left["n"] > 0 else None
                d.destroy()
                if r == Gtk.ResponseType.OK:
                    state["old"] = m
                    write(CONF + "/resolution", "%s %s" % (main, m) + chr(10))
                    run("cherrystone-home")
                else:
                    run(["xrandr", "--output", main, "--mode", state["old"]])
                    state["busy"] = True
                    c.set_active_id(state["old"])
                    state["busy"] = False
            rc.connect("changed", set_res)
            box.pack_start(rc, False, False, 0)

    # Night light: warmer colours, easier on the eyes at night
    row = Gtk.Box(spacing=12)
    t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    t.pack_start(label("Night light", "bold"), False, False, 0)
    t.pack_start(label("Warmer colours, less blue. Easier on your eyes in the evening.", "small", wrap=True),
                 False, False, 0)
    row.pack_start(t, True, True, 0)
    nl = Gtk.Switch()
    nl.set_valign(Gtk.Align.CENTER)
    nl.set_active(read(CONF + "/nightlight", "off").strip() == "on")

    def night(s, *_):
        on = s.get_active()
        write(CONF + "/nightlight", ("on" if on else "off") + chr(10))
        for o in [l.split()[0] for l in out("xrandr --query").splitlines() if " connected" in l]:
            run(["xrandr", "--output", o, "--gamma", "1:0.82:0.64" if on else "1:1:1"])
    nl.connect("notify::active", night)
    row.pack_end(nl, False, False, 0)
    box.pack_start(row, False, False, 0)

    # Size: makes text and controls bigger or smaller, 80% to 150%
    box.pack_start(label("Size", "bold"), False, False, 0)
    try:
        cur = max(80, min(150, int(read(CONF + "/textsize", "100").strip())))
    except ValueError:
        cur = 100
    srow = Gtk.Box(spacing=10)
    sval = label("%d%%" % cur, "small")
    sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 80, 150, 5)
    sc.set_draw_value(False)
    sc.set_value(cur)
    for mk in (80, 100, 125, 150):
        sc.add_mark(mk, Gtk.PositionType.BOTTOM, None)
    pend = {}

    def size_changed(s):
        v = int(round(s.get_value() / 5) * 5)
        sval.set_text("%d%%" % v)
        if "id" in pend:
            GLib.source_remove(pend.pop("id"))

        def save():
            pend.pop("id", None)
            write(CONF + "/textsize", "%d" % v + chr(10))
            notify("Size", "Sign out and back in to see the new size.", "preferences-desktop-display")
            return False
        pend["id"] = GLib.timeout_add(900, save)
    sc.connect("value-changed", size_changed)
    srow.pack_start(sc, True, True, 0)
    srow.pack_start(sval, False, False, 0)
    box.pack_start(srow, False, False, 0)

    row = Gtk.Box(spacing=12)
    t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    t.pack_start(label("Animations", "bold"), False, False, 0)
    t.pack_start(label("Windows and menus fade and slide in. Off on old computers to keep "
                       "games and videos smooth.", "small", wrap=True),
                 False, False, 0)
    row.pack_start(t, True, True, 0)
    sw = Gtk.Switch()
    sw.set_valign(Gtk.Align.CENTER)
    sw.set_active(ok(["pgrep", "-x", "picom"]))     # on right now?

    def animations(s, *_):
        if os.path.exists(CONF + "/no-animations"):
            os.remove(CONF + "/no-animations")      # the old way of saying off
        if s.get_active():
            write(CONF + "/animations", "on\n")
            run("pgrep -x picom || picom -b")
        else:
            write(CONF + "/animations", "off\n")
            run(["pkill", "-x", "picom"])
    sw.connect("notify::active", animations)
    row.pack_end(sw, False, False, 0)
    box.pack_start(row, False, False, 0)


    outs = [l.split()[0] for l in out("xrandr --query").splitlines() if " connected" in l]
    if len(outs) > 1:
        main, other = outs[0], outs[1]
        box.pack_start(label("Second screen", "bold"), False, False, 0)
        cb = Gtk.ComboBoxText()
        for t in ("Show the same thing", "Extend to the right", "Off"):
            cb.append_text(t)
        cb.set_active(0)
        acts = [["--auto", "--same-as", main], ["--auto", "--right-of", main], ["--off"]]
        cb.connect("changed", lambda c: run(["xrandr", "--output", other] + acts[c.get_active()]))
        box.pack_start(cb, False, False, 0)
    buttons(box, button("Done", "main", win.destroy))
    win.show_all()


# ------------------------------------------------------------------ touchpad

def touchpad():
    win, box = window("Touchpad", "input-touchpad", 400)
    conf = CONF + "/touchpad"
    vals = {"tap": "TRUE", "natural": "FALSE"}
    for line in read(conf).splitlines():
        k, _, v = line.partition("=")
        if k in vals:
            vals[k] = v.strip()

    def setting(key, title, sub):
        row = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label(title, "bold"), False, False, 0)
        if sub:
            t.pack_start(label(sub, "small", wrap=True), False, False, 0)
        row.pack_start(t, True, True, 0)
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        sw.set_active(vals[key] == "TRUE")

        def flip(s, *_):
            vals[key] = "TRUE" if s.get_active() else "FALSE"
            write(conf, "tap=%s\nnatural=%s\n" % (vals["tap"], vals["natural"]))
            run(["cherrystone-touchpad", "apply"])
        sw.connect("notify::active", flip)
        row.pack_end(sw, False, False, 0)
        box.pack_start(row, False, False, 0)
    setting("tap", "Tap to click", "A light tap clicks, no need to press down.")
    setting("natural", "Natural scrolling", "The page follows your fingers, like on a phone.")
    buttons(box, button("Done", "main", win.destroy))
    win.show_all()


# --------------------------------------------------------------------- about

def about():
    win, box = window("About Cherrystone", "cherrystone", 440, heading="Cherrystone")
    box.get_children()[0].get_style_context().add_class("big")
    top = Gtk.Box(spacing=16)
    top.pack_start(picture("/usr/share/icons/hicolor/128x128/apps/cherrystone.png", 80), False, False, 0)
    words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    words.set_valign(Gtk.Align.CENTER)
    words.pack_start(label("small. fast. yours.", "bold"), False, False, 0)
    words.pack_start(label("Turns old laptops into simple, safe computers for the web.", "sub", wrap=True),
                     False, False, 0)
    top.pack_start(words, True, True, 0)
    box.pack_start(top, False, False, 0)
    cpu = next((l.split(":", 1)[1].strip() for l in read("/proc/cpuinfo").splitlines()
                if l.startswith("model name")), "unknown processor")
    cpu = re.sub(r"\s+", " ", cpu.replace("(R)", "").replace("(TM)", "").replace(" CPU", ""))
    mem = next((int(l.split()[1]) // 1024 for l in read("/proc/meminfo").splitlines()
                if l.startswith("MemTotal:")), 0)
    started = read("/tmp/cherrystone-started")
    ver = read("/etc/cherrystone-version")
    try:
        ver = time.strftime("%-d %B %Y", time.strptime(ver, "%Y%m%d"))
    except ValueError:
        ver = ver or "unknown"
    rows = [("Version", ver),
            ("This computer", "%s, %d MB memory (%s)" % (cpu, mem, "64-bit" if os.uname().machine == "x86_64" else "32-bit")),
            ("Browser", "Badwolf (WebKit), with ad blocking"),
            ("Based on", "Alpine Linux " + read("/etc/alpine-release"))]
    if started:
        rows.append(("Started in", started + " seconds"))
    g = Gtk.Grid(column_spacing=14, row_spacing=6)
    for i, (k, v) in enumerate(rows):
        g.attach(label(k, "sub"), 0, i, 1, 1)
        g.attach(label(v, wrap=True), 1, i, 1, 1)
    box.pack_start(g, False, False, 0)
    buttons(box, button("Check for updates", "plain", lambda: run("cherrystone-update")),
            button("Close", "main", win.destroy))
    win.show_all()


# ----------------------------------------------------------------- shortcuts

SHORTCUTS = [
    ("Windows key", "Apps and search"),
    ("Ctrl+T", "New tab (the home page)"),
    ("Ctrl+W", "Close tab"),
    ("Ctrl+Tab", "Next tab (Ctrl+Shift+Tab: previous)"),
    ("Ctrl+L", "Type a web address"),
    ("Ctrl+H", "History"),
    ("Ctrl+D", "Add this page to the home page"),
    ("F5", "Reload the page"),
    ("Alt+Left", "Back (Alt+Right: forward)"),
    ("Ctrl+F", "Find on the page"),
    ("Ctrl+scroll", "Bigger or smaller page (Ctrl+0: normal)"),
    ("Alt+Tab", "Switch windows"),
    ("Alt+F4", "Close the window"),
    ("Ctrl+Alt+L", "Lock the screen"),
    ("Print Screen", "Screenshot (Shift: part of the screen)"),
    ("F11", "Full screen"),
    ("Ctrl+Alt+T", "Terminal (with Advanced tools on)"),
    ("Ctrl+Alt+/", "This list"),
]


CHROMEBOOK_SHORTCUTS = [
    ("Search", "Apps and search (like the Windows key)"),
    ("Search+Up", "Page Up (Search+Down: Page Down)"),
    ("Search+Left", "Home (Search+Right: End)"),
    ("Search+Backspace", "Delete"),
    ("Search+top row", "F1 to F10"),
]


def shortcuts():
    single("shortcuts")
    win, box = window("Keyboard shortcuts", "preferences-desktop-keyboard-shortcuts", 480)
    g = Gtk.Grid(column_spacing=16, row_spacing=8)
    items = SHORTCUTS
    if read("/sys/class/dmi/id/sys_vendor").strip() == "Google":
        items = CHROMEBOOK_SHORTCUTS + SHORTCUTS[1:]
    for i, (k, v) in enumerate(items):
        kl = label(k, "kbd", xalign=0.5)
        kl.set_halign(Gtk.Align.START)
        g.attach(kl, 0, i, 1, 1)
        g.attach(label(v), 1, i, 1, 1)
    sc = Gtk.ScrolledWindow()
    sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sc.set_size_request(-1, min(420, Gdk.Screen.get_default().get_height() - 200))
    sc.add(g)
    box.pack_start(sc, True, True, 0)
    buttons(box, button("Close", "main", win.destroy))
    win.show_all()


# --------------------------------------------------------------------- tiles

COLOURS = ["#3b6fd6", "#d81e3c", "#2e9e5b", "#e0a020", "#8a3bd6", "#5a5a64", "#e06a20", "#1e9ec8"]


def tiles():
    mode = out("cherrystone-mode") or "full"
    path = os.path.join(CONF, "tiles-" + mode)
    if not os.path.isfile(path):
        out("cherrystone-home")
    win, box = window("Home page tiles", "user-home", 460)
    box.pack_start(label("The big buttons on the browser's home page. Tip: press Ctrl+D in the browser "
                         "to add the page you're on.", "sub", wrap=True), False, False, 0)
    lb = Gtk.ListBox()
    lb.get_style_context().add_class("cherry")
    lb.set_selection_mode(Gtk.SelectionMode.NONE)
    sc = Gtk.ScrolledWindow()
    sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sc.set_size_request(-1, 240)
    sc.add(lb)
    box.pack_start(sc, True, True, 0)
    state = {"changed": False}

    def load():
        return [l.split("|") for l in read(path).splitlines() if l.count("|") >= 3]

    def save(items):
        write(path, "".join("|".join(i) + "\n" for i in items))
        state["changed"] = True
        fill()

    def fill():
        for r in lb.get_children():
            lb.remove(r)
        items = load()
        for idx, t in enumerate(items):
            h = Gtk.Box(spacing=12)
            badge = Gtk.Label()
            badge.set_markup('<span background="%s" foreground="#ffffff" weight="bold">  %s  </span>'
                             % (GLib.markup_escape_text(t[2]), GLib.markup_escape_text((t[0][:1] or "?").upper())))
            h.pack_start(badge, False, False, 0)
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            v.pack_start(label(t[0], "bold"), False, False, 0)
            u = label(t[3], "small")
            u.set_ellipsize(Pango.EllipsizeMode.END)
            u.set_max_width_chars(40)
            v.pack_start(u, False, False, 0)
            h.pack_start(v, True, True, 0)
            rm = Gtk.Button()
            rm.get_style_context().add_class("icon")
            rm.add(icon("edit-delete-symbolic list-remove-symbolic", 16))
            rm.set_tooltip_text("Remove")
            rm.connect("clicked", lambda b, idx=idx: save([x for j, x in enumerate(load()) if j != idx]))
            h.pack_end(rm, False, False, 0)
            lb.add(h)
        lb.show_all()

    add = Gtk.Box(spacing=8)
    name, url = Gtk.Entry(), Gtk.Entry()
    name.set_placeholder_text("Name")
    name.set_width_chars(12)
    url.set_placeholder_text("Address, like example.com")
    add.pack_start(name, False, False, 0)
    add.pack_start(url, True, True, 0)
    err = label("", "error")

    def do_add(*_):
        n = re.sub(r'[<>"&|]', "", name.get_text()).strip()[:24]
        u = re.sub(r'[\s<>"|]', "", url.get_text())
        if u and not re.match(r"https?://", u):
            u = "https://" + u
        if not n or not u:
            err.set_text("A tile needs a name and an address.")
            return
        err.set_text("")
        items = load()
        items.append([n, n[0].upper(), COLOURS[len(items) % 8], u])
        save(items)
        name.set_text("")
        url.set_text("")
        name.grab_focus()
    url.connect("activate", do_add)
    add.pack_start(button("Add", "main", do_add), False, False, 0)
    box.pack_start(add, False, False, 0)
    box.pack_start(err, False, False, 0)

    def original():
        shutil.copy("/usr/share/cherrystone/tiles-" + mode, path)
        state["changed"] = True
        fill()

    def close(*_):
        if state["changed"]:
            run("cherrystone-home")
            notify("Home page tiles", "Saved. Reload the home page to see them.")
        win.destroy()
    win.connect("delete-event", lambda *_: (close(), True)[1])
    row = buttons(box, button("Done", "main", close))
    row.pack_start(button("Back to the original tiles", "link", original), False, False, 0)
    fill()
    win.show_all()


# --------------------------------------------------------------------- install

def disks():
    """Whole disks of at least 2 GB, except the one Cherrystone runs from."""
    boot = ""
    for line in read("/proc/mounts").splitlines():
        f = line.split()
        if len(f) > 1 and f[1] == "/media/.boot":
            boot = f[0]
    found = []
    for line in out(["lsblk", "-dbpno", "NAME,SIZE,TYPE,MODEL"]).splitlines():
        f = line.split(None, 3)
        if len(f) < 3 or f[2] != "disk" or not f[1].isdigit() or int(f[1]) < 2000000000:
            continue
        if boot.startswith(f[0]) or f[0].startswith(("/dev/zram", "/dev/loop", "/dev/sr", "/dev/fd")):
            continue
        found.append({"dev": f[0], "size": "%d GB" % (int(f[1]) // 1000000000),
                      "model": (f[3].strip() if len(f) > 3 else "") or "Disk"})
    return found


def install():
    # One installer at a time (a second click on the shelf button does nothing)
    pidf = "/tmp/cherrystone-install.%d" % os.getuid()
    try:
        if "cherrystone-ui" in read("/proc/%d/cmdline" % int(read(pidf))):
            return True
    except ValueError:
        pass
    write(pidf, str(os.getpid()))
    atexit.register(lambda: os.path.exists(pidf) and os.remove(pidf))

    found = disks()
    if not found:
        return message("Install Cherrystone", "No disk to install on",
                       "Cherrystone couldn't find a disk other than the USB stick it's running from.")

    win, box = window("Install Cherrystone", "cherrystone", 460)
    title = box.get_children()[0]
    stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=200)
    stack.set_vhomogeneous(False)      # each page only as tall as it needs
    box.pack_start(stack, True, True, 0)
    state = {"disk": found[0], "running": False, "target": 0.0, "creep": 0.0}

    def page(mood, *widgets):
        p = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        p.pack_start(stony(mood), False, False, 0)
        for w in widgets:
            p.pack_start(w, False, False, 0)
        return p

    def bar(*items):
        row = Gtk.Box(spacing=8)
        for b in reversed(items):
            row.pack_end(b, False, False, 0)
        return row

    def show(name, heading):
        title.set_text(heading)
        stack.set_visible_child_name(name)
        win.resize(1, 1)                   # shrink to fit the new page

    # 1. pick a disk
    lb = Gtk.ListBox()
    lb.get_style_context().add_class("cherry")
    for d in found:
        row = Gtk.ListBoxRow()
        row.disk = d
        h = Gtk.Box(spacing=12)
        h.pack_start(icon("drive-harddisk", 32), False, False, 0)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label(d["model"], "bold"), False, False, 0)
        t.pack_start(label("%s  ·  %s" % (d["size"], d["dev"]), "small"), False, False, 0)
        h.pack_start(t, True, True, 0)
        row.add(h)
        lb.add(row)
    lb.select_row(lb.get_row_at_index(0))
    lb.connect("row-selected", lambda l, r: r and state.update(disk=r.disk))
    stack.add_named(page("excited",
                         label("Cherrystone will start faster and keep your settings and files, "
                               "even after you turn the computer off.", "sub", wrap=True),
                         label("Where should it go?", "bold"), lb,
                         bar(button("Cancel", "plain", win.destroy),
                             button("Next", "main", lambda: confirm()))), "pick")

    # 2. the warning
    warn = label("", "bold", wrap=True)
    stack.add_named(page("sad", warn,
                         label("That includes Windows or any other system, and every file on it. "
                               "This can't be undone.", "sub", wrap=True),
                         bar(button("Back", "plain", lambda: show("pick", "Install Cherrystone")),
                             button("Erase and install", "main", lambda: start()))), "confirm")

    def confirm():
        d = state["disk"]
        warn.set_text("Everything on %s (%s) will be erased." % (d["model"], d["size"]))
        warn.get_style_context().add_class("error")
        show("confirm", "Are you sure?")

    # 3. installing
    step = label("Getting ready...", "bold", wrap=True)
    prog = Gtk.ProgressBar()
    stack.add_named(page("happy", step, prog,
                         label("Keep the computer plugged in and leave the USB stick in.",
                               "sub", wrap=True)), "run")

    # 4. finished / went wrong
    stack.add_named(page("cool",
                         label("Shut down, take out the USB stick, and turn the computer back on. "
                               "Cherrystone will start from the disk.", "sub", wrap=True),
                         bar(button("Later", "plain", win.destroy),
                             button("Shut down now", "main", lambda: run(["doas", "/sbin/poweroff"])))), "done")
    err = label("", "sub", wrap=True)
    stack.add_named(page("sad", err,
                         label("Nothing on the USB stick was changed. You can try again.", "sub", wrap=True),
                         bar(button("Close", "main", win.destroy))), "error")

    # The bar glides to each step, and creeps along during the long copy so
    # it never looks stuck
    def tick():
        cur = prog.get_fraction()
        goal = max(state["target"], min(state["target"] + state["creep"], state["target"] + 0.55))
        if state["running"] and state["target"] >= 0.25:
            state["creep"] += 0.0004
        prog.set_fraction(cur + (goal - cur) * 0.15 if goal > cur else cur)
        return state["running"]

    def start():
        state["running"] = True
        show("run", "Installing Cherrystone")
        win.set_deletable(False)
        GLib.timeout_add(50, tick)
        proc = subprocess.Popen(["doas", "/usr/local/sbin/cherrystone-install", state["disk"]["dev"]],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def update(line):
            if line.startswith("#"):
                if not line.startswith("# Error"):
                    step.set_text(line[1:].strip() + "...")
            elif line.strip().isdigit():
                state["target"], state["creep"] = int(line) / 100.0, 0.0
            return False

        def work():
            for line in proc.stdout:
                GLib.idle_add(update, line.rstrip("\n"))
            errors = [l[7:].strip() for l in proc.stderr.read().splitlines() if l.startswith("ERROR: ")]
            return proc.wait() == 0 and not errors, errors

        def done(result):
            good, errors = result
            state["running"] = False
            win.set_deletable(True)
            if good:
                prog.set_fraction(1.0)
                show("done", "Cherrystone is installed")
            else:
                err.set_text("It stopped with: %s." % (errors[0] if errors else "an unknown problem"))
                show("error", "The install didn't finish")
            return False
        in_thread(work, done)

    def closing(*_):
        return state["running"]     # can't close it halfway through
    win.connect("delete-event", closing)
    win.connect("key-press-event", lambda w, e: state["running"])   # Esc does nothing while running
    win.show_all()
    show("pick", "Install Cherrystone")


# ------------------------------------------------------------ shared: flows

def flow(title, icon_name="cherrystone", width=460):
    """A window whose pages cross-fade (pick, confirm, working, done...).
    Returns win, add(name, mood, *widgets), show(name, heading)."""
    win, box = window(title, icon_name, width)
    heading = box.get_children()[0]
    stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=200)
    stack.set_vhomogeneous(False)
    box.pack_start(stack, True, True, 0)

    def add(name, mood, *widgets):
        p = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        if mood:
            p.pack_start(stony(mood), False, False, 0)
        for w in widgets:
            p.pack_start(w, False, False, 0)
        stack.add_named(p, name)
        return p

    def show(name, text):
        heading.set_text(text)
        stack.set_visible_child_name(name)
        win.resize(1, 1)
    return win, add, show


def bar(*items):
    """A row of buttons, right-aligned (for inside a flow page)."""
    row = Gtk.Box(spacing=8)
    for b in reversed(items):
        row.pack_end(b, False, False, 0)
    return row


def drive_list(drives, on_pick):
    """A list of drives (dicts with dev, size, name); the first is picked."""
    lb = Gtk.ListBox()
    lb.get_style_context().add_class("cherry")
    for d in drives:
        row = Gtk.ListBoxRow()
        row.drive = d
        h = Gtk.Box(spacing=12)
        h.pack_start(icon(d.get("icon", "drive-removable-media drive-harddisk"), 32), False, False, 0)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label(d["name"], "bold"), False, False, 0)
        t.pack_start(label("%s  ·  %s" % (d["size"], d["dev"]), "small"), False, False, 0)
        h.pack_start(t, True, True, 0)
        row.add(h)
        lb.add(row)
    if drives:
        lb.select_row(lb.get_row_at_index(0))
        on_pick(drives[0])
    lb.connect("row-selected", lambda l, r: r and on_pick(r.drive))
    return lb


def boot_device():
    for line in read("/proc/mounts").splitlines():
        f = line.split()
        if len(f) > 1 and f[1] == "/media/.boot":
            return f[0]
    return ""


# ------------------------------------------------------------ Save my stuff

def save():
    if " /media/.save " in read("/proc/mounts") or os.path.isdir("/media/.boot/persist"):
        return message("Save my stuff", "Your stuff is being saved",
                       "Settings, Wi-Fi passwords and files are kept when you restart.", mood="happy")
    boot = boot_device()
    drives = []
    for line in out(["lsblk", "-lpno", "NAME,SIZE,TYPE,LABEL"]).splitlines():
        f = line.split(None, 3)
        if len(f) < 3 or f[2] not in ("disk", "part") or (boot and boot.startswith(f[0])):
            continue
        if f[0].startswith(("/dev/zram", "/dev/loop", "/dev/sr", "/dev/fd")):
            continue
        drives.append({"dev": f[0], "size": f[1], "name": (f[3].strip() if len(f) > 3 else "") or "USB stick or card"})
    if not drives:
        return message("Save my stuff", "Plug in a second USB stick or SD card",
                       "Cherrystone keeps your settings and files on it. (Or install Cherrystone "
                       "on this computer, which keeps everything by itself.)", mood="thinking")

    win, add, show = flow("Save my stuff", "drive-removable-media")
    state = {"drive": None, "busy": False}
    lb = drive_list(drives, lambda d: state.update(drive=d))
    add("pick", "happy",
        label("From a USB stick, Cherrystone forgets everything when it turns off. Pick another "
              "stick or card to keep your settings and files on.", "sub", wrap=True),
        lb, bar(button("Cancel", "plain", win.destroy), button("Next", "main", lambda: confirm())))

    warn = label("", "bold", wrap=True)
    add("confirm", "sad", warn,
        label("It will be used only for Cherrystone from now on.", "sub", wrap=True),
        bar(button("Back", "plain", lambda: show("pick", "Save my stuff")),
            button("Erase and use it", "main", lambda: start())))

    def confirm():
        d = state["drive"]
        warn.set_text("Everything on %s (%s) will be erased." % (d["name"], d["size"]))
        warn.get_style_context().add_class("error")
        show("confirm", "Are you sure?")

    spin = Gtk.Spinner()
    add("run", "thinking", spin, label("Getting it ready. Leave it plugged in.", "sub", wrap=True))
    add("done", "excited",
        label("Keep it plugged in. From the next restart your settings and files are kept.", "sub", wrap=True),
        bar(button("Later", "plain", win.destroy),
            button("Restart now", "main", lambda: run(["doas", "/sbin/reboot"]))))
    err = label("", "sub", wrap=True)
    add("error", "sad", err, bar(button("Close", "main", win.destroy)))

    def start():
        state["busy"] = True
        win.set_deletable(False)
        spin.start()
        show("run", "Setting it up...")

        def work():
            p = subprocess.run(["doas", "/usr/local/sbin/cherrystone-make-save", state["drive"]["dev"]],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            errs = [l[7:] for l in p.stderr.splitlines() if l.startswith("ERROR: ")]
            return p.returncode == 0, errs

        def done(r):
            good, errs = r
            state["busy"] = False
            win.set_deletable(True)
            spin.stop()
            if good:
                show("done", "Done")
            else:
                err.set_text("It stopped with: %s." % (errs[0] if errs else "an unknown problem"))
                show("error", "That didn't work")
            return False
        in_thread(work, done)

    win.connect("delete-event", lambda *_: state["busy"])
    win.show_all()
    show("pick", "Save my stuff")


# ------------------------------------------------------------------- Reset

def reset():
    if not os.path.isdir("/media/.save/upper") and not os.path.isdir("/media/.boot/persist/upper"):
        return message("Reset Cherrystone", "Nothing to reset",
                       "Nothing is saved on this computer: Cherrystone already starts fresh every time.",
                       mood="happy")
    win, add, show = flow("Reset Cherrystone", "edit-clear-all")

    def go():
        if not ok(["doas", "/usr/local/sbin/cherrystone-reset-on-restart"]):
            notify("Reset Cherrystone", "Couldn't start the reset.", "dialog-error")
    add("ask", "sad",
        label("Puts Cherrystone back the way it was new: your settings, Wi-Fi passwords, your "
              "password and the files kept in Cherrystone are erased.", "sub", wrap=True),
        label("It restarts first, and asks for your password and to confirm before anything "
              "is erased.", "sub", wrap=True),
        bar(button("Cancel", "plain", win.destroy), button("Restart and reset", "main", go)))
    win.show_all()
    show("ask", "Reset Cherrystone")


# -------------------------------------------------------------- Linux apps

def linuxapps():
    win, box = window("Advanced tools", "utilities-terminal", 420)
    f = CONF + "/linux-apps"
    box.pack_start(label("For people who know Linux: a Terminal and a Task Manager in the "
                         "launcher, Ctrl+Alt+T, and the whole system (and hidden files) in Files. "
                         "Most people never need these.", "sub", wrap=True), False, False, 0)
    row = Gtk.Box(spacing=12)
    row.pack_start(label("Show advanced tools", "bold"), True, True, 0)
    sw = Gtk.Switch()
    sw.set_valign(Gtk.Align.CENTER)
    sw.set_active(os.path.exists(f))

    def flip(s, *_):
        on = s.get_active()
        if on:
            write(f, "")
        elif os.path.exists(f):
            os.remove(f)
        # Files: the whole system (/, /var, /etc...) and hidden files only with this on
        v = "1" if on else "0"
        run("sed -i 's/^places_root=.*/places_root=%s/' ~/.config/libfm/libfm.conf; "
            "sed -i 's/^show_hidden=.*/show_hidden=%s/' ~/.config/pcmanfm/default/pcmanfm.conf; "
            "pkill -x pcmanfm; sleep 1; pcmanfm --daemon-mode" % (v, v))
    sw.connect("notify::active", flip)
    row.pack_end(sw, False, False, 0)
    box.pack_start(row, False, False, 0)
    buttons(box, button("Done", "main", win.destroy))
    win.show_all()


# ---------------------------------------------------------------- Recovery
# Boot menu > Recovery: repair an installed Cherrystone, get your files off
# it, or reset it. The root side (cherrystone-recover) does the work and
# checks the password before touching anything.

def recovery():
    R = ["doas", "/usr/local/sbin/cherrystone-recover"]
    win, add, show = flow("Cherrystone Recovery", "cherrystone", 560)
    win.set_deletable(False)                      # it's the only thing running
    state = {"dev": None, "pw": "", "after": None, "busy": False}

    # 1. the list of things to do
    lb = Gtk.ListBox()
    lb.get_style_context().add_class("cherry")
    lb.set_activate_on_single_click(True)
    intro = label("", "sub", wrap=True)

    def item(icon_name, text, sub, action, dev=None):
        row = Gtk.ListBoxRow()
        row.action, row.dev = action, dev
        h = Gtk.Box(spacing=12)
        h.pack_start(icon(icon_name, 28), False, False, 0)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label(text, "bold"), False, False, 0)
        if sub:
            t.pack_start(label(sub, "small", wrap=True), False, False, 0)
        h.pack_start(t, True, True, 0)
        row.add(h)
        lb.add(row)

    def fill():
        for r in lb.get_children():
            lb.remove(r)
        found = False
        for line in out(R + ["list"], timeout=60).splitlines():
            parts = line.split("|")
            if len(parts) < 3:
                continue
            dev, kind, size = parts[0], parts[1], parts[2]
            name = dev.replace("/dev/", "")
            found = True
            if kind == "install":
                item("system-run applications-system", "Repair Cherrystone on %s (%s)" % (name, size),
                     "Checks it, puts fresh system files on it and fixes how it starts. Your stuff is kept.",
                     "repair", dev)
                item("folder", "Get your files from Cherrystone on %s" % name, None, "files", dev)
                item("edit-clear-all", "Reset Cherrystone on %s" % name, "Erases your stuff on it.", "reset", dev)
            else:
                item("folder", "Get your files from the Save my stuff drive %s (%s)" % (name, size), None, "files", dev)
                item("edit-clear-all", "Reset the Save my stuff drive %s" % name, "Erases it.", "reset", dev)
        sc.set_visible(found)              # no empty box when there's nothing to list
        intro.set_text("Found Cherrystone on this computer. What do you want to do?" if found else
                       "No installed Cherrystone and no Save my stuff drive were found. "
                       "(A disk that's badly broken may not show up at all.)")
        lb.show_all()

    sc = Gtk.ScrolledWindow()
    sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sc.set_size_request(-1, 220)
    sc.set_no_show_all(True)
    sc.add(lb)
    lb.show()
    add("list", "thinking", intro, sc,
        bar(button("Terminal", "plain", lambda: run(["lxterminal", "-e", "su", "-l", "root"])),
            button("Restart", "plain", lambda: run(["doas", "/sbin/reboot"])),
            button("Shut down", "plain", lambda: run(["doas", "/sbin/poweroff"]))))

    def home():
        state.update(dev=None, pw="")
        show("list", "Cherrystone Recovery")

    def result(mood, heading, text):
        res_text.set_text(text)
        res_pic.set_from_file(STONY % mood)
        show("result", heading)

    # 2. password (only when that Cherrystone has one)
    pw_entry = Gtk.Entry()
    pw_entry.set_visibility(False)
    pw_entry.set_placeholder_text("Password")
    pw_err = label("", "error")
    add("password", "thinking", label("This Cherrystone has a password. Type it to go on.", "sub", wrap=True),
        pw_entry, pw_err,
        bar(button("Back", "plain", home), button("OK", "main", lambda: check_pw())))

    def check_pw():
        pw = pw_entry.get_text()
        p = subprocess.run(R + ["check", state["dev"]], input=pw + "\n", text=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if p.returncode == 0:
            state["pw"] = pw
            state["after"]()
        else:
            pw_entry.set_text("")
            pw_err.set_text("That's not the password. Try again.")
    pw_entry.connect("activate", lambda *_: check_pw())

    def with_password(then):
        state["after"] = then
        if ok(R + ["haspass", state["dev"]]):
            pw_entry.set_text("")
            pw_err.set_text("")
            show("password", "Password")
            pw_entry.grab_focus()
        else:
            then()

    # 3a. repair: confirm, then progress
    add("repair", "happy",
        label("It checks the disk for errors, puts fresh system files on it from this USB stick "
              "(so it also updates it) and fixes how it starts. Your settings and files are kept.",
              "sub", wrap=True),
        bar(button("Back", "plain", home), button("Repair", "main", lambda: repair())))
    step = label("Getting ready...", "bold", wrap=True)
    prog = Gtk.ProgressBar()
    add("working", "happy", step, prog, label("Keep the computer plugged in.", "sub", wrap=True))

    def repair():
        state["busy"] = True
        show("working", "Repairing")
        proc = subprocess.Popen(R + ["repair", state["dev"]], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        proc.stdin.write(state["pw"] + "\n")
        proc.stdin.close()

        def update(line):
            if line.startswith("#") and not line.startswith("# Error"):
                step.set_text(line[1:].strip() + "...")
            elif line.strip().isdigit():
                prog.set_fraction(int(line) / 100.0)
            return False

        def work():
            for line in proc.stdout:
                GLib.idle_add(update, line.rstrip("\n"))
            errs = [l[7:] for l in proc.stderr.read().splitlines() if l.startswith("ERROR: ")]
            return proc.wait() == 0 and not errs, errs

        def done(r):
            state["busy"] = False
            good, errs = r
            if good:
                result("cool", "Repaired", "Take out the USB stick and restart to start Cherrystone from the disk.")
            else:
                result("sad", "The repair didn't finish", errs[0] if errs else "Something went wrong.")
            return False
        in_thread(work, done)

    # 3b. files
    def files():
        p = subprocess.run(R + ["files", state["dev"]], input=state["pw"] + "\n", text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        d = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else ""
        if os.path.isdir(d):
            run(["pcmanfm", d])
            result("happy", "Your files are open in Files",
                   "They're read-only. Plug in a USB stick and copy what you need onto it.")
        else:
            errs = [l[7:] for l in p.stderr.splitlines() if l.startswith("ERROR: ")]
            result("sad", "Couldn't open the files", errs[0] if errs else "Something went wrong.")

    # 3c. reset: type ERASE
    erase = Gtk.Entry()
    erase.set_placeholder_text("ERASE")
    erase_go = button("Erase", "main", lambda: do_reset())
    erase_go.set_sensitive(False)
    erase.connect("changed", lambda e: erase_go.set_sensitive(e.get_text() == "ERASE"))
    add("reset", "surprised",
        label("This erases everything kept on it: settings, Wi-Fi passwords, the password and every "
              "file. It can't be undone.", "sub", wrap=True),
        label("To erase it, type ERASE (in capitals):", "bold", wrap=True), erase,
        bar(button("Cancel", "plain", home), erase_go))

    def do_reset():
        p = subprocess.run(R + ["reset", state["dev"]], input=state["pw"] + "\n", text=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if p.returncode == 0:
            result("happy", "Erased", "It starts fresh next time.")
        else:
            errs = [l[7:] for l in p.stderr.splitlines() if l.startswith("ERROR: ")]
            result("sad", "Nothing was erased", errs[0] if errs else "Something went wrong.")

    # 4. how it went
    res_text = label("", "sub", wrap=True)
    res = add("result", "happy", res_text, bar(button("Back to the list", "main", lambda: (fill(), home()))))
    res_pic = res.get_children()[0]

    def picked(lb, row):
        state["dev"] = row.dev
        name = row.dev.replace("/dev/", "")
        if row.action == "repair":
            with_password(lambda: show("repair", "Repair Cherrystone on %s?" % name))
        elif row.action == "files":
            with_password(files)
        elif row.action == "reset":
            def ask():
                erase.set_text("")
                show("reset", "Woah there!")
                erase.grab_focus()
            with_password(ask)
    lb.connect("row-activated", picked)

    win.connect("delete-event", lambda *_: True)
    win.connect("key-press-event", lambda w, e: True if e.keyval == Gdk.KEY_Escape else False)
    fill()
    win.show_all()
    home()


# ---------------------------------------------------------------------- main

SCREENS = {"wifi": wifi, "power": power, "password": password, "notifications": notifications,
           "profile": profile, "wallpaper": wallpaper, "display": display, "touchpad": touchpad,
           "about": about, "shortcuts": shortcuts, "tiles": tiles, "install": install,
           "save": save, "reset": reset, "linuxapps": linuxapps, "recovery": recovery}

# Dark mode (Settings > Personalize): the same colour swap as the rest of Cherrystone
_DARK = [('#ffffff', '#18181a'), ('#f8f9fa', '#1e1e21'), ('#f1f3f4', '#26262a'), ('#e8eaed', '#303035'), ('#dadce0', '#3c3c42'), ('#d7d9dc', '#303035'), ('#c4c7cc', '#3c3c42'), ('#fde4e8', '#4a1a26'), ('#fbe3e8', '#4a1a26'), ('#f9c9d2', '#5c1f2e'), ('#202124', '#ececef'), ('#3c4043', '#c8c8cc'), ('#5f6368', '#a0a0a6'), ('#80868b', '#8a8a90'), ('#9aa0a6', '#76767c'), ('#bdc1c6', '#5a5a60')]


def _darken(css):
    if open(os.path.expanduser("~/.config/cherrystone/theme")).read().strip() != "dark":
        return css
    s = css.decode()
    s = re.sub(r"(?<![-.\w])color: #ffffff", "color: @KEEPWHITE@", s)
    for i, (a, _) in enumerate(_DARK):
        s = re.sub(a, "@C%d@" % i, s, flags=re.I)
    for i, (_, b) in enumerate(_DARK):
        s = s.replace("@C%d@" % i, b)
    return s.replace("@KEEPWHITE@", "#ffffff").encode()


if __name__ == "__main__":
    prov = Gtk.CssProvider()
    try:
        prov.load_from_data(_darken(CSS))
    except OSError:
        prov.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                             Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
    args = sys.argv[1:] or ["about"]
    if args[0] == "slider":
        if not slider(args[1] if len(args) > 1 else "volume"):
            sys.exit(0)
    elif args[0] == "message":
        message(*(args[1:4] + [""] * (3 - len(args[1:4]))))
    elif args[0] in SCREENS:
        if SCREENS[args[0]]() is not None:   # a screen that only showed a notice
            sys.exit(0)
    else:
        sys.exit("unknown screen: " + args[0])
    Gtk.main()
