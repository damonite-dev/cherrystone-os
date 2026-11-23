#!/usr/bin/env python3
# Cherrystone Settings and quick settings, in the same look as the sign-in screen.
#   cherrystone-settings            Settings
#   cherrystone-settings advanced   the rarely needed things
#   cherrystone-settings quick      quick settings, above the clock (click the clock)
import os, re, sys, signal, subprocess, time
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib

GUEST = os.environ.get("USER") == "guest"

CSS = b"""
window.cherry { background: #ffffff; }
window.pop { border-top: 3px solid #d81e3c; }
.title { font-size: 24px; font-weight: 300; color: #202124; }
.clock { font-size: 34px; font-weight: 300; color: #202124; }
.sub { color: #5f6368; }
.small { font-size: 9px; color: #3c4043; }
button.tile { background: none; background-image: none; border: none; border-radius: 0;
              padding: 6px 10px; box-shadow: none; }
/* the same size in every state, and only the background fades (no growing text) */
button.tile, button.tile:hover, button.tile:active, button.tile:focus {
              transition: background-color 150ms ease-out; -gtk-icon-transform: none; }
button.tile label, button.tile:hover label, button.tile:active label, button.tile:focus label {
              font-size: 15px; font-weight: 300; transition: none; }
.title { font-size: 34px; }
button.tile:hover { background: #fde4e8; }
button.tile label { color: #202124; }
button.round { background: #f1f3f4; background-image: none; border: none; border-radius: 24px;
               min-width: 46px; min-height: 46px; padding: 0; box-shadow: none; }
button.round:hover { background: #fde4e8; }
button.round.on { background: #d81e3c; }
button.round.on image { color: #ffffff; }
button.link { background: none; background-image: none; border: none; box-shadow: none;
              color: #d81e3c; padding: 4px 8px; }
scale highlight { background: #d81e3c; }
scale slider { background: #ffffff; border: 2px solid #d81e3c; }
button { transition: background-color 150ms ease-out, color 150ms ease-out; }
button.tile:active, button.round:active { background: #f9c9d2; }
button.round.on:active { background: #b3122f; }
"""


