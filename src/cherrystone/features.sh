#!/bin/sh
# Cherrystone extras, sourced by rootfs-config.sh (same $tmp, $BRAND, helpers):
# quick settings, Wi-Fi picker, sliders, notification history, lock screen,
# web apps, install to disk, and "Save my stuff".

# =========================================================== quick settings

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-quick <<'EOF'
#!/bin/sh
# Click the clock: quick settings (part of cherrystone-settings). Clicking
# again, pressing Esc or clicking anywhere else closes it.
exec cherrystone-settings quick
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-slider <<'EOF'
#!/bin/sh
# cherrystone-slider volume|brightness (part of cherrystone-ui)
exec cherrystone-ui "slider" "$1"
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-wifi <<'EOF'
#!/bin/sh
# Pick a Wi-Fi network and connect (part of cherrystone-ui)
exec cherrystone-ui wifi
EOF

# ===================================================== notification history

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-notifications <<'EOF'
#!/bin/sh
# Missed notifications and Do not disturb (part of cherrystone-ui)
exec cherrystone-ui notifications
EOF

# ================================================================ lock screen

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-lock <<'EOF'
#!/bin/sh
# Lock the screen. Without a lock password, press Enter to unlock;
# set a password in Settings > Lock password.
pgrep -x i3lock >/dev/null && exit 0
img="/tmp/cherrystone-lock.$(id -u).png"
cherrystone-lockimage "$img" 2>/dev/null && exec i3lock -n -f -i "$img"
exec i3lock -n -c f1f3f4
EOF

# The lock screen's picture, in the sign-in screen's look: your wallpaper,
# picture and name, with room in the middle for i3lock's typing ring.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-lockimage <<'EOF'
#!/usr/bin/env python3
import os, subprocess, sys
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib

HOME = os.path.expanduser("~")
def read(p):
    try:
        return open(p).read().strip()
    except OSError:
        return ""

