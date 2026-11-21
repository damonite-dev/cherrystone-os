#!/bin/sh
# Cherrystone extras, part 3 (sourced by rootfs-config.sh, same $tmp and
# helpers): the browser's "can't reach this page" and history pages, the
# Notes and Calculator apps, and the update check.

mkdir -p "$tmp"/usr/share/cherrystone

# Stony, the Cherrystone mascot (named after the stone in a cherry): pixel pictures of
# its moods, drawn by branding/stony/make-stony.py. Used by Welcome, the tour,
# "not found" messages, empty lists, the offline bar and Cherry Run.
mkdir -p "$tmp"/usr/share/cherrystone/stony
cp "$BRAND"/stony/stony-*.png "$tmp"/usr/share/cherrystone/stony/
chmod 0644 "$tmp"/usr/share/cherrystone/stony/*.png

# Cherry Run, the little pixel-art runner (games/cherry-run.js). It lives on
# the "This page didn't load" page below, like a game you can play while
# you wait; cherry-run.html is the same game on its own page, for the home
# page's "You're offline" bar.
install -m 0644 "$BRAND"/../games/cherry-run.html "$BRAND"/../games/cherry-run.js "$tmp"/usr/share/cherrystone/

# ------------------------------------------------- browser: page didn't load
# Shown by Cherrystone's Badwolf in place of WebKit's own error. @URL@ is
# the address that failed. The page shows its own address (not a file), so
# it can't load other files: the game's code is copied right into it.
{
cat <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Can't reach this page</title>
<style>
body { background: #ffffff; color: #202124; font-family: Cantarell, "DejaVu Sans", sans-serif; margin: 0; }
.box { max-width: 640px; margin: 0 auto; padding: 18px 20px; }
.box { margin-top: 50px; }
#game { display: none; justify-content: center; margin-top: 12px; }
/* Playing: the game gets the space, the message shrinks to a line */
body.playing .box { margin-top: 4px; padding-top: 6px; }
body.playing #sad, body.playing .url, body.playing p { display: none; }
body.playing h1 { font-size: 16px; margin-top: 4px; display: inline-block; margin-right: 10px; }
body.playing .b { margin-top: 4px; padding: 6px 14px; }
canvas { display: block; touch-action: none; image-rendering: -webkit-optimize-contrast;
         image-rendering: pixelated; image-rendering: crisp-edges; }