def run(cmd):
    subprocess.Popen(cmd, shell=True, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def out(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


def icon(names, size):
    theme = Gtk.IconTheme.get_default()
    names = names.split()
    pick = next((n for n in names if theme.has_icon(n)), names[-1])
    img = Gtk.Image.new_from_icon_name(pick, Gtk.IconSize.DIALOG)
    img.set_pixel_size(size)
    return img


def tile(label, icons, action):
    # A plain row: small icon, big light text (no boxes)
    b = Gtk.Button()
    b.get_style_context().add_class("tile")
    box = Gtk.Box(spacing=14)
    # Papirus's Bluetooth icon is a tall oval that fills its whole square, so
    # it's drawn smaller to look the same size as the others
    pic = icon(icons, 18 if "bluetooth" in icons else 24)
    pic.set_size_request(24, -1)
    box.pack_start(pic, False, False, 0)
    lab = Gtk.Label(label=label, xalign=0)
    box.pack_start(lab, True, True, 0)
    b.add(box)
    b.set_size_request(250, 42)
    b.connect("clicked", lambda *_: action() if callable(action) else run(action))
    return b


def grid(items):
    g = Gtk.Grid(column_spacing=24, row_spacing=2, column_homogeneous=True)
    for i, (label, icons, action) in enumerate(items):
        g.attach(tile(label, icons, action), i % 2, i // 2, 1, 1)
    return g


def styled(win, *classes):
    for c in ("cherry",) + classes:
        win.get_style_context().add_class(c)


# ------------------------------------------------------------------ Settings

EVERYDAY = [
    ("Wi-Fi", "preferences-system-network network-wireless", "cherrystone-wifi"),
    ("Bluetooth", "preferences-system-bluetooth bluetooth", "cherrystone-bluetooth"),
    ("Sound", "preferences-desktop-sound multimedia-volume-control audio-volume-high", "cherrystone-slider volume"),
    ("Display", "preferences-desktop-display video-display", "cherrystone-display"),
    ("Personalize", "preferences-desktop-wallpaper preferences-desktop-background image-x-generic", "cherrystone-wallpaper"),
    ("Name and picture", "preferences-desktop-user user-info avatar-default", "cherrystone-profile"),
    ("Password", "preferences-desktop-user-password dialog-password system-lock-screen", "cherrystone-lockpass"),
    ("Keyboard and time", "preferences-desktop-keyboard input-keyboard", "cherrystone-welcome --settings"),
    ("Touchpad", "input-touchpad preferences-desktop-peripherals", "cherrystone-touchpad"),
    ("Home page", "user-home web-browser", "cherrystone-tiles"),
    ("About", "help-about dialog-information", "cherrystone-about"),
]
ADVANCED = [
    ("Save my stuff", "drive-removable-media", "cherrystone-save"),
    ("Reset", "edit-clear-all edit-clear", "cherrystone-reset"),
    ("Shortcuts", "preferences-desktop-keyboard-shortcuts input-keyboard", "cherrystone-shortcuts"),
    ("Advanced tools", "utilities-terminal", "cherrystone-linuxapps"),
    ("Network details", "preferences-system-network network-wired", "nm-connection-editor"),
]
# Running from the USB stick: Install comes first (it's how you keep Cherrystone)
LIVE = "cherrystone.live" in open("/proc/cmdline").read().split() if os.path.exists("/proc/cmdline") else False
if LIVE:
    EVERYDAY.insert(0, ("Install", "system-software-install drive-harddisk", "cherrystone-installer"))
GUEST_ITEMS = [i for i in EVERYDAY if i[0] in ("Wi-Fi", "Bluetooth", "Sound", "Display", "Touchpad", "About")]


def settings(start):
    win = Gtk.Window(title="Settings")
    win.set_icon_name("preferences-system")
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_resizable(False)
    styled(win)
    win.connect("destroy", Gtk.main_quit)
    win.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and w.destroy())

    stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)

    def page(title, sub, items, back):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_border_width(22)
        top = Gtk.Box(spacing=8)
        if back:
            b = Gtk.Button(label="‹ Back")
            b.get_style_context().add_class("link")
            b.connect("clicked", lambda *_: stack.set_visible_child_name("main"))
            top.pack_start(b, False, False, 0)
        t = Gtk.Label(label=title.lower(), xalign=0)
        t.get_style_context().add_class("title")
        top.pack_start(t, False, False, 0)
        box.pack_start(top, False, False, 0)
        if sub:
            s = Gtk.Label(label=sub, xalign=0)
            s.get_style_context().add_class("sub")
            box.pack_start(s, False, False, 0)
        box.pack_start(grid(items), False, False, 0)
        return box

    if GUEST:
        stack.add_named(page("Settings", "You're a guest, so only some settings are here.", GUEST_ITEMS, False), "main")
    else:
        main = EVERYDAY + [("Advanced", "preferences-system applications-system",
                            lambda: stack.set_visible_child_name("advanced"))]
        stack.add_named(page("Settings", None, main, False), "main")
        stack.add_named(page("Advanced", "Backups, resetting and extras.", ADVANCED, True), "advanced")
    win.add(stack)
    win.show_all()
    if start == "advanced" and not GUEST:
        stack.set_visible_child_name("advanced")


# ------------------------------------------------------------ Quick settings

def mixer():
    for ctl in ("Master", "PCM"):
        if subprocess.run(["amixer", "sget", ctl], capture_output=True).returncode == 0:
            return ctl
    return None


def network():
    ssid = out("nmcli -t -f active,ssid dev wifi | awk -F: '$1 == \"yes\" { print $2; exit }'")
    if ssid:
        return ssid, True
    if "ethernet:connected" in out("nmcli -t -f type,state dev"):
        return "Wired", True
    return "Wi-Fi", False


def battery():
    for b in sorted(os.listdir("/sys/class/power_supply")) if os.path.isdir("/sys/class/power_supply") else []:
        p = os.path.join("/sys/class/power_supply", b)
        if b.startswith("BAT") and os.path.exists(p + "/capacity"):
            cap = open(p + "/capacity").read().strip()
            st = open(p + "/status").read().strip() if os.path.exists(p + "/status") else ""
            return cap + "%" + (" · charging" if st == "Charging" else "")
    return None


def slider(icons, value, on_change):
    row = Gtk.Box(spacing=10)
    row.pack_start(icon(icons, 22), False, False, 0)
    sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 5)
    sc.set_draw_value(False)
    sc.set_value(value)
    pending = {}

    def changed(s):
        if "id" in pending:
            GLib.source_remove(pending["id"])

        def apply():
            pending.pop("id", None)
            on_change(int(s.get_value()))
            return False
        pending["id"] = GLib.timeout_add(120, apply)
    sc.connect("value-changed", changed)
    row.pack_start(sc, True, True, 0)
    return row