scr = Gdk.Screen.get_default()
w, h = scr.get_width(), scr.get_height()
css = Gtk.CssProvider()
css.load_from_data(b"""
.pod { background: rgba(255,255,255,0.9); border-radius: 0; padding: 16px 40px; }
.name { font-size: 20px; font-weight: bold; color: #202124; }
.hint { background: rgba(255,255,255,0.9); border-radius: 0; padding: 6px 16px; color: #3c4043; }
""")
Gtk.StyleContext.add_provider_for_screen(scr, css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

win = Gtk.OffscreenWindow()
ov = Gtk.Overlay()
win.add(ov)
wall = read(HOME + "/.config/cherrystone/wallpaper")
if not os.path.isfile(wall):
    wall = "/usr/share/backgrounds/cherrystone/blossom-light.png"
try:
    pb = GdkPixbuf.Pixbuf.new_from_file(wall)
    k = max(w / pb.get_width(), h / pb.get_height())
    pb = pb.scale_simple(max(w, int(pb.get_width() * k + 1)), max(h, int(pb.get_height() * k + 1)),
                         GdkPixbuf.InterpType.BILINEAR)
    bg = Gtk.Image.new_from_pixbuf(pb.new_subpixbuf((pb.get_width() - w) // 2, (pb.get_height() - h) // 2, w, h))
except GLib.Error:
    bg = Gtk.Box()
bg.set_size_request(w, h)
ov.add(bg)

# top and bottom are the same height, so the gap (the ring) is dead centre
ring = min(240, h // 2)
side = max(110, min(150, (h - ring) // 2 - 40))
# The layout box is see-through; only the picture card and the hint are white
pod = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
pod.set_halign(Gtk.Align.CENTER)
pod.set_valign(Gtk.Align.CENTER)
top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
top.set_size_request(300, side)
card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
card.get_style_context().add_class("pod")
card.set_halign(Gtk.Align.CENTER)
card.set_valign(Gtk.Align.END)
pic = HOME + "/.face"
if not os.path.isfile(pic):
    pic = "/usr/share/icons/hicolor/128x128/apps/cherrystone.png"
size = min(80, side - 70)
try:
    face = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(pic, size, size, True))
except GLib.Error:
    face = Gtk.Image.new_from_icon_name("avatar-default", Gtk.IconSize.DIALOG)
card.pack_start(face, False, False, 0)
name = Gtk.Label(label=read(HOME + "/.config/cherrystone/name") or "Cherrystone")
name.get_style_context().add_class("name")
card.pack_start(name, False, False, 0)
top.pack_end(card, False, False, 0)
pod.pack_start(top, False, False, 0)
gap = Gtk.Box()
gap.set_size_request(-1, ring)
pod.pack_start(gap, False, False, 0)
locked = subprocess.run(["doas", "/usr/local/sbin/cherrystone-checkpass"], input=b"\n",
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0
bottom = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
bottom.set_size_request(300, side)
hint = Gtk.Label(label="Locked. Type your password, then press Enter." if locked
                 else "Locked. Press Enter to unlock.")
hint.get_style_context().add_class("hint")
hint.set_halign(Gtk.Align.CENTER)
bottom.pack_start(hint, False, False, 0)
pod.pack_start(bottom, False, False, 0)
ov.add_overlay(pod)

win.show_all()
for _ in range(50):
    while Gtk.events_pending():
        Gtk.main_iteration()
pix = win.get_pixbuf()
if pix is None:
    sys.exit(1)
pix.savev(sys.argv[1], "png", [], [])
EOF

# Sets or removes the password (sign-in, lock screen). Reads the new password
# on stdin; an empty one removes it. The same password locks root too (the
# rescue console on Ctrl+Alt+F2 and the early-boot rescue shell), so it
# can't be got around from there.
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-setpass <<'EOF'
#!/bin/sh
IFS= read -r pw || pw=""
if [ -z "$pw" ]; then
	passwd -d cherrystone >/dev/null
	passwd -d root >/dev/null
else
	printf 'cherrystone:%s\nroot:%s\n' "$pw" "$pw" | chpasswd
fi
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-lockpass <<'EOF'
#!/bin/sh
# Settings > Password (part of cherrystone-ui)
exec cherrystone-ui password
EOF

# =================================================================== web apps

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-webapp <<'EOF'
#!/bin/sh
# Open a web app in the browser
exec cherrystone-browser "$1"
EOF

webapp() { # id name url colour letter
	makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-$1.desktop <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=cherrystone-webapp $3
Icon=${6:-cherrystone-$1}
Categories=Network;
EOF
	echo "$2|${6:-cherrystone-$1}|cherrystone-webapp $3" >> "$tmp"/usr/share/cherrystone/apps
	if command -v magick >/dev/null 2>&1; then
		magick -size 96x96 xc:none -fill "$4" -draw "circle 48,48 48,4" \
			-fill white -font /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf \
			-pointsize 52 -gravity center -annotate +0+2 "$5" -resize 48x48 \
			"$tmp/usr/share/icons/hicolor/48x48/apps/cherrystone-$1.png" ||
			echo "warning: could not make the $2 icon" >&2
	fi
}
webapp youtube "YouTube" "https://www.youtube.com" "#d81e3c" "Y" youtube
webapp gmail "Gmail" "https://mail.google.com" "#3b6fd6" "M" gmail
webapp docs "Docs" "https://docs.google.com" "#2e9e5b" "D" google-docs
webapp wikipedia "Wikipedia" "https://www.wikipedia.org" "#5a5a64" "W" wikipedia

# ===================================================== install to disk

makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-install <<'EOF'
#!/bin/sh
# cherrystone-install /dev/sdX : erase the disk and install Cherrystone on it.
# Prints "# message" lines and percentages (the installer screen shows them).
set -e
die() { echo "# Error: $*"; echo "ERROR: $*" >&2; exit 1; }
disk="$1"
case "$disk" in
	/dev/sd[a-z]|/dev/hd[a-z]|/dev/vd[a-z]) esp="${disk}1"; part="${disk}2" ;;
	/dev/nvme[0-9]n[0-9]|/dev/mmcblk[0-9]) esp="${disk}p1"; part="${disk}p2" ;;
	*) die "$disk is not a whole disk" ;;
esac
[ -b "$disk" ] || die "$disk not found"
boot="$(awk '$2 == "/media/.boot" { print $1 }' /proc/mounts)"
case "$boot" in "$disk"*) die "Cherrystone is running from $disk" ;; esac
src=/media/.boot
[ -f "$src/cherrystone.sfs" ] || die "can't find the Cherrystone system image"

echo 5; echo "# Preparing $disk"
for m in $(awk -v d="$disk" 'index($1, d) == 1 { print $2 }' /proc/mounts); do umount "$m" || true; done
swapoff -a 2>/dev/null || true
dd if=/dev/zero of="$disk" bs=1M count=4 conv=fsync 2>/dev/null
# 1: a small FAT partition for UEFI computers (and Chromebooks with UEFI
# firmware), 2: the system, which older BIOS computers start from directly
printf 'label: dos\nstart=2048, size=128MiB, type=ef\ntype=83, bootable\n' | sfdisk -q "$disk"
sleep 2; mdev -s; [ -b "$part" ] || sleep 3
[ -b "$esp" ] && [ -b "$part" ] || die "the new partitions didn't appear"

echo 15; echo "# Formatting"
# syslinux can't boot from ext4 with the 64bit or metadata_csum features
mkfs.ext4 -q -F -L CHERRYSTONE -O ^64bit,^metadata_csum "$part"
mkfs.vfat -F 32 -n CHERRYBOOT "$esp" >/dev/null
mkdir -p /mnt/cherrystone-install
mount -t ext4 "$part" /mnt/cherrystone-install
t=/mnt/cherrystone-install

echo 25; echo "# Copying Cherrystone (this takes a few minutes)"
mkdir -p "$t/boot/syslinux" "$t/persist"
cp "$src/boot/vmlinuz" "$src/boot/initramfs" "$t/boot/"
cp "$src/cherrystone.sfs" "$t/cherrystone.sfs"

echo 85; echo "# Installing the boot loader"
for f in ldlinux.c32 libutil.c32 libcom32.c32 menu.c32 vesamenu.c32; do
	cp /usr/share/syslinux/$f "$t/boot/syslinux/"
done
cherrystone-bootcfg > "$t/boot/syslinux/syslinux.cfg"
cp "$src/boot/syslinux/back.png" "$t/boot/syslinux/back.png" 2>/dev/null || true
extlinux --install "$t/boot/syslinux" >/dev/null 2>&1
dd if=/usr/share/syslinux/mbr.bin of="$disk" bs=440 count=1 conv=notrunc 2>/dev/null
cherrystone-efiboot "$esp" || die "couldn't set up starting on UEFI computers"

echo 95; echo "# Finishing"
sync
umount "$t"
echo 100; echo "# Done"
EOF

# cherrystone-efiboot PARTITION: put the UEFI boot files (GRUB, its menu,
# the kernel) on an installed computer's CHERRYBOOT partition
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-efiboot <<'EOF'
#!/bin/sh
set -e
esp="$1"; src=/media/.boot; m=/run/cherrystone-esp
efi="$(ls "$src"/boot/grub/disk-*.efi 2>/dev/null | head -n1)"
[ -n "$efi" ] || exit 0          # an older stick without them: BIOS only
mkdir -p "$m"
mount -t vfat "$esp" "$m"
mkdir -p "$m/EFI/BOOT" "$m/boot/grub"
name="$(basename "$efi" | sed 's/^disk-//' | tr '[:lower:]' '[:upper:]')"
cp "$efi" "$m/EFI/BOOT/$name"
cp "$src/boot/grub/disk.cfg" "$m/boot/grub/grub.cfg"
cp "$src/boot/grub/unicode.pf2" "$m/boot/grub/" 2>/dev/null || true
cp -r "$src/boot/grub/theme" "$m/boot/grub/" 2>/dev/null || true
cp "$src/boot/vmlinuz" "$src/boot/initramfs" "$m/boot/"
sync; umount "$m"
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-installer <<'EOF'
#!/bin/sh
# Install Cherrystone on this computer's disk (a screen in cherrystone-ui;
# the work is done by /usr/local/sbin/cherrystone-install)
exec cherrystone-ui install
EOF

# ===================================================== save my stuff

makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-make-save <<'EOF'
#!/bin/sh
# cherrystone-make-save /dev/sdX|/dev/sdXN : erase it and use it to keep
# Cherrystone's settings and files. Copies this session's changes onto it.
set -e
die() { echo "ERROR: $*" >&2; exit 1; }
dev="$1"
[ -b "$dev" ] || die "$dev not found"
boot="$(awk '$2 == "/media/.boot" { print $1 }' /proc/mounts)"
case "$boot" in "$dev"*) die "Cherrystone is running from $dev" ;; esac
for m in $(awk -v d="$dev" 'index($1, d) == 1 { print $2 }' /proc/mounts); do umount "$m" || true; done
target="$dev"
case "$dev" in
	/dev/sd[a-z]|/dev/hd[a-z]|/dev/vd[a-z]|/dev/mmcblk[0-9])
		case "$dev" in /dev/mmcblk*) target="${dev}p1" ;; *) target="${dev}1" ;; esac
		dd if=/dev/zero of="$dev" bs=1M count=4 conv=fsync 2>/dev/null
		printf 'label: dos\nstart=2048, type=83\n' | sfdisk -q "$dev"
		sleep 2; mdev -s; [ -b "$target" ] || sleep 3 ;;
esac
[ -b "$target" ] || die "the new partition didn't appear"
mkfs.ext4 -q -F -L CHERRYSAVE "$target"
mkdir -p /mnt/cherrystone-save
mount -t ext4 "$target" /mnt/cherrystone-save
mkdir -p /mnt/cherrystone-save/upper /mnt/cherrystone-save/work
if [ -d /media/.rw/upper ]; then
	cp -a /media/.rw/upper/. /mnt/cherrystone-save/upper/ 2>/dev/null || true
fi
sync
umount /mnt/cherrystone-save
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-save <<'EOF'
#!/bin/sh
# Settings > Save my stuff (a screen in cherrystone-ui; the work is done by
# /usr/local/sbin/cherrystone-make-save)
exec cherrystone-ui save
EOF

makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-installer.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Cherrystone
Exec=cherrystone-installer
Icon=cherrystone
Categories=System;
EOF
echo "Install|system-software-install|cherrystone-installer" >> "$tmp"/usr/share/cherrystone/apps

# ===================================================== permissions

cat >> "$tmp"/etc/doas.d/cherrystone.conf <<'EOF'
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-setpass
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-install
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-make-save
EOF
