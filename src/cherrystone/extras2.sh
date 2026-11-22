#!/bin/sh
# Even more Cherrystone, sourced by rootfs-config.sh after extras.sh (same
# $tmp, $BRAND, helpers): Reset, the sign-in clock, the getting-started
# tour, touchpad settings, built-in wallpapers, and
# the shutdown sound.

mkdir -p "$tmp"/usr/share/cherrystone "$tmp"/usr/local/sbin "$tmp"/usr/local/bin \
	"$tmp"/usr/share/applications "$tmp"/etc/X11/xorg.conf.d

# ================================================================== Reset

# Settings > Reset Cherrystone: restarts into recovery, which asks for the
# password and for ERASE before erasing anything (the boot media checks for
# the "reset-requested" note next to the saved stuff).
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-reset-on-restart <<'EOF'
#!/bin/sh
for d in /media/.save /media/.boot/persist; do
	if [ -d "$d/upper" ] && mountpoint -q "${d%/persist}" 2>/dev/null; then
		touch "$d/reset-requested" && sync && exec reboot
	fi
done
exit 1
EOF
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-reset <<'EOF'
#!/bin/sh
# Settings > Reset (a screen in cherrystone-ui)
exec cherrystone-ui reset
EOF
cat >> "$tmp"/etc/doas.d/cherrystone.conf <<'EOF'
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-reset-on-restart
permit nopass cherrystone as root cmd /sbin/rc-service args bluetooth start
permit nopass guest as root cmd /sbin/rc-service args bluetooth start
EOF

# ================================================= getting-started tour