#sad { width: 48px; height: 52px; }
h1 { font-size: 22px; font-weight: normal; margin: 16px 0 2px; }
.url { color: #5f6368; word-break: break-all; font-size: 14px; }
p { color: #3c4043; margin: 8px 0 0; font-size: 14px; }
.b { display: inline-block; margin: 12px 8px 0 0; padding: 8px 16px; border-radius: 0;
     text-decoration: none; font-size: 14px; cursor: pointer; border: none; font-family: inherit; }
.main { background: #d81e3c; color: #ffffff; }
.other { background: #f1f3f4; color: #202124; }
</style></head>
<body><div id="game"><canvas id="c" width="320" height="160" data-room="70"></canvas></div>
<div class="box">
<canvas id="sad" width="12" height="13"></canvas>
<h1>This page didn't load</h1>
<div class="url">@URL@</div>
<p>Check that you're online and the address is right. The site might also be down for a minute.</p>
<button class="b main" onclick="location.reload()">Try again</button>
<a class="b other" href="cherrystone:wifi">Connect to Wi-Fi</a>
</div>
<script>
if (!navigator.onLine)
  document.querySelector("h1").textContent = "You're offline";
// The secret: a sad grey cherry. Click it (or press Space) and it turns
// into Cherry Run. Until then the game is hidden and doesn't run.
window.CHERRY_HIDDEN = true;
(function () {
  var rows = [".......ggll.", "......g.lll.", ".....g......", "...rrrrrr...", "..rhhrrrrr..",
              ".rhhrrrrrrr.", ".rrrkrrrkrr.", ".rrrkrrrkrr.", ".rrrrrrrrrr.", ".rrrrkkkrrr.",
              "..drkrrrkrd.", "..ddrrrrrdd.", "...dddddd..."];
  var col = { g: "#5f6368", l: "#9aa0a6", r: "#bdc1c6", h: "#e8eaed", d: "#80868b", k: "#3c4043" };
  var sg = document.getElementById("sad").getContext("2d");
  for (var y = 0; y < rows.length; y++)
    for (var x = 0; x < 12; x++)
      if (rows[y][x] !== ".") { sg.fillStyle = col[rows[y][x]]; sg.fillRect(x, y, 1, 1); }
})();
EOF
cat "$BRAND"/../games/cherry-run.js
cat <<'EOF'

(function () {
  var sad = document.getElementById("sad"), box = document.getElementById("game");
  function reveal() {
    if (started) return;
    document.body.className = "playing";
    box.style.display = "flex";
    cherryStart();
    press();                         // off it goes
  }
  sad.addEventListener("click", reveal);
  window.addEventListener("keydown", function (e) {
    if (!started && (e.key === " " || e.key === "ArrowUp")) { e.preventDefault(); e.stopPropagation(); reveal(); }
  }, true);
})();
</script>
</body></html>
EOF
} > "$tmp"/usr/share/cherrystone/error.html
chmod 0644 "$tmp"/usr/share/cherrystone/error.html

# ------------------------------------------------------- browser: history
# Ctrl+H. The browser adds each page you visit to history.js next to this
# page (in ~/.local/share/cherrystone); cherrystone-browser copies it there.
makefile root:root 0644 "$tmp"/usr/share/cherrystone/history.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>History</title>
<style>
body { background: #ffffff; color: #202124; font-family: Cantarell, "DejaVu Sans", sans-serif; margin: 0; }
.wrap { max-width: 760px; margin: 0 auto; padding: 24px 16px; }
h1 { font-size: 24px; font-weight: normal; margin: 0 0 16px; }
.bar { display: flex; gap: 10px; margin-bottom: 18px; }
input { flex: 1; border: none; background: #f1f3f4; border-radius: 0; padding: 9px 16px;
        font-size: 14px; font-family: inherit; outline: none; }
input:focus { background: #fff; box-shadow: 0 0 0 2px #d81e3c; }
.clear { background: #f1f3f4; color: #202124; border-radius: 0; padding: 9px 16px;
         text-decoration: none; font-size: 14px; white-space: nowrap; }
h2 { font-size: 13px; color: #5f6368; font-weight: bold; margin: 22px 0 6px; }
a.row { display: flex; gap: 14px; padding: 7px 10px; border-radius: 0; text-decoration: none; color: #202124; }
a.row:hover { background: #fde4e8; }
.t { color: #5f6368; font-size: 13px; width: 44px; flex: none; }
.n { flex: 1; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.d { color: #80868b; font-size: 13px; max-width: 220px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.empty { color: #5f6368; margin-top: 30px; text-align: center; }
</style></head>
<body><div class="wrap">
<h1>History</h1>
<div class="bar"><input id="q" placeholder="Search history" autofocus>
<a class="clear" href="cherrystone:clear-history" onclick="setTimeout(function () { location.reload(); }, 800)">Clear history</a></div>
<div id="list"></div>
</div>
<script>
var all = [];
function dec(s) {
  try { return new TextDecoder().decode(Uint8Array.from(atob(s), function (c) { return c.charCodeAt(0); })); }
  catch (e) { return ""; }
}
function H(u, t, when) { all.push({ u: dec(u), t: dec(t), w: when }); }
</script>
<script src="history.js"></script>
<script>
var list = document.getElementById("list"), q = document.getElementById("q");
function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;"); }
function show() {
  var f = q.value.toLowerCase(), html = "", day = "", n = 0, seen = {};
  for (var i = all.length - 1; i >= 0 && n < 400; i--) {
    var e = all[i];
    if (f && (e.u + " " + e.t).toLowerCase().indexOf(f) < 0) continue;
    var d = new Date(e.w * 1000), ds = d.toDateString();
    if (seen[ds + e.u]) continue;
    seen[ds + e.u] = 1;
    if (ds !== day) { day = ds; html += "<h2>" + d.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" }) + "</h2>"; }
    var host = e.u.replace(/^https?:\/\//, "").split("/")[0];
    html += '<a class="row" href="' + esc(e.u) + '"><span class="t">' +
      ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2) + '</span><span class="n">' +
      esc(e.t || e.u) + '</span><span class="d">' + esc(host) + "</span></a>";
    n++;
  }
  list.innerHTML = html || '<p class="empty"><img src="file:///usr/share/cherrystone/stony/stony-sleepy-small.png" alt="" ' +
    'style="display:block;margin:0 auto 10px;image-rendering:pixelated">' + (f ? "Nothing matches." : "No history yet.") + "</p>";
}
q.oninput = show;
show();
</script>
</body></html>
EOF

# ------------------------------------------------------------------ Notes
# Notes are plain text files in Documents/Notes, saved as you type.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-notes <<'EOF'
#!/usr/bin/env python3
import os, time
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib, Pango

DIR = os.path.expanduser("~/Documents/Notes")
os.makedirs(DIR, exist_ok=True)
CSS = b"""
window { background: #ffffff; }
.side { background: #f1f3f4; }
.side row { padding: 8px 12px; border-radius: 0; margin: 2px 6px; }
.side row:selected { background: #d81e3c; color: #ffffff; }
.side row:selected label { color: #ffffff; }
.when { font-size: 9px; color: #5f6368; }
button.new { background: #d81e3c; background-image: none; color: #ffffff; border: none;
             border-radius: 0; padding: 6px 14px; box-shadow: none; margin: 10px; }
button.new label { color: #ffffff; }
button.del { background: none; background-image: none; border: none; box-shadow: none; color: #5f6368; }
textview, textview text { background: #ffffff; color: #202124; font-size: 13px; }
"""


def title_of(path):
    try:
        with open(path) as f:
            line = f.readline().strip()
        return line[:40] or "Empty note"
    except OSError:
        return "Empty note"


class Notes(Gtk.Window):
    def __init__(self):
        super().__init__(title="Notes")
        self.set_icon_name("accessories-text-editor")
        self.set_default_size(760, 480)
        self.current, self.pending, self.loading = None, None, False
        paned = Gtk.Box()
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.get_style_context().add_class("side")
        side.set_size_request(220, -1)
        new = Gtk.Button(label="+  New note")
        new.get_style_context().add_class("new")
        new.connect("clicked", lambda *_: self.new_note())
        side.pack_start(new, False, False, 0)
        self.list = Gtk.ListBox()
        self.list.get_style_context().add_class("side")
        self.list.connect("row-selected", self.pick)
        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.add(self.list)
        side.pack_start(sc, True, True, 0)
        delete = Gtk.Button(label="Delete this note")
        delete.get_style_context().add_class("del")
        delete.connect("clicked", lambda *_: self.delete())
        side.pack_end(delete, False, False, 6)
        paned.pack_start(side, False, False, 0)
        self.text = Gtk.TextView()
        self.text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        for m in ("left", "right", "top", "bottom"):
            getattr(self.text, "set_%s_margin" % m)(22)
        self.text.get_buffer().connect("changed", self.changed)
        tsc = Gtk.ScrolledWindow()
        tsc.add(self.text)
        paned.pack_start(tsc, True, True, 0)
        self.add(paned)
        self.connect("delete-event", lambda *_: self.save() or False)
        self.connect("destroy", Gtk.main_quit)
        self.refresh()
        if not self.files():
            self.new_note()
        else:
            self.list.select_row(self.list.get_row_at_index(0))

    def files(self):
        fs = [os.path.join(DIR, f) for f in os.listdir(DIR) if f.endswith(".txt")]
        return sorted(fs, key=os.path.getmtime, reverse=True)

    def refresh(self, select=None):
        self.loading = True
        for r in self.list.get_children():
            self.list.remove(r)
        for path in self.files():
            row = Gtk.ListBoxRow()
            row.path = path
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            name = Gtk.Label(label=title_of(path), xalign=0)
            name.set_ellipsize(Pango.EllipsizeMode.END)
            when = Gtk.Label(label=time.strftime("%-d %b, %H:%M", time.localtime(os.path.getmtime(path))), xalign=0)
            when.get_style_context().add_class("when")
            box.pack_start(name, False, False, 0)
            box.pack_start(when, False, False, 0)
            row.add(box)
            self.list.add(row)
            if path == select:
                self.list.select_row(row)
        self.list.show_all()
        self.loading = False

    def pick(self, lb, row):
        if self.loading or row is None or row.path == self.current:
            return
        self.save()
        self.current = row.path
        try:
            data = open(row.path).read()
        except OSError:
            data = ""
        self.loading = True
        self.text.get_buffer().set_text(data)
        self.loading = False
        self.text.grab_focus()

    def new_note(self):
        self.save()
        path = os.path.join(DIR, time.strftime("note-%Y%m%d-%H%M%S.txt"))
        open(path, "w").close()
        self.current = None
        self.refresh(select=path)
        row = self.list.get_selected_row()
        if row:
            self.pick(self.list, row)

    def changed(self, buf):
        if self.loading or not self.current:
            return
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(800, self.save)

    def save(self):
        if self.pending:
            GLib.source_remove(self.pending)
            self.pending = None
        if self.current:
            b = self.text.get_buffer()
            data = b.get_text(b.get_start_iter(), b.get_end_iter(), False)
            try:
                old = open(self.current).read()
            except OSError:
                old = None
            if data != old:
                with open(self.current, "w") as f:
                    f.write(data)
                self.refresh(select=self.current)
        return False

    def delete(self):
        if not self.current:
            return
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                              buttons=Gtk.ButtonsType.NONE, text="Delete this note?")
        d.add_buttons("Cancel", 0, "Delete", 1)
        r = d.run()
        d.destroy()
        if r != 1:
            return
        os.remove(self.current)
        self.current = None
        self.loading = True
        self.text.get_buffer().set_text("")
        self.loading = False
        self.refresh()
        if self.files():
            self.list.select_row(self.list.get_row_at_index(0))
        else:
            self.new_note()


p = Gtk.CssProvider()
p.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
Notes().show_all()
Gtk.main()
EOF

# ------------------------------------------------------------- Calculator
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-calculator <<'EOF'
#!/usr/bin/env python3
import ast, operator
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk

CSS = b"""
window { background: #ffffff; }
.screen { font-size: 30px; color: #202124; padding: 10px 6px; }
.prev { font-size: 12px; color: #5f6368; }
button { background: #f1f3f4; background-image: none; border: none; border-radius: 0;
         font-size: 17px; min-height: 46px; box-shadow: none; color: #202124; }
button:hover { background: #fde4e8; }
button.op { background: #fde4e8; color: #b3122f; }
button.eq { background: #d81e3c; color: #ffffff; }
button.eq label { color: #ffffff; }
"""
OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
       ast.Div: operator.truediv, ast.Mod: operator.mod, ast.Pow: operator.pow}


def calc(node):
    if isinstance(node, ast.Expression):
        return calc(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in OPS:
        a, b = calc(node.left), calc(node.right)
        if isinstance(node.op, ast.Pow) and abs(b) > 100:
            raise ValueError
        return OPS[type(node.op)](a, b)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        v = calc(node.operand)
        return -v if isinstance(node.op, ast.USub) else v
    raise ValueError


def nice(v):
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 1e15:
            return str(int(v))
        return ("%.10g" % v)
    return str(v)


win = Gtk.Window(title="Calculator")
win.set_icon_name("accessories-calculator")
win.set_resizable(False)
win.connect("destroy", Gtk.main_quit)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
box.set_border_width(14)
prev = Gtk.Label(xalign=1)
prev.get_style_context().add_class("prev")
screen = Gtk.Label(label="0", xalign=1)
screen.get_style_context().add_class("screen")
screen.set_selectable(True)
box.pack_start(prev, False, False, 0)
box.pack_start(screen, False, False, 0)
expr = [""]


def update():
    screen.set_text(expr[0].replace("*", "×").replace("/", "÷") or "0")


def press(k):
    if k == "C":
        expr[0] = ""
        prev.set_text("")
    elif k == "⌫":
        expr[0] = expr[0][:-1]
    elif k == "=":
        if not expr[0]:
            return
        try:
            r = nice(calc(ast.parse(expr[0].replace("^", "**"), mode="eval")))
            prev.set_text(screen.get_text() + " =")
            expr[0] = r
        except ZeroDivisionError:
            prev.set_text("Can't divide by zero")
        except Exception:
            prev.set_text("That doesn't add up")
    elif k == "%":
        expr[0] += "/100"
    else:
        expr[0] += {"×": "*", "÷": "/", "−": "-"}.get(k, k)
    update()


grid = Gtk.Grid(row_spacing=8, column_spacing=8, column_homogeneous=True)
keys = ["C", "(", ")", "÷",
        "7", "8", "9", "×",
        "4", "5", "6", "−",
        "1", "2", "3", "+",
        "0", ".", "⌫", "="]
for i, k in enumerate(keys):
    b = Gtk.Button(label=k)
    b.set_size_request(64, -1)
    if k in "÷×−+":
        b.get_style_context().add_class("op")
    if k == "=":
        b.get_style_context().add_class("eq")
    b.connect("clicked", lambda _b, k=k: press(k))
    b.set_can_focus(False)
    grid.attach(b, i % 4, i // 4, 1, 1)
box.pack_start(grid, False, False, 0)


def key(w, e):
    ch = e.string
    if e.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) or ch == "=":
        press("=")
    elif e.keyval == Gdk.KEY_BackSpace:
        press("⌫")
    elif e.keyval == Gdk.KEY_Escape or ch in ("c", "C"):
        press("C")
    elif ch and ch in "0123456789.+-*/()%^":
        expr[0] += ch
        update()
    else:
        return False
    return True


win.connect("key-press-event", key)
p = Gtk.CssProvider()
p.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
win.add(box)
win.show_all()
Gtk.main()
EOF

# ----------------------------------------------------------- update check
# Settings > About > Check for updates, and once per start-up (quietly).
# The newest version number lives next to the downloads on archive.org.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-update <<'EOF'
#!/bin/sh
# cherrystone-update [--quiet]: is there a newer Cherrystone?
mine="$(cat /etc/cherrystone-version 2>/dev/null)"
latest="$(wget -q -T 15 -O - https://archive.org/download/cherrystone/version.txt 2>/dev/null | head -n1 | tr -dc 0-9)"
if [ -z "$latest" ]; then
	[ "$1" = --quiet ] || notify-send -i cherrystone "Updates" "Couldn't check. Are you online?"
	exit 0
fi
if [ -n "$mine" ] && [ "$latest" -gt "$mine" ]; then
	( a="$(notify-send -i cherrystone -t 0 "A new Cherrystone is out" \
		"Download it, write it to your USB stick, and start from it. Your saved stuff stays." \
		-A get="Download")"
	  [ "$a" = get ] && cherrystone-browser https://archive.org/details/cherrystone ) &
else
	[ "$1" = --quiet ] || notify-send -i cherrystone "Updates" "You have the newest Cherrystone."
fi
EOF

# ================================================================ the clock
# Secure websites (https) check the date. An old computer whose clock
# battery has died starts up in 2009 or so, and then every site says its
# certificate is wrong. So a clock that's older than this Cherrystone is
# moved up to the day it was made, and the real time comes from the
# internet as soon as you're online.
makefile root:root 0755 "$tmp"/etc/local.d/cherrystone-clock.start <<'EOF'
#!/bin/sh
built="$(cat /etc/cherrystone-version 2>/dev/null)"
case "$built" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) exit 0 ;; esac
if [ "$(date +%Y%m%d)" -lt "$built" ]; then
	date -s "$(echo "$built" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/') 12:00:00" >/dev/null 2>&1
fi
exit 0
EOF
mkdir -p "$tmp"/etc/NetworkManager/dispatcher.d
makefile root:root 0755 "$tmp"/etc/NetworkManager/dispatcher.d/50-cherrystone-time <<'EOF'
#!/bin/sh
# Just got online: set the clock from the internet
case "$2" in
up|connectivity-change)
	(ntpd -n -q -p pool.ntp.org >/dev/null 2>&1 ||
	 ntpd -n -q -p time.cloudflare.com >/dev/null 2>&1) & ;;
esac
exit 0
EOF

# ======================================================= Chromebook keyboard
# On a Chromebook (also with MrChromebox's firmware) the top row sends
# F1-F10 and there's no Home, End, Page Up/Down or Delete. This makes them
# work like on ChromeOS: the top row does what its pictures say, and
# Search+arrows / Search+Backspace give the missing keys (Search+top row:
# the real F1-F10). A quick tap on Search still opens the apps.
# Other computers: nothing happens.
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-chromebook-keys <<'EOF'
#!/bin/sh
[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" = Google ] || exit 0
command -v keyd >/dev/null 2>&1 || exit 0

# What each top-row key is, left to right. Newer Chromebooks say so
# themselves; older ones all have the classic row.
map=""
for f in /sys/bus/serio/devices/*/function_row_physmap /sys/devices/platform/i8042/serio*/function_row_physmap; do
	[ -r "$f" ] && { map="$(cat "$f")"; break; }
done
what() {
	c="$(echo "$1" | tr a-f A-F)"
	[ ${#c} -eq 4 ] && c="${c#E0}"
	case "$c" in
	EA) echo A-left ;;          # back (in the browser)
	E9) echo A-right ;;         # forward
	E7) echo f5 ;;              # refresh
	91) echo f11 ;;             # full screen
	92) echo leftmeta ;;        # overview: the apps
	93) echo sysrq ;;           # screenshot
	94) echo brightnessdown ;;
	95) echo brightnessup ;;
	97) echo kbdillumdown ;;
	98) echo kbdillumup ;;
	9A) echo playpause ;;
	9B) echo micmute ;;
	A0) echo mute ;;
	AE) echo volumedown ;;
	B0) echo volumeup ;;
	esac
}
mkdir -p /etc/keyd
{
	echo "# Written by cherrystone-chromebook-keys at startup"
	echo "[ids]"
	echo "0001:0001"
	echo
	echo "[main]"
	i=1
	if [ -n "$map" ]; then
		for code in $map; do
			k="$(what "$code")"
			[ -n "$k" ] && echo "f$i = $k"
			i=$((i + 1))
		done
	else
		for k in A-left A-right f5 f11 leftmeta brightnessdown brightnessup mute volumedown volumeup; do
			echo "f$i = $k"
			i=$((i + 1))
		done
	fi
	echo "leftmeta = overload(search, leftmeta)"
	echo
	echo "[search:M]"
	echo "up = pageup"
	echo "down = pagedown"
	echo "left = home"
	echo "right = end"
	echo "backspace = delete"
	i=1
	while [ $i -le 10 ]; do echo "f$i = f$i"; i=$((i + 1)); done
} > /etc/keyd/default.conf
rc-service keyd start >/dev/null 2>&1 || keyd >/dev/null 2>&1 &
exit 0
EOF
makefile root:root 0755 "$tmp"/etc/local.d/chromebook-keys.start <<'EOF'
#!/bin/sh
exec /usr/local/sbin/cherrystone-chromebook-keys
EOF