def round_button(label, icons, action, on=False, close=None):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    b = Gtk.Button()
    b.get_style_context().add_class("round")
    if on:
        b.get_style_context().add_class("on")
    b.add(icon(icons, 20))
    b.set_halign(Gtk.Align.CENTER)
    b.set_tooltip_text(label)

    def go(*_):
        if close:
            close()
        action() if callable(action) else run(action)
    b.connect("clicked", go)
    box.pack_start(b, False, False, 0)
    lab = Gtk.Label(label=label)
    lab.get_style_context().add_class("small")
    lab.set_ellipsize(3)  # end
    lab.set_max_width_chars(10)
    box.pack_start(lab, False, False, 0)
    return box


def quick():
    pidf = "/tmp/cherrystone-quick.%d" % os.getuid()
    try:  # clicking the clock again closes it
        os.kill(int(open(pidf).read()), signal.SIGTERM)
        os.remove(pidf)
        return False
    except Exception:
        pass
    open(pidf, "w").write(str(os.getpid()))

    win = Gtk.Window(title="Quick settings")
    win.set_wmclass("CherryQuick", "CherryQuick")
    win.set_decorated(False)
    win.set_skip_taskbar_hint(True)
    win.set_keep_above(True)
    win.set_resizable(False)
    styled(win, "pop")

    def close(*_):
        try:
            os.remove(pidf)
        except Exception:
            pass
        Gtk.main_quit()
    win.connect("destroy", close)
    win.connect("focus-out-event", lambda *_: win.destroy())
    win.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and w.destroy())
    shut = win.destroy

    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    box.set_border_width(18)
    box.set_size_request(340, -1)

    top = Gtk.Box(spacing=8)
    left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    c = Gtk.Label(label=time.strftime("%H:%M"), xalign=0)
    c.get_style_context().add_class("clock")
    d = Gtk.Label(label=time.strftime("%A %-d %B"), xalign=0)
    d.get_style_context().add_class("sub")
    left.pack_start(c, False, False, 0)
    left.pack_start(d, False, False, 0)
    top.pack_start(left, True, True, 0)
    bat = battery()
    if bat:
        bl = Gtk.Label(label=bat)
        bl.get_style_context().add_class("sub")
        top.pack_end(bl, False, False, 0)
        top.pack_end(icon("battery-good-symbolic battery-full-symbolic", 18), False, False, 0)
    box.pack_start(top, False, False, 0)

    net, connected = network()
    paused = out("dunstctl is-paused") == "true"

    def toggle_dnd():
        run("dunstctl set-paused toggle")
    row = Gtk.Grid(column_spacing=8, column_homogeneous=True)
    for i, w in enumerate([
        round_button(net, "network-wired-symbolic" if net == "Wired" else "network-wireless-signal-excellent-symbolic" if connected
                     else "network-wireless-offline-symbolic", "cherrystone-wifi", connected, shut),
        round_button("Bluetooth", "bluetooth-active-symbolic", "cherrystone-bluetooth", False, shut),
        round_button("Do not disturb" if paused else "Notifications",
                     "notifications-disabled-symbolic" if paused else "preferences-system-notifications-symbolic",
                     "cherrystone-notifications", paused, shut),
        round_button("Settings", "emblem-system-symbolic", "cherrystone-settings", False, shut),
    ]):
        row.attach(w, i, 0, 1, 1)
    box.pack_start(row, False, False, 0)

    ctl = mixer()
    if ctl:
        info = out("amixer sget %s" % ctl)
        import re
        m = re.search(r"\[(\d+)%\]", info)
        vol = int(m.group(1)) if m else 50
        box.pack_start(slider("audio-volume-high-symbolic", vol,
                              lambda v: run("amixer -q sset %s %d%% unmute" % (ctl, v))), False, False, 0)
    bmax = out("brightnessctl -c backlight max")
    if bmax.isdigit() and int(bmax) > 0:
        cur = out("brightnessctl -c backlight get")
        pct = int(cur) * 100 // int(bmax) if cur.isdigit() else 100
        box.pack_start(slider("display-brightness-symbolic", pct,
                              lambda v: run("doas /usr/bin/brightnessctl -c backlight -q set %d%%" % max(v, 5))), False, False, 0)

    sep = Gtk.Separator()
    box.pack_start(sep, False, False, 0)
    bottom = Gtk.Grid(column_spacing=8, column_homogeneous=True)
    for i, w in enumerate([
        round_button("Lock", "system-lock-screen-symbolic", "cherrystone-lock", False, shut),
        round_button("Sign out", "system-log-out-symbolic", "openbox --exit", False, shut),
        round_button("Restart", "system-reboot-symbolic", "cherrystone-power restart", False, shut),
        round_button("Shut down", "system-shutdown-symbolic", "cherrystone-power off", False, shut),
    ]):
        if GUEST and i == 0:
            continue
        bottom.attach(w, i, 0, 1, 1)
    box.pack_start(bottom, False, False, 0)

    win.add(box)
    win.show_all()
    w, h = win.get_size()
    disp = Gdk.Display.get_default()
    mon = disp.get_primary_monitor() or disp.get_monitor(0)
    g = mon.get_geometry()
    win.move(g.x + g.width - w, g.y + g.height - h - 40)   # sits on the shelf
    win.present()
    return True


# Dark mode (Settings > Personalize): the same colour swap as the rest of Cherrystone
_DARK = [('#ffffff', '#18181a'), ('#f8f9fa', '#1e1e21'), ('#f1f3f4', '#26262a'), ('#e8eaed', '#303035'), ('#dadce0', '#3c3c42'), ('#d7d9dc', '#303035'), ('#c4c7cc', '#3c3c42'), ('#fde4e8', '#4a1a26'), ('#fbe3e8', '#4a1a26'), ('#f9c9d2', '#5c1f2e'), ('#202124', '#ececef'), ('#3c4043', '#c8c8cc'), ('#5f6368', '#a0a0a6'), ('#80868b', '#8a8a90'), ('#9aa0a6', '#76767c'), ('#bdc1c6', '#5a5a60')]


try:                                       # Personalize > Accent colour
    import sys as _sys
    _sys.path.insert(0, "/usr/lib/cherrystone")
    from accent import accent as _accent
except Exception:
    def _accent(css):
        return css


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
        prov.load_from_data(_accent(_darken(CSS)))
    except OSError:
        prov.load_from_data(_accent(CSS))
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                             Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "quick":
        if not quick():
            sys.exit(0)
    else:
        settings(arg)
    Gtk.main()
