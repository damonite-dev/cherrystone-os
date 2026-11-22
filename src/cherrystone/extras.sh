#!/bin/sh
# More Cherrystone, sourced by rootfs-config.sh after features.sh (same $tmp,
# $BRAND, helpers): the home page and its
# tiles, the sign-in screen and guest mode, the keyboard shortcut overlay,
# the session watcher (offline, low battery, USB sticks), Bluetooth, and the
# startup sound.

mkdir -p "$tmp"/usr/share/cherrystone "$tmp"/usr/local/sbin "$tmp"/usr/local/bin \
	"$tmp"/usr/share/applications "$tmp"/etc/skel/.config/cherrystone \
	"$tmp"/etc/skel/Downloads

# ================================================================ home page

# Default tiles: "Name|letter|colour|address|icon" (the letter and colour are
# used when there's no icon). People can change theirs in
# Settings > Home page tiles (or "Edit tiles" on the home page).
makefile root:root 0644 "$tmp"/usr/share/cherrystone/tiles-normal <<'EOF'
Gmail|M|#3b6fd6|https://mail.google.com|gmail
YouTube|&#9654;|#d81e3c|https://www.youtube.com|youtube
Docs|D|#2e9e5b|https://docs.google.com|google-docs
Drive|&#9650;|#e0a020|https://drive.google.com|google-drive
Calendar|31|#3b6fd6|https://calendar.google.com|calendar
Maps|&#9673;|#2e9e5b|https://maps.google.com|google-maps
News|N|#5a5a64|https://news.google.com|com.gitlab.newsflash
Wikipedia|W|#5a5a64|https://www.wikipedia.org|wikipedia
EOF
makefile root:root 0644 "$tmp"/usr/share/cherrystone/tiles-lite <<'EOF'
Wikipedia|W|#5a5a64|https://en.m.wikipedia.org
News (NPR)|N|#3b6fd6|https://text.npr.org
CNN Lite|C|#d81e3c|https://lite.cnn.com
Weather|&#9728;|#e0a020|https://wttr.in
Hacker News|Y|#e06a20|https://news.ycombinator.com
Reddit|R|#d8501e|https://old.reddit.com
EOF

# Writes ~/.local/share/cherrystone/home.html from the tiles, with an
# "offline" bar when there's no network. Run at sign-in, when the tiles
# change and when the network comes or goes. Plain HTML + CSS 2 so NetSurf
# shows it too.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-home <<'EOF'
#!/bin/sh
mode="$(cherrystone-mode)"
tiles=~/.config/cherrystone/tiles-$mode
[ -f "$tiles" ] || { mkdir -p ~/.config/cherrystone; cp /usr/share/cherrystone/tiles-$mode "$tiles"; }
out=~/.local/share/cherrystone/home.html
mkdir -p "${out%/*}"
if [ "$mode" = lite ]; then
	search="https://www.google.com/search"
	hint="Lite mode: simple websites work best. For YouTube, Gmail and other big sites, restart and pick Normal."
else
	search="https://www.google.com/search"
	hint="Windows key or the cherry: all apps &middot; Click the clock: Wi-Fi, volume and more &middot; Ctrl+Alt+/ : shortcuts"
fi
name="$(cat ~/.config/cherrystone/name 2>/dev/null)"
[ "$USER" = guest ] && name=""
name="$(printf '%s' "$name" | tr -d '"<>&\')"
title=Cherrystone
[ -n "$name" ] && title="Hi, $name"
wall="$(cat ~/.config/cherrystone/wallpaper 2>/dev/null)"
bg=""
[ -f "$wall" ] && bg="background: #1d0a10 url('file://$wall') center / cover fixed;"
offline=""
case "$(nmcli -t -f STATE general 2>/dev/null)" in
	connected|connecting|"") ;;
	*) offline=1 ;;