makefile root:root 0644 "$tmp"/usr/share/cherrystone/tour.html <<'EOF'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Getting started</title>
<style>
body { background: #ffffff; color: #202124; font-family: Cantarell, "DejaVu Sans", sans-serif; margin: 0; }
.wrap { width: 640px; margin: 0 auto; padding: 36px 0 48px; }
h1 { font-weight: normal; font-size: 26px; margin: 0 0 6px; }
.sub { color: #5f6368; margin: 0 0 28px; }
.step { background: #f8f9fa; border-left: 3px solid #d81e3c; border-radius: 0 8px 8px 0;
        padding: 14px 18px; margin: 0 0 12px; }
.step b { display: block; font-size: 16px; margin-bottom: 4px; }
.step span { color: #3c4043; font-size: 14px; line-height: 1.5; }
kbd { background: #f1f3f4; border: 1px solid #dadce0; border-radius: 0; padding: 1px 6px;
      font-family: inherit; font-size: 13px; }
a.go { display: inline-block; margin-top: 18px; background: #d81e3c; color: #fff;
       text-decoration: none; padding: 11px 22px; font-size: 15px; border-radius: 0; }
</style></head><body><div class="wrap">
<img src="file:///usr/share/cherrystone/stony/stony-happy.png" alt="" style="width:64px;height:auto;image-rendering:pixelated;float:right;margin:0 0 8px 16px">
<h1>Welcome to Cherrystone</h1>
<p class="sub">Six things worth knowing. It takes a minute.</p>
<div class="step"><b>1. The browser is the computer</b>
<span>Open it from the shelf (the round blue icon next to the cherry). Your apps are websites: they're the tiles on the home page. Every new tab (<kbd>Ctrl+T</kbd>) opens it. Ads are blocked, which keeps pages fast.</span></div>
<div class="step"><b>2. The shelf</b>
<span>Along the bottom. The cherry at the left opens all apps and search (so does the <kbd>Windows</kbd> key); next to it are your pinned apps and open windows. At the right: network, volume, battery, the clock, and your picture (shut down, restart, sign out).</span></div>
<div class="step"><b>3. Click the clock</b>
<span>Quick settings: Wi-Fi, Bluetooth, volume, brightness, notifications, lock, sign out and shut down.</span></div>
<div class="step"><b>4. Make it yours</b>
<span>Settings has Wi-Fi, sound, your name and picture, a password, wallpapers, the home page tiles and more. The rarely needed things are under Advanced.</span></div>
<div class="step"><b>5. Keep your stuff</b>
<span>From a USB stick, Cherrystone forgets everything when it turns off. To keep things: Settings &gt; Save my stuff (a second USB stick), or Install to disk.</span></div>
<div class="step"><b>6. Shortcuts</b>
<span><kbd>Ctrl+Alt+/</kbd> shows every keyboard shortcut. <kbd>Ctrl+Alt+L</kbd> locks the screen.</span></div>
<p class="end"><a class="go" href="file:///home/cherrystone/.local/share/cherrystone/home.html">Start browsing</a>
<img src="file:///usr/share/cherrystone/stony/stony-love-small.png" alt="" style="width:36px;height:auto;image-rendering:pixelated;vertical-align:-10px;margin-left:12px"></p>
</div></body></html>
EOF
echo "Tour|help-browser|cherrystone-browser file:///usr/share/cherrystone/tour.html" \
	>> "$tmp"/usr/share/cherrystone/apps

# ============================================================ touchpad

# Tap to click is on from the start (netbook touchpad buttons are stiff)
makefile root:root 0644 "$tmp"/etc/X11/xorg.conf.d/40-cherrystone-touchpad.conf <<'EOF'
Section "InputClass"
	Identifier "Cherrystone touchpad"
	MatchIsTouchpad "on"
	Driver "libinput"
	Option "Tapping" "on"
	Option "DisableWhileTyping" "on"
EndSection
EOF

# cherrystone-touchpad apply: apply ~/.config/cherrystone/touchpad
# cherrystone-touchpad: Settings > Touchpad
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-touchpad <<'EOF'
#!/bin/sh
conf=~/.config/cherrystone/touchpad
tap=TRUE; natural=FALSE
[ -f "$conf" ] && . "$conf"
apply() {
	xinput list --name-only 2>/dev/null | grep -i -E 'touchpad|synaptics|glidepoint|elan' |
	while IFS= read -r dev; do
		[ "$tap" = TRUE ] && t=1 || t=0
		[ "$natural" = TRUE ] && n=1 || n=0
		xinput set-prop "$dev" "libinput Tapping Enabled" "$t" 2>/dev/null
		xinput set-prop "$dev" "libinput Natural Scrolling Enabled" "$n" 2>/dev/null
	done
}
if [ "$1" = apply ]; then apply; exit 0; fi
if ! xinput list --name-only 2>/dev/null | grep -qi -E 'touchpad|synaptics|glidepoint|elan'; then
	exec cherrystone-ui message "Touchpad" "No touchpad found" "Plug in a mouse, or check the touchpad isn't switched off (often Fn and an F key)."
fi
exec cherrystone-ui touchpad
EOF

# ============================================================ wallpapers

# Built-in wallpapers (smooth gradients, no text, so the sign-in box and
# the home page sit nicely on them) plus small previews for the picker
W="$tmp"/usr/share/backgrounds/cherrystone
mkdir -p "$W"
if command -v magick >/dev/null 2>&1; then
	# Plain background (sign-in, Recovery): a picture rather than a colour,
	# so the sign-in clock can show through
	magick -size 64x64 xc:'#1d0a10' "$tmp/usr/share/backgrounds/cherrystone-plain.png" ||
		echo "warning: could not make the plain background" >&2
	magick -size 64x64 xc:'#f2f2f2' "$tmp/usr/share/backgrounds/cherrystone-white.png" ||
		echo "warning: could not make the white background" >&2
	for spec in "blossom-light:radial-gradient:#fdf1f4-#e9b7c5" \
	            "sky:gradient:#e8f0fe-#aecbfa" \
	            "cherry-night:radial-gradient:#4a1624-#12050a" \
	            "blossom:gradient:#c84a6c-#3a0e1c" \
	            "orchard:radial-gradient:#24452c-#0b170e" \
	            "dusk:gradient:#4a2458-#140a1c" \
	            "midnight:radial-gradient:#22222e-#0a0a10"; do
		name="${spec%%:*}"; fill="${spec#*:}"
		magick -size 1366x768 "$fill" -depth 8 "$W/$name.png" &&
		magick "$W/$name.png" -resize 120x68 "$W/.$name-thumb.png" ||
			echo "warning: could not make the $name wallpaper" >&2
	done
fi

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-wallpaper <<'EOF'
#!/bin/sh
# Settings > Wallpaper (part of cherrystone-ui)
exec cherrystone-ui wallpaper
EOF

# ======================================================== shutdown sound

# Plays branding/shutdown.wav while Cherrystone shuts down or restarts.
# "touch ~/.config/cherrystone/no-sound" (as the cherrystone user) turns it
# off, along with the startup sound.
if [ -f "$BRAND"/shutdown.wav ]; then
	cp "$BRAND"/shutdown.wav "$tmp"/usr/share/cherrystone/shutdown.wav
fi
# cherrystone-power off|restart: every Shut down and Restart button goes
# through this. It covers the screen with a goodbye (black, the cherry,
# "shutting down..." in big light letters), plays the shutdown sound right
# then, and turns the computer off when the sound is done.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-power <<'EOF'
#!/usr/bin/env python3
import os
import subprocess
import sys
import threading

what = sys.argv[1] if len(sys.argv) > 1 else "off"
cmd = ["doas", "/sbin/reboot"] if what == "restart" else ["doas", "/sbin/poweroff"]
SOUND = "/usr/share/cherrystone/shutdown.wav"
quiet = os.path.exists(os.path.expanduser("~/.config/cherrystone/no-sound"))


def finish(*_):
    subprocess.run(["sync"])
    os.execvp(cmd[0], cmd)


def go(*_):
    # start shutting down, but keep the goodbye on screen until the
    # system closes it (otherwise the desktop flashes back for a moment)
    subprocess.run(["sync"])
    subprocess.Popen(cmd)
    return False


try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, GLib, Gtk
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("no screen")
except Exception:
    finish()

css = Gtk.CssProvider()
css.load_from_data(b"""
window.bye { background: #000000; }
.bye label { color: #ffffff; font-size: 34px; font-weight: 300; }
.bye .dots { color: #d81e3c; }
""")
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)

win = Gtk.Window()
win.get_style_context().add_class("bye")
win.set_decorated(False)
win.set_keep_above(True)
win.fullscreen()
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=26)
box.set_halign(Gtk.Align.CENTER)
box.set_valign(Gtk.Align.CENTER)
try:
    from gi.repository import GdkPixbuf
    pic = GdkPixbuf.Pixbuf.new_from_file_at_scale("/usr/share/icons/hicolor/256x256/apps/cherrystone.png", 140, 140, True)
    box.pack_start(Gtk.Image.new_from_pixbuf(pic), False, False, 0)
except Exception:
    pass
row = Gtk.Box()
row.set_halign(Gtk.Align.CENTER)
row.pack_start(Gtk.Label(label="restarting" if what == "restart" else "shutting down"), False, False, 0)
dots = Gtk.Label(label="")
dots.get_style_context().add_class("dots")
dots.set_width_chars(3)
dots.set_xalign(0)
row.pack_start(dots, False, False, 0)
box.pack_start(row, False, False, 0)
win.add(box)
win.connect("delete-event", lambda *_: True)
win.show_all()

n = {"i": 0}


def tick():
    n["i"] = (n["i"] + 1) % 4
    dots.set_text("." * n["i"])
    return True
GLib.timeout_add(400, tick)


def sound():
    if not quiet and os.path.exists(SOUND):
        open("/tmp/cherrystone-chimed", "w").close()      # chime.stop then doesn't play it again
        try:
            subprocess.run(["timeout", "7", "aplay", "-q", SOUND], stderr=subprocess.DEVNULL)
        except OSError:
            pass
    else:
        import time
        time.sleep(1.5)
    GLib.idle_add(go)
GLib.timeout_add(250, lambda: threading.Thread(target=sound, daemon=True).start() and False)
Gtk.main()
EOF

makefile root:root 0755 "$tmp"/etc/local.d/chime.stop <<'EOF'
#!/bin/sh
f=/usr/share/cherrystone/shutdown.wav
[ -f "$f" ] || exit 0
[ -f /tmp/cherrystone-chimed ] && exit 0          # the goodbye screen already played it
[ -f /home/cherrystone/.config/cherrystone/no-sound ] && exit 0
timeout 7 aplay -q "$f" 2>/dev/null
exit 0
EOF

# ======================================================== Recovery app

# Boot menu > Recovery starts this instead of the browser: a repair kit for
# a Cherrystone installed on the computer's disk (or a Save my stuff drive),
# like a recovery USB. The root side (cherrystone-recover) does the work and
# asks for that installation's password before touching its data.

# The boot menu for an installed disk: the USB's menu without "Recovery"
# and without cherrystone.live (used by the installer and Repair)
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-bootcfg <<'EOF'
#!/bin/sh
sed 's/ cherrystone\.live//' /media/.boot/boot/syslinux/syslinux.cfg |
	awk '/^LABEL / { skip = ($2 == "recovery") } !skip'
EOF

makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-recover <<'EOF'
#!/bin/sh
# cherrystone-recover list                  drives: "device|install or save|size"
# cherrystone-recover haspass DEV           exit 0 if it has a password
# cherrystone-recover check|repair|reset|files DEV   (password on stdin)
cmd="$1"; dev="$2"
M=/run/cherrystone-recovery
mkdir -p "$M/probe" "$M/target" "$M/files"
die() { echo "# Error: $*"; echo "ERROR: $*" >&2; exit 1; }

# Drives with Cherrystone stuff on them: installed (ext4 "CHERRYSTONE" with
# /persist) and Save my stuff drives (ext4 "CHERRYSAVE")
list() {
	blkid 2>/dev/null | grep 'TYPE="ext4"' | grep -E 'LABEL="(CHERRYSTONE|CHERRYSAVE)"' |
	while IFS=: read -r d rest; do
		mount -o ro,noload "$d" "$M/probe" 2>/dev/null || continue
		kind=""
		[ -d "$M/probe/persist" ] && kind=install
		echo "$rest" | grep -q 'LABEL="CHERRYSAVE"' && kind=save
		umount "$M/probe"
		[ -n "$kind" ] || continue
		size="$(lsblk -dno SIZE "$d" 2>/dev/null | tr -d ' ')"
		echo "$d|$kind|$size"
	done
}
kind_of() { list | awk -F'|' -v d="$1" '$1 == d { print $2 }'; }
upper_of() { if [ "$1" = install ]; then echo persist/upper; else echo upper; fi; }

roothash() {
	mount -o ro,noload "$dev" "$M/probe" 2>/dev/null || return 0
	awk -F: '$1 == "root" { print $2 }' "$M/probe/$(upper_of "$kind")/etc/shadow" 2>/dev/null
	umount "$M/probe"
}
pw_ok() {
	case "$2" in '$'*) ;; *) return 1 ;; esac
	id="$(echo "$2" | cut -d'$' -f2)"; salt="$(echo "$2" | cut -d'$' -f3)"
	case "$id" in 1) m=md5 ;; 5) m=sha256 ;; 6) m=sha512 ;; *) return 1 ;; esac
	[ "$(printf '%s\n' "$1" | cryptpw -P 0 -m "$m" -S "$salt")" = "$2" ]
}
need_password() {
	hash="$(roothash)"
	[ -n "$hash" ] || return 0
	IFS= read -r pw || pw=""
	sleep 1
	pw_ok "$pw" "$hash" || die "That's not the password for that Cherrystone."
}
unmount_dev() {
	for m in $(awk -v d="$dev" '$1 == d { print $2 }' /proc/mounts); do umount "$m" 2>/dev/null; done
}

case "$cmd" in list) list; exit 0 ;; esac
[ -b "$dev" ] || die "no such drive"
kind="$(kind_of "$dev")"
[ -n "$kind" ] || die "$dev doesn't have Cherrystone on it"

case "$cmd" in
haspass)
	[ -n "$(roothash)" ] ;;
check)
	need_password ;;
files)
	need_password
	unmount_dev
	mount -o ro,noload "$dev" "$M/files" || die "couldn't open the drive"
	echo "$M/files/$(upper_of "$kind")/home/cherrystone" ;;
reset)
	need_password
	unmount_dev
	mount -t ext4 "$dev" "$M/target" || die "couldn't open the drive"
	u="$(upper_of "$kind")"
	rm -rf "$M/target/$u" "$M/target/${u%upper}work"
	mkdir -p "$M/target/$u" "$M/target/${u%upper}work"
	sync; umount "$M/target" ;;
repair)
	[ "$kind" = install ] || die "only an installed Cherrystone can be repaired"
	need_password
	case "$dev" in
		/dev/nvme*|/dev/mmcblk*) disk="${dev%p[0-9]*}" ;;
		*) disk="$(echo "$dev" | sed 's/[0-9]*$//')" ;;
	esac
	src=/media/.boot
	[ -f "$src/cherrystone.sfs" ] || die "can't find the system image on this USB stick"
	echo 5; echo "# Checking the disk for errors"
	unmount_dev
	e2fsck -f -y "$dev" > /tmp/repair-fsck.log 2>&1
	[ $? -lt 4 ] || die "the disk has errors that couldn't be fixed"
	echo 30; echo "# Putting fresh system files on it (this takes a few minutes)"
	mount -t ext4 "$dev" "$M/target" || die "couldn't open the disk"
	t="$M/target"
	mkdir -p "$t/boot/syslinux" "$t/persist"
	if ! { cp "$src/boot/vmlinuz" "$t/boot/vmlinuz.new" && mv "$t/boot/vmlinuz.new" "$t/boot/vmlinuz" &&
	       cp "$src/boot/initramfs" "$t/boot/initramfs.new" && mv "$t/boot/initramfs.new" "$t/boot/initramfs" &&
	       cp "$src/cherrystone.sfs" "$t/cherrystone.sfs.new" && mv "$t/cherrystone.sfs.new" "$t/cherrystone.sfs"; }; then
		umount "$t"; die "couldn't copy the system files (is the disk full?)"
	fi
	echo 85; echo "# Fixing how it starts"
	for f in ldlinux.c32 libutil.c32 libcom32.c32 menu.c32 vesamenu.c32; do
		cp /usr/share/syslinux/$f "$t/boot/syslinux/"
	done
	cherrystone-bootcfg > "$t/boot/syslinux/syslinux.cfg"
	cp "$src/boot/syslinux/back.png" "$t/boot/syslinux/back.png" 2>/dev/null
	if ! extlinux --install "$t/boot/syslinux" >/dev/null 2>&1; then
		umount "$t"; die "couldn't fix the boot loader"
	fi
	dd if=/usr/share/syslinux/mbr.bin of="$disk" bs=440 count=1 conv=notrunc 2>/dev/null
	# UEFI computers start from the CHERRYBOOT partition: fresh files there too
	esp="$(blkid -t LABEL=CHERRYBOOT -o device 2>/dev/null | grep "^$disk" | head -n1)"
	[ -n "$esp" ] && cherrystone-efiboot "$esp"
	echo 95; echo "# Finishing"
	sync; umount "$t"
	echo 100; echo "# Done" ;;