esac
# HTML-escape (letters may already be entities like &#9654;, so not &)
esc() { printf '%s' "$1" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
{
cat <<HTML
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Cherrystone</title>
<style>
body { background: #ffffff; color: #202124; font-family: Cantarell, "DejaVu Sans", sans-serif;
       margin: 0; text-align: center; $bg }
/* a soft cherry glow at the top so the page doesn't feel empty */
.top { background: #d81e3c; color: #ffffff; padding: 1px 0 28px; }
.top .date { color: #fbe3e8; }
.wall .top { background: #d81e3c; }
.wall .wrap { background: rgba(255, 255, 255, 0.94); width: 680px; margin: 30px auto; border-radius: 0;
              padding: 6px 0 4px; }
.date { color: #5f6368; font-size: 14px; margin: -14px 0 20px; }
.off { background: #d81e3c; color: #fff; padding: 9px; font-size: 14px; }
.off a { color: #fff; font-weight: bold; margin-left: 10px; }
.logo { margin-top: 36px; width: 48px; height: 48px; padding: 8px; background: #ffffff; }
h1 { font-weight: 300; font-size: 34px; margin: 6px 0 22px; letter-spacing: -0.5px; }
input { width: 480px; padding: 12px 18px; font-size: 15px; color: #202124;
        background: #f1f3f4; border: 1px solid #f1f3f4; border-radius: 0; outline: none;
        box-shadow: none; }
input { background: #ffffff; border-color: #ffffff; }
input:focus { background: #ffffff; border-color: #ffffff; outline: 3px solid #b3122f; }
/* Flat colour tiles: icon top left, name bottom left */
.apps { width: 600px; margin: 26px auto 0; text-align: left; }
a.app { display: inline-block; position: relative; width: 140px; height: 104px; margin: 0 6px 6px 0;
        color: #ffffff; text-decoration: none; font-size: 15px; vertical-align: top;
        transition: opacity 150ms ease-out; }
a.app:hover, a.app:focus { opacity: 0.85; outline: 3px solid #202124; outline-offset: -3px; }
a.app .t { position: absolute; left: 10px; bottom: 8px; right: 8px; }
/* alive in motion: the tiles turn in one after another (short, so old PCs don't wait) */
@keyframes in { from { opacity: 0; transform: translateX(24px); } to { opacity: 1; transform: none; } }
a.app { animation: in 260ms ease-out both; }
a.app:nth-child(2) { animation-delay: 30ms; } a.app:nth-child(3) { animation-delay: 60ms; }
a.app:nth-child(4) { animation-delay: 90ms; } a.app:nth-child(5) { animation-delay: 120ms; }
a.app:nth-child(6) { animation-delay: 150ms; } a.app:nth-child(7) { animation-delay: 180ms; }
a.app:nth-child(n+8) { animation-delay: 210ms; }
.i { position: absolute; left: 10px; top: 10px; width: 36px; height: 36px; line-height: 36px;
     font-size: 30px; font-weight: 300; color: #ffffff; text-align: left; }
.hint { color: #5f6368; font-size: 12px; margin: 30px 0 8px; }
.edit { font-size: 12px; }
.edit a { color: #5f6368; }
/* Stony at the very bottom, in the middle: click for Cherry Run */
a.stony { position: relative; display: block; width: 36px; margin: 22px auto 14px; text-decoration: none; }
a.stony img { width: 36px; height: 39px; image-rendering: pixelated; display: block;
            transition: transform 150ms ease-out; }
a.stony:hover img, a.stony:focus img { transform: translateY(-4px);
                                   content: url("file:///usr/share/cherrystone/stony/stony-wink-small.png"); }
a.stony span { position: absolute; left: 50%; bottom: 48px; transform: translateX(-50%); white-space: nowrap;
             background: #202124; color: #ffffff; font-size: 12px; padding: 5px 10px; border-radius: 0;
             opacity: 0; transition: opacity 150ms ease-out; pointer-events: none; }
a.stony:hover span, a.stony:focus span { opacity: 1; }
HTML
[ "$(cat ~/.config/cherrystone/theme 2>/dev/null)" = dark ] && cat <<HTML
body { background-color: #18181a; color: #ececef; }
.hint, .edit a { color: #a0a0a6; }
input { color: #202124; }
.wall .wrap { background: rgba(24, 24, 26, 0.94); }
a.app:hover, a.app:focus { outline-color: #ececef; }
HTML
cat <<HTML
</style></head><body${bg:+ class="wall"}><div class="wrap"><div class="top">
HTML
[ -n "$offline" ] && echo '<div class="off"><img src="file:///usr/share/cherrystone/stony/stony-sad-small.png" alt="" style="height:20px;vertical-align:-5px;margin-right:6px;image-rendering:pixelated">You&#39;re offline.<a href="cherrystone:wifi">Connect to Wi-Fi</a><a href="file:///usr/share/cherrystone/cherry-run.html">Play Cherry Run</a></div>'
cat <<HTML
<img class="logo" src="file:///usr/share/icons/hicolor/128x128/apps/cherrystone.png" alt="">
<h1 id="hi">$title</h1>
<p class="date" id="date"></p>
<script>
var h = new Date().getHours(), n = "$name";
var part = h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
document.getElementById("hi").textContent = n ? part + ", " + n : part;
document.getElementById("date").textContent = new Date().toLocaleDateString(undefined,
  { weekday: "long", day: "numeric", month: "long" });
</script>
<form action="$search" method="get" onsubmit="var v=this.q.value.trim(); if(v.indexOf(' ')<0 &amp;&amp; /^[^\s]+\.[a-z]{2,}(\/.*)?\$/i.test(v)){location.href=(/^https?:/.test(v)?'':'https://')+v; return false;}"><input type="text" name="q" placeholder="Search Google or type a web address" autofocus></form>
</div>
<div class="apps">
HTML
while IFS='|' read -r name letter colour url icon; do
	[ -n "$name" ] && [ -n "$url" ] || continue
	svg="/usr/share/icons/Papirus/64x64/apps/$icon.svg"
	if [ -n "$icon" ] && [ -f "$svg" ]; then
		pic="<img class=\"i\" src=\"file://$svg\" alt=\"\">"
	else
		pic="<span class=\"i\">$(esc "$letter")</span>"
	fi
	echo "<a class=\"app\" href=\"$(esc "$url")\" style=\"background: $(esc "$colour")\">$pic<span class=\"t\">$(esc "$name")</span></a>"
done < "$tiles"
echo "</div>"
echo "<p class=\"hint\">$hint</p>"
[ "$mode" = lite ] || echo '<p class="edit"><a href="cherrystone:tiles">Edit tiles</a> &middot; <a href="file:///usr/share/cherrystone/tour.html">New here? Take the tour</a></p>'
echo '<a class="stony" href="file:///usr/share/cherrystone/cherry-run.html"><span>Play Cherry Run?</span><img src="file:///usr/share/cherrystone/stony/stony-happy-small.png" alt="Stony"></a>'
echo "</div></body></html>"
} > "$out.new" && mv "$out.new" "$out"

# NetSurf's home page setting
ns=~/.config/netsurf/Choices
mkdir -p "${ns%/*}"
touch "$ns"
sed -i '/^homepage_url:/d' "$ns"
echo "homepage_url:file://$out" >> "$ns"
EOF

# Settings > Home page tiles: add, remove, or go back to the defaults
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-tiles <<'EOF'
#!/bin/sh
mode="$(cherrystone-mode)"
tiles=~/.config/cherrystone/tiles-$mode
[ -f "$tiles" ] || cherrystone-home
colours="#3b6fd6 #d81e3c #2e9e5b #e0a020 #8a3bd6 #5a5a64 #e06a20 #1e9ec8"
# cherrystone-tiles add URL [TITLE]: the browser's Ctrl+D
if [ "$1" = add ]; then
	url="$(printf '%s' "$2" | tr -d ' <>"|')"
	case "$url" in http://?*|https://?*) ;; *) notify-send "Home page" "Only web pages can go on the home page."; exit 0 ;; esac
	if awk -F'|' -v u="$url" '$4 == u { f = 1 } END { exit !f }' "$tiles"; then
		notify-send -i cherrystone "Home page" "That page is already on your home page."; exit 0
	fi
	name="$(printf '%s' "${3:-}" | tr -d '<>"&|' | sed 's/ [-|·–—] .*//' | cut -c1-24)"
	[ -n "$name" ] || name="$(printf '%s' "$url" | sed 's#^https*://##; s#^www\.##; s#[/:].*##')"
	letter="$(printf '%s' "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')"
	n="$(wc -l < "$tiles")"
	colour="$(echo $colours | cut -d' ' -f$(( n % 8 + 1 )))"
	echo "$name|$letter|$colour|$url" >> "$tiles"
	cherrystone-home
	notify-send -i cherrystone "Added to your home page" "$name"
	exit 0
fi
exec cherrystone-ui tiles
EOF

# cherrystone: links (from the home page) open Cherrystone things. Only these
# two, so a web page can't use it to run anything else.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-url <<'EOF'
#!/bin/sh
case "$1" in
	cherrystone:wifi*) exec cherrystone-wifi ;;
	cherrystone:tiles*) exec cherrystone-tiles ;;
	cherrystone:clear-history*)
		: > "$HOME/.local/share/cherrystone/history.js"
		notify-send -i cherrystone "History cleared" "" ;;
esac
EOF
makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-url.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Cherrystone
Exec=cherrystone-url %u
Icon=cherrystone
NoDisplay=true
MimeType=x-scheme-handler/cherrystone;
EOF
# Default apps: cherrystone: links, folders open in Files
makefile root:root 0644 "$tmp"/etc/skel/.config/mimeapps.list <<'EOF'
[Default Applications]
x-scheme-handler/cherrystone=cherrystone-url.desktop
inode/directory=pcmanfm.desktop
EOF

# ======================================================= sign-in and guest

# Checks the cherrystone user's password (read from stdin). Exit 0 = right,
# or no password is set.
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-checkpass <<'EOF'
#!/bin/sh
IFS= read -r pw || pw=""
hash="$(awk -F: '$1 == "cherrystone" { print $2 }' /etc/shadow)"
[ -z "$hash" ] && exit 0
case "$hash" in '$'*) ;; *) exit 1 ;; esac
id="$(echo "$hash" | cut -d'$' -f2)"
salt="$(echo "$hash" | cut -d'$' -f3)"
case "$id" in 1) m=md5 ;; 5) m=sha256 ;; 6) m=sha512 ;; *) exit 1 ;; esac
sleep 1   # slows down guessing
[ "$(printf '%s\n' "$pw" | cryptpw -P 0 -m "$m" -S "$salt")" = "$hash" ]
EOF

# "Browse as guest": the next session (after this one ends) is a guest one
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-guest <<'EOF'
#!/bin/sh
touch /run/cherrystone-guest
EOF

# The sign-in screen: your picture and name, your password if you set one,
# and "Browse as guest". Shown when Cherrystone starts and after signing out.
makefile root:root 0644 "$tmp"/usr/share/cherrystone/signin.css <<'EOF'
window, dialog, .background { background-color: #2a0e16; color: #ffffff; }
button { background: #3d1822; color: #ffffff; border: 1px solid #4a2a32;
         box-shadow: none; text-shadow: none; padding: 8px 18px; }
button:hover, button:focus { background: #d81e3c; border-color: #d81e3c; }
entry { background: #3d1822; color: #ffffff; border: 1px solid #4a2a32; padding: 6px; }
entry:focus { border-color: #d81e3c; }
EOF
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-signin <<'EOF'
#!/usr/bin/env python3
# Cherrystone sign-in screen:
# your picture with your name and password under it in the middle, Browse
# as Guest and Shut down along the bottom, the time and battery in the
# top-right corner. Exits 0 when you've signed in.
import os
import subprocess
import time

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

GLib.set_prgname("CherrySignin")   # window class Cherry*: the window manager focuses it
HOME = os.path.expanduser("~")
CHECK = ["doas", "/usr/local/sbin/cherrystone-checkpass"]


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def password_ok(pw):
    return subprocess.run(CHECK, input=(pw + "\n").encode(),
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def battery():
    base = "/sys/class/power_supply"
    try:
        for d in sorted(os.listdir(base)):
            if d.startswith("BAT"):
                cap = read(f"{base}/{d}/capacity")
                if cap:
                    plug = " ⚡" if read(f"{base}/{d}/status") == "Charging" else ""
                    return f"{cap}%{plug}"
    except OSError:
        pass
    return ""


CSS = b"""
/* One solid cherry block, big light name: readable on any wallpaper */
.pod { background-color: #d81e3c; padding: 30px 40px 24px; }
.name { color: #ffffff; font-size: 26pt; font-weight: 300; }
.oops { color: #ffd2d9; font-size: 10pt; }
.pod entry { background: #ffffff; color: #202124; border: 2px solid #ffffff; border-radius: 0;
             padding: 6px 12px; box-shadow: none; }
.pod entry:focus { border-color: #202124; }
button.go { background: #ffffff; color: #d81e3c; border: none; border-radius: 0; font-weight: bold;
            padding: 6px 16px; box-shadow: none; text-shadow: none; }
button.go:hover, button.go:focus { background: #fde4e8; }
.bar { background-color: rgba(0, 0, 0, 0.45); padding: 4px 8px; }
.bar button { background: transparent; color: #ffffff; border: none; border-radius: 0;
              box-shadow: none; text-shadow: none; padding: 6px 12px; }
.bar button:hover, .bar button:focus { background: rgba(255, 255, 255, 0.14); }
.status { color: #ffffff; font-size: 11pt; background-color: rgba(0, 0, 0, 0.45);
          padding: 5px 12px; border-bottom-left-radius: 0; }
"""


class SignIn(Gtk.Window):
    def __init__(self):
        super().__init__(title="Sign in")
        self.signed_in = False
        self.set_decorated(False)
        self.connect("delete-event", lambda *a: True)        # Alt+F4 does nothing
        screen = self.get_screen()
        geo = Gdk.Display.get_default().get_primary_monitor() or Gdk.Display.get_default().get_monitor(0)
        geo = geo.get_geometry()
        w, h = geo.width, geo.height
        self.set_default_size(w, h)
        self.move(0, 0)

        style = Gtk.CssProvider()
        style.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(screen, style, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

        overlay = Gtk.Overlay()
        self.add(overlay)

        # Background: your wallpaper, or plain cherry
        wall = read(HOME + "/.config/cherrystone/wallpaper")
        if not os.path.isfile(wall):
            wall = "/usr/share/backgrounds/cherrystone/blossom-light.png"
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file(wall)
            scale = max(w / pb.get_width(), h / pb.get_height())
            pb = pb.scale_simple(max(w, int(pb.get_width() * scale + 1)),
                                 max(h, int(pb.get_height() * scale + 1)), GdkPixbuf.InterpType.BILINEAR)
            # crop to exactly the screen, so the window is exactly the screen
            pb = pb.new_subpixbuf((pb.get_width() - w) // 2, (pb.get_height() - h) // 2, w, h)
            bg = Gtk.Image.new_from_pixbuf(pb)
        except GLib.Error:
            bg = Gtk.Box()
            bg.set_size_request(w, h)
        overlay.add(bg)

        # The pod: picture, name, password
        pod = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pod.get_style_context().add_class("pod")
        pod.set_halign(Gtk.Align.CENTER)
        pod.set_valign(Gtk.Align.CENTER)
        pic = HOME + "/.face"
        if not os.path.isfile(pic):
            pic = "/usr/share/icons/hicolor/128x128/apps/cherrystone.png"
        try:
            face = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(pic, 112, 112, True))
        except GLib.Error:
            face = Gtk.Image.new_from_icon_name("avatar-default", Gtk.IconSize.DIALOG)
        # the cherry logo would vanish on the cherry block: only a real picture shows
        if os.path.isfile(HOME + "/.face"):
            pod.pack_start(face, False, False, 0)
        name = Gtk.Label(label=read(HOME + "/.config/cherrystone/name") or "Cherrystone")
        name.get_style_context().add_class("name")
        pod.pack_start(name, False, False, 0)

        self.has_password = not password_ok("")
        row = Gtk.Box(spacing=6)
        if self.has_password:
            self.entry = Gtk.Entry()
            self.entry.set_visibility(False)
            self.entry.set_placeholder_text("Password")
            self.entry.set_width_chars(18)
            self.entry.connect("activate", self.sign_in)
            row.pack_start(self.entry, True, True, 0)
            go = Gtk.Button(label="→")
        else:
            self.entry = None
            go = Gtk.Button(label="Sign in  →")
        go.get_style_context().add_class("go")
        go.connect("clicked", self.sign_in)
        row.pack_start(go, not self.has_password, not self.has_password, 0)
        pod.pack_start(row, False, False, 4)
        self.oops = Gtk.Label(label="")
        self.oops.get_style_context().add_class("oops")
        pod.pack_start(self.oops, False, False, 0)
        overlay.add_overlay(pod)
        self.focus_me = self.entry or go

        # Bottom bar: Browse as Guest, Shut down
        bar = Gtk.Box(spacing=4)
        bar.get_style_context().add_class("bar")
        bar.set_valign(Gtk.Align.END)
        bar.set_halign(Gtk.Align.FILL)
        guest = Gtk.Button(label="Browse as Guest")
        guest.connect("clicked", self.guest)
        bar.pack_start(guest, False, False, 0)
        off = Gtk.Button(label="Shut down")
        off.connect("clicked", lambda *a: subprocess.run(["doas", "/sbin/poweroff"]))
        bar.pack_end(off, False, False, 0)
        overlay.add_overlay(bar)

        # Top-right corner: battery and the time
        self.status = Gtk.Label()
        self.status.get_style_context().add_class("status")
        self.status.set_halign(Gtk.Align.END)
        self.status.set_valign(Gtk.Align.START)
        overlay.add_overlay(self.status)
        self.tick()
        GLib.timeout_add_seconds(5, self.tick)

    def tick(self):
        bat = battery()
        self.status.set_text((bat + "    " if bat else "") + time.strftime("%H:%M"))
        return True

    def fade_out(self):
        """Fade away into your desktop (needs Animations on; otherwise it just closes)."""
        self.signed_in = True
        steps = {"n": 0}

        def step():
            steps["n"] += 1
            self.set_opacity(max(0.0, 1 - steps["n"] / 12.0))
            if steps["n"] >= 12:
                Gtk.main_quit()
                return False
            return True
        GLib.timeout_add(25, step)

    def sign_in(self, *args):
        if not self.has_password:
            self.fade_out()
            return
        self.oops.set_text("")
        self.entry.set_sensitive(False)
        GLib.idle_add(self.check)

    def check(self):
        if password_ok(self.entry.get_text()):
            self.fade_out()
        else:
            self.entry.set_text("")
            self.entry.set_sensitive(True)
            self.entry.grab_focus()
            self.oops.set_text("That's not the password. Try again.")
        return False

    def guest(self, *args):
        if subprocess.run(["doas", "/usr/local/sbin/cherrystone-guest"]).returncode == 0:
            # The session ends and comes back as a guest one; wait for that
            # rather than letting the browser start meanwhile
            subprocess.run(["openbox", "--exit"])
            time.sleep(60)


win = SignIn()
win.show_all()
win.present()
win.focus_me.grab_focus()
Gtk.main()
# 0 only when you've really signed in (the session asks again otherwise)
raise SystemExit(0 if win.signed_in else 1)
EOF

# Settings > Your name and picture (shown on the sign-in screen)
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-profile <<'EOF'
#!/bin/sh
# Settings > Name and picture (part of cherrystone-ui)
exec cherrystone-ui profile
EOF

# ==================================================== keyboard shortcuts

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-shortcuts <<'EOF'
#!/bin/sh
# The keyboard shortcuts list (Ctrl+Alt+/) (part of cherrystone-ui)
exec cherrystone-ui shortcuts
EOF
echo "Shortcuts|preferences-desktop-keyboard-shortcuts|cherrystone-shortcuts" >> "$tmp"/usr/share/cherrystone/apps

# ============================================== session watcher

# One small background loop: tells you when the network drops (with a
# Connect button), warns when the battery is low and shuts down safely
# before it runs out, and offers to open USB sticks when plugged in.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-watch <<'EOF'
#!/bin/sh
media="/run/media/$USER"
list_media() { ls -1 "$media" 2>/dev/null | sort; }
known="$(list_media)"
net=""; warned=""; critical_since=""; saver=""; memwarned=""
dl="$HOME/Downloads"
list_dl() { ls -1 "$dl" 2>/dev/null | grep -v -e '\.wkdownload$' -e '\.part$' -e '\.download$' | sort; }
dl_known="$(list_dl)"; dl_wait=""
tick=0
while sleep 3; do
	tick=$((tick + 1))

	# Finished downloads (the browser saves them to Downloads): a popup once
	# a new file has stopped growing
	dl_now="$(list_dl)"
	printf '%s\n' "$dl_now" | while IFS= read -r f; do
		[ -n "$f" ] || continue
		printf '%s\n' "$dl_known" | grep -qxF "$f" && continue
		size="$(stat -c %s "$dl/$f" 2>/dev/null)"
		if printf '%s\n' "$dl_wait" | grep -qxF "$size/$f"; then
			( a="$(notify-send -a Downloads -i folder-download -t 15000 "Download finished" "$f" \
				-A open=Open -A folder="Show in Files")"
			  case "$a" in open) xdg-open "$dl/$f" ;; folder) pcmanfm "$dl" ;; esac ) &
			echo "done:$f"
		else
			echo "wait:$size/$f"
		fi
	done > /tmp/cherrystone-dl.$$
	dl_wait="$(sed -n 's/^wait://p' /tmp/cherrystone-dl.$$)"
	dl_known="$(printf '%s\n%s\n' "$dl_known" "$(sed -n 's/^done://p' /tmp/cherrystone-dl.$$)" | sed '/^$/d')"
	rm -f /tmp/cherrystone-dl.$$

	# USB sticks / SD cards (mounted by Files in the background)
	now="$(list_media)"
	if [ "$now" != "$known" ]; then
		echo "$now" | while IFS= read -r d; do
			[ -n "$d" ] || continue
			echo "$known" | grep -qxF "$d" && continue
			( a="$(notify-send -a Files -i drive-removable-media -t 15000 \
				"USB drive connected: $d" "Click to open it in Files." -A open=Open)"
			  [ "$a" = open ] && pcmanfm "$media/$d" ) &
		done
		known="$now"
	fi

	# Network, every 9 seconds (first check after ~20 s, to let Wi-Fi connect)
	if [ $((tick % 3)) = 0 ] && [ "$tick" -ge 7 ]; then
		case "$(nmcli -t -f STATE general 2>/dev/null)" in
			connected) state=on ;;
			connecting) state="$net" ;;
			*) state=off ;;
		esac
		if [ -n "$state" ] && [ "$state" != "$net" ]; then
			cherrystone-home
			if [ "$state" = off ]; then
				( a="$(notify-send -a Network -i network-offline -t 15000 "You're offline" \
					"Click to connect to Wi-Fi." -A wifi="Connect to Wi-Fi")"
				  [ "$a" = wifi ] && cherrystone-wifi ) &
			fi
			net="$state"
		fi
	fi

	# Memory, every 15 seconds: warn before things start to crawl
	if [ $((tick % 5)) = 0 ]; then
		avail="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
		if [ "${avail:-999}" -lt 120 ] && [ -z "$memwarned" ]; then
			memwarned=1
			notify-send -u critical -a Memory -i dialog-warning "This computer is running out of memory" \
				"Close some tabs or apps to speed things up."
		elif [ "${avail:-0}" -gt 250 ]; then
			memwarned=""
		fi
	fi

	# Updates: once, about 2 minutes after starting (only says something
	# if there is a new Cherrystone)
	[ "$tick" = 40 ] && cherrystone-update --quiet &

	# Battery, every 30 seconds
	if [ $((tick % 10)) = 0 ]; then
		for b in /sys/class/power_supply/BAT*; do
			[ -r "$b/capacity" ] || continue
			cap="$(cat "$b/capacity")"; st="$(cat "$b/status" 2>/dev/null)"
			if [ "$st" != Discharging ]; then
				warned=""; critical_since=""
				# Battery saver off again: the screen back to how it was
				if [ -n "$saver" ]; then
					doas /usr/bin/brightnessctl -c backlight -q set "$saver" 2>/dev/null
					saver=""
				fi
				continue
			fi
			# Battery saver: at 20% the screen dims to 40% (if it was brighter)
			if [ "$cap" -le 20 ] && [ -z "$saver" ]; then
				max="$(brightnessctl -c backlight max 2>/dev/null)"; cur="$(brightnessctl -c backlight get 2>/dev/null)"
				if [ "${max:-0}" -gt 0 ] && [ -n "$cur" ]; then
					saver="$(( cur * 100 / max ))%"
					if [ $(( cur * 100 / max )) -gt 40 ]; then
						doas /usr/bin/brightnessctl -c backlight -q set 40%
						notify-send -a Battery -i battery-low "Battery saver is on" \
							"The screen is dimmer to make the battery last. It goes back when you plug in."
					fi
				fi
			fi
			if [ "$cap" -le 4 ]; then
				if [ -z "$critical_since" ]; then
					critical_since="$tick"
					notify-send -u critical -a Battery -i battery-caution "Battery almost empty" \
						"Cherrystone will shut down in 1 minute to keep your stuff safe. Plug in the charger to stop it."
				elif [ $((tick - critical_since)) -ge 20 ]; then
					sync; doas /sbin/poweroff
				fi
			elif [ "$cap" -le 10 ] && [ "$warned" != 10 ]; then
				warned=10
				notify-send -u critical -a Battery -i battery-low "Battery low: $cap%" \
					"Plug in the charger soon."
			elif [ "$cap" -le 20 ] && [ -z "$warned" ]; then
				warned=20
				notify-send -a Battery -i battery-low "Battery at $cap%" ""
			fi
		done
	fi
done
EOF

# ============================================================= Bluetooth

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-bluetooth <<'EOF'
#!/bin/sh
if ! ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then
	exec cherrystone-ui message "Bluetooth" "No Bluetooth found" "This computer doesn't have Bluetooth, or it's switched off. A small USB Bluetooth adapter works too."
fi
rfkill unblock bluetooth 2>/dev/null
# the service only starts at boot when Bluetooth was there already
doas /sbin/rc-service bluetooth start >/dev/null 2>&1
exec blueman-manager
EOF

# ======================================================== startup sound

# Plays branding/startup.wav when Cherrystone has started, if there is one.
# "touch ~/.config/cherrystone/no-sound" turns it off.
if [ -f "$BRAND"/startup.wav ]; then
	cp "$BRAND"/startup.wav "$tmp"/usr/share/cherrystone/startup.wav
fi
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-chime <<'EOF'
#!/bin/sh
f=/usr/share/cherrystone/startup.wav
[ -f "$f" ] && [ ! -f ~/.config/cherrystone/no-sound ] && exec aplay -q "$f"
EOF