*)
	die "unknown command" ;;
esac
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-recovery <<'EOF'
#!/bin/sh
# The Recovery app. Runs instead of the desktop when started from the boot
# menu's Recovery entry (a screen in cherrystone-ui; the root side,
# cherrystone-recover, does the work).
exec cherrystone-ui recovery
EOF
cat >> "$tmp"/etc/doas.d/cherrystone.conf <<'EOF'
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-recover
EOF

# ======================================= Advanced tools switch, Display

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-linuxapps <<'EOF'
#!/bin/sh
# Settings > Advanced > Advanced tools: Terminal and Task Manager in the launcher
# (and Ctrl+Alt+T). Off unless you want them. (A screen in cherrystone-ui.)
exec cherrystone-ui linuxapps
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-display <<'EOF'
#!/bin/sh
# Settings > Display (part of cherrystone-ui)
exec cherrystone-ui display
EOF

# Files shows your stuff and your USB sticks, not Cherrystone's own drives
# (the stick it runs from, the system image, a Save my stuff drive) or an
# empty floppy drive
mkdir -p "$tmp"/etc/udev/rules.d
makefile root:root 0644 "$tmp"/etc/udev/rules.d/90-cherrystone-hide.rules <<'EOF'
KERNEL=="loop*|zram*|fd*", ENV{UDISKS_IGNORE}="1"
ENV{ID_FS_LABEL}=="CHERRYSTONE|CHERRYSAVE", ENV{UDISKS_IGNORE}="1"
EOF
