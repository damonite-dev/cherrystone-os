#!/bin/sh
set -e
# Builds the Cherrystone ISO. Runs INSIDE an Alpine environment, as root.
# Don't call this directly: use build.sh (docker) or build-wsl.sh (no docker).
#
# Layout of the ISO:
#   /boot/vmlinuz, /boot/initramfs   kernel + early boot (initramfs-init)
#   /cherrystone.sfs                 the whole system, compressed, read-only
# At boot the image is mounted straight from the media with a RAM-backed
# writable layer on top, so RAM is only used for what is running or changed.

ARCH="${ARCH:-x86_64}"
# Quick test builds (CHERRYSTONE_QUICK=1): downloaded packages are kept for
# next time and the system image is compressed lightly. Same system, just a
# bigger ISO that's much faster to make. Release builds don't set it.
if [ -n "$CHERRYSTONE_QUICK" ]; then
	mkdir -p "/var/cache/cherrystone-apk/$ARCH"
	APKCACHE="--cache-dir /var/cache/cherrystone-apk/$ARCH"
	SQUASH_LEVEL=3
else
	APKCACHE="--no-cache"
	SQUASH_LEVEL=19
fi
ALPINE="${ALPINE:-3.22}"
SRC="${SRC:-/src}"
OUT="${OUT:-/out}"
WORK="${WORK:-/var/tmp/cherrystone-$ARCH}"
MIRROR="${MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
LABEL=CHERRYSTONE          # must match LABEL in initramfs-init
# cherrystone.live: started from the USB stick/CD (an installed disk drops it)
CMDLINE="quiet loglevel=3 vt.global_cursor_default=0 console=tty0 cherrystone.live"
MENU_SECONDS=2             # how long the boot menu waits

R="$WORK/rootfs"
ISO="$WORK/iso"

msg() { echo ">> $*"; }
die() { echo "error: $*" >&2; exit 1; }

case "$ARCH" in
	x86_64) GRUB_FMT=x86_64-efi; GRUB_EFI=bootx64.efi ;;
	x86)    GRUB_FMT=i386-efi;   GRUB_EFI=bootia32.efi ;;
	*) die "unsupported arch '$ARCH' (use x86 or x86_64)" ;;
esac
[ "$(id -u)" = 0 ] || die "must run as root"

unmount_all() {
	for m in "$R/proc" "$R/dev"; do
		if mountpoint -q "$m" 2>/dev/null; then umount "$m"; fi
	done
}
trap unmount_all EXIT
unmount_all
rm -rf "$WORK"
mkdir -p "$R" "$ISO/boot/syslinux" "$ISO/boot/grub" "$ISO/efi/boot" "$OUT"

msg "Installing build tools"
apk add --no-cache --no-progress alpine-keys xorriso squashfs-tools mtools grub grub-efi patch \
	imagemagick font-dejavu >/dev/null

# ---------------------------------------------------------------- system image
msg "Installing packages into the system image ($ARCH, Alpine $ALPINE)"
mkdir -p "$R/etc/apk/keys" "$R/proc" "$R/dev"
if [ -d "/usr/share/apk/keys/$ARCH" ]; then
	cp /usr/share/apk/keys/"$ARCH"/* "$R/etc/apk/keys/"
else
	cp /etc/apk/keys/* "$R/etc/apk/keys/"
fi
printf '%s\n' "$MIRROR/v$ALPINE/main" "$MIRROR/v$ALPINE/community" > "$R/etc/apk/repositories"
mount -t proc proc "$R/proc"
mount --bind /dev "$R/dev"

# "packages" for every ISO, plus "packages-x86_64" etc. for one kind only
PKGS="$(cat "$SRC/packages" "$SRC/packages-$ARCH" 2>/dev/null | sed 's/#.*//' | xargs)"
apk add --root "$R" --initdb --arch "$ARCH" $APKCACHE --no-progress $PKGS

msg "Applying Cherrystone configuration"
sh "$SRC/rootfs-config.sh" "$R" "$SRC/branding"
# The version (the build date): Settings > About, and the update check
date +%Y%m%d > "$R/etc/cherrystone-version"
cp "$R/etc/cherrystone-version" "$OUT/version.txt"
chroot "$R" /bin/sh -e <<'EOF'
adduser -D -s /bin/sh -g Cherrystone cherrystone
passwd -d cherrystone >/dev/null
passwd -d root >/dev/null          # passwordless rescue login on tty2
# "Browse as guest": a second user whose home is wiped every time
# (Alpine has a built-in "guest" account; give it a home and a shell)
if grep -q '^guest:' /etc/passwd; then
	sed -i 's|^guest:\([^:]*\):\([0-9]*\):\([0-9]*\):.*|guest:\1:\2:\3:Guest:/home/guest:/bin/sh|' /etc/passwd
else
	adduser -D -s /bin/sh -g Guest guest
fi
mkdir -p /home/guest
chown guest /home/guest
chmod 700 /home/guest
passwd -d guest >/dev/null
for g in video input audio seat netdev plugdev lp bluetooth; do
	addgroup cherrystone "$g" 2>/dev/null || true
	addgroup guest "$g" 2>/dev/null || true
done
# pick up the Cherrystone icons added after the package triggers ran
gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
gtk-update-icon-cache -q -f -t /usr/share/icons/Papirus || true
EOF
mkdir -p "$R/media/.boot" "$R/media/.ro" "$R/media/.rw" "$R/media/.save"

# ------------------------------------------------------------------ Badwolf
# Badwolf ships with JavaScript off in every new tab (it's privacy-first),
# which breaks most modern sites. Build the same version with JavaScript on
# and Cherrystone's small changes (badwolf-cherrystone.patch: new tabs open
# the home page, the usual browser keys, no JS/IMG buttons), for the target
# arch, and use it instead of the packaged binary (the package still
# provides its icons, translations and dependencies).
# The result is cached in /var/tmp between builds (per patch version).
BW_VER=1.3.0
BW_SHA512=f83884f9a1c4d12d641f68697d7fab7885803975ead6cb78e88b0b8d2f7b6f9da116f72e39f02c47e8dca89e4ced9b932524338a6211c7d4509c12206c10cdeb
BW_REV="$(md5sum "$SRC/badwolf-cherrystone.patch" | cut -c1-8)"
BWC="/var/tmp/cherrystone-badwolf-$BW_VER-$BW_REV-$ARCH"
if [ ! -x "$BWC/badwolf" ]; then
	msg "Building Badwolf with JavaScript on ($ARCH, first time only)"
	BR="$BWC.root"
	rm -rf "$BR"
	mkdir -p "$BR/etc/apk" "$BR/src" "$BR/proc" "$BR/dev"
	cp -r "$R/etc/apk/keys" "$R/etc/apk/repositories" "$BR/etc/apk/"
	apk add --root "$BR" --arch "$ARCH" --initdb --no-cache --no-progress \
		alpine-base build-base webkit2gtk-4.1-dev samurai ed >/dev/null
	# The source is kept in /var/tmp after the first download, so a build
	# still works when the Badwolf site is down
	BWT="/var/tmp/badwolf-$BW_VER.tar.gz"
	if ! { [ -f "$BWT" ] && echo "$BW_SHA512  $BWT" | sha512sum -c - >/dev/null 2>&1; }; then
		for try in 1 2 3; do
			wget -q -O "$BWT.part" "https://hacktivis.me/releases/badwolf-$BW_VER.tar.gz" && break
			sleep 5
		done
		echo "$BW_SHA512  $BWT.part" | sha512sum -c - >/dev/null 2>&1 ||
			die "couldn't download the Badwolf source (or it doesn't match its checksum)"
		mv "$BWT.part" "$BWT"
	fi
	cp "$BWT" "$BR/src/badwolf.tar.gz"
	tar -xzf "$BR/src/badwolf.tar.gz" -C "$BR/src"
	sed -i 's/"enable-javascript-markup", FALSE/"enable-javascript-markup", TRUE/' \
		"$BR/src/badwolf-$BW_VER/config.h"
	grep -q '"enable-javascript-markup", TRUE' "$BR/src/badwolf-$BW_VER/config.h" ||
		die "couldn't turn JavaScript on in Badwolf's config.h"
	patch -d "$BR/src/badwolf-$BW_VER" -p1 < "$SRC/badwolf-cherrystone.patch" >/dev/null ||
		die "badwolf-cherrystone.patch doesn't apply"
	mount -t proc proc "$BR/proc"
	mount --bind /dev "$BR/dev"
	chroot "$BR" /bin/sh -ec "cd /src/badwolf-$BW_VER
		PREFIX=/usr WITH_WEBKITGTK=4.1 ./configure >/dev/null
		samu >/dev/null"
	umount "$BR/proc" "$BR/dev"
	mkdir -p "$BWC"
	cp "$BR/src/badwolf-$BW_VER/badwolf" "$BWC/badwolf"
	rm -rf "$BR"
fi
install -m 0755 "$BWC/badwolf" "$R/usr/bin/badwolf"

# ------------------------------------------------------------ kernel + initramfs
msg "Building initramfs"
KVER="$(ls "$R/lib/modules" | head -n1)"
[ -n "$KVER" ] || die "no kernel modules found in the image"
cp "$SRC/initramfs-init" "$R/tmp/cherrystone-init"
# Filesystems a USB stick may be written with (Rufus ISO mode = FAT32/exFAT)
printf '%s\n' kernel/fs/fat kernel/fs/exfat kernel/fs/nls \
	> "$R/etc/mkinitfs/features.d/cherrystone.modules"
chroot "$R" mkinitfs -i /tmp/cherrystone-init \
	-F "ata base cdrom cherrystone ext4 mmc nvme scsi squashfs usb virtio" \
	-o /tmp/cherrystone-initramfs "$KVER"
cp "$R/boot/vmlinuz-lts" "$ISO/boot/vmlinuz"
mv "$R/tmp/cherrystone-initramfs" "$ISO/boot/initramfs"

# ------------------------------------------------------------------ bootloaders
msg "Setting up bootloaders (BIOS: isolinux, UEFI: grub)"
# Bootloader files for the target arch, unpacked into a scratch root
B="$WORK/bootpkgs"
mkdir -p "$B/etc/apk"
cp -r "$R/etc/apk/keys" "$R/etc/apk/repositories" "$B/etc/apk/"
apk add --root "$B" --initdb --arch "$ARCH" $APKCACHE --no-progress --no-scripts \
	syslinux grub-efi >/dev/null
for f in isohdpfx.bin isolinux.bin ldlinux.c32 libutil.c32 libcom32.c32 menu.c32 vesamenu.c32; do
	cp "$B/usr/share/syslinux/$f" "$ISO/boot/syslinux/$f"
done
# Boot menu background: the cherry and the name on dark cherry, 640x480
magick -size 640x480 radial-gradient:'#3a121c'-'#12050a' \
	\( "$SRC/branding/cherrystone-256.png" -resize 84x84 \) \
	-gravity north -geometry +0+40 -composite \
	-font /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf -pointsize 24 -fill white \
	-annotate +0+134 Cherrystone \
	-font /usr/share/fonts/dejavu/DejaVuSans.ttf -pointsize 13 -fill '#b89aa2' \
	-annotate +0+168 'small. fast. yours.' \
	-alpha off -depth 8 "PNG24:$ISO/boot/syslinux/back.png"
cat > "$ISO/boot/syslinux/syslinux.cfg" <<EOF
UI vesamenu.c32
PROMPT 0
TIMEOUT $((MENU_SECONDS * 10))
MENU RESOLUTION 640 480
MENU BACKGROUND /boot/syslinux/back.png
MENU TITLE
MENU TABMSG Press Tab to change the options
MENU VSHIFT 13
MENU ROWS 5
MENU MARGIN 10
MENU TIMEOUTROW 20
MENU TABMSGROW 26
MENU CMDLINEROW 26
MENU COLOR screen 0 #00000000 #00000000 none
MENU COLOR border 0 #00000000 #00000000 none
MENU COLOR title 0 #00000000 #00000000 none
MENU COLOR unsel 0 #ffe8d8dc #00000000 none
MENU COLOR hotkey 0 #ffffffff #00000000 none
MENU COLOR sel 0 #ffffffff #ffd81e3c none
MENU COLOR hotsel 0 #ffffffff #ffd81e3c none
MENU COLOR timeout_msg 0 #ffb89aa2 #00000000 none
MENU COLOR timeout 0 #ffffffff #00000000 none
MENU COLOR tabmsg 0 #ff8a6a72 #00000000 none
MENU COLOR cmdmark 0 #ffd81e3c #00000000 none
MENU COLOR cmdline 0 #ffffffff #00000000 none
DEFAULT cherrystone

LABEL cherrystone
	MENU LABEL Cherrystone
	KERNEL /boot/vmlinuz
	INITRD /boot/initramfs
	APPEND $CMDLINE

LABEL recovery
	MENU LABEL Recovery (repair an installed Cherrystone)
	KERNEL /boot/vmlinuz
	INITRD /boot/initramfs
	APPEND $CMDLINE cherrystone.recovery
EOF

# ---- grub (UEFI) start: the same look as the BIOS menu above
cat > "$WORK/grub_early.cfg" <<EOF
search --no-floppy --set=root --label "$LABEL"
set prefix=(\$root)/boot/grub
EOF
grub-mkimage \
	--config="$WORK/grub_early.cfg" \
	--directory="$B/usr/lib/grub/$GRUB_FMT" \
	--prefix="/boot/grub" \
	--output="$ISO/efi/boot/$GRUB_EFI" \
	--format="$GRUB_FMT" \
	--compression="xz" \
	all_video disk part_gpt part_msdos linux normal configfile search \
	search_label efi_gop efi_uga fat iso9660 cat echo ls test true help gzio multiboot2 \
	font gfxterm gfxterm_background gfxmenu png

# Theme: dark cherry with the logo above the middle of the screen, the
# entries just below it, the selected one on a cherry-red bar. The picture
# is big and cropped from its middle, so it fits any screen.
T="$ISO/boot/grub/theme"
mkdir -p "$T"
cp /usr/share/grub/unicode.pf2 "$ISO/boot/grub/unicode.pf2"
magick -size 1920x1200 radial-gradient:'#3a121c'-'#12050a' \
	\( "$SRC/branding/cherrystone-256.png" -resize 84x84 \) \
	-gravity north -geometry +0+392 -composite \
	-font /usr/share/fonts/dejavu/DejaVuSans-Bold.ttf -pointsize 24 -fill white \
	-annotate +0+486 Cherrystone \
	-font /usr/share/fonts/dejavu/DejaVuSans.ttf -pointsize 13 -fill '#b89aa2' \
	-annotate +0+520 'small. fast. yours.' \
	-alpha off -depth 8 "PNG24:$T/background.png"
for part in c n s e w ne nw se sw; do
	magick -size 4x4 xc:'#d81e3c' "PNG24:$T/sel_$part.png"
	# the box GRUB shows its messages in (while it loads Cherrystone): the
	# same dark cherry as the background, so it's not a black rectangle
	magick -size 4x4 xc:'#12050a' "PNG24:$T/term_$part.png"
done
cat > "$T/theme.txt" <<'EOF'
title-text: ""
terminal-box: "term_*.png"
terminal-left: "0"
terminal-top: "0"
terminal-width: "100%"
terminal-height: "100%"
terminal-border: "0"
desktop-image: "background.png"
desktop-image-scale-method: "crop"
desktop-image-h-align: "center"
desktop-image-v-align: "center"
desktop-color: "#12050a"
terminal-font: "Unifont Regular 16"
message-font: "Unifont Regular 16"
message-color: "#b89aa2"
+ boot_menu {
	left = 50%-220
	width = 440
	top = 50%-30
	height = 110
	item_font = "Unifont Regular 16"
	item_color = "#e8d8dc"
	selected_item_font = "Unifont Regular 16"
	selected_item_color = "#ffffff"
	selected_item_pixmap_style = "sel_*.png"
	item_height = 28
	item_padding = 14
	item_spacing = 6
	icon_width = 0
	icon_height = 0
	item_icon_space = 0
	scrollbar = false
}
+ label {
	id = "__timeout__"
	text = "Starting in %d seconds"
	left = 0
	width = 100%
	top = 50%+100
	height = 20
	align = "center"
	color = "#b89aa2"
	font = "Unifont Regular 16"
}
+ label {
	text = "Press E to change the options"
	left = 0
	width = 100%
	top = 100%-36
	height = 20
	align = "center"
	color = "#8a6a72"
	font = "Unifont Regular 16"
}
EOF

cat > "$ISO/boot/grub/grub.cfg" <<EOF
set timeout=$MENU_SECONDS
set default=0
# Plain colours, if the screen can't do pictures
set color_normal=white/black
set menu_color_normal=white/black
set menu_color_highlight=white/red
if loadfont /boot/grub/unicode.pf2; then
	set gfxmode=auto
	terminal_output gfxterm
	set theme=/boot/grub/theme/theme.txt
	export theme
fi

menuentry "Cherrystone" {
linux	/boot/vmlinuz $CMDLINE
initrd	/boot/initramfs
}
menuentry "Recovery (repair an installed Cherrystone)" {
linux	/boot/vmlinuz $CMDLINE cherrystone.recovery
initrd	/boot/initramfs
}
EOF
# Installed computers: the same menu from a small FAT partition labelled
# CHERRYBOOT (GRUB can't read the ext4 system partition). The installer
# copies these from the stick.
cat > "$WORK/grub_disk.cfg" <<EOF
search --no-floppy --set=root --label CHERRYBOOT
set prefix=(\$root)/boot/grub
EOF
grub-mkimage \
	--config="$WORK/grub_disk.cfg" \
	--directory="$B/usr/lib/grub/$GRUB_FMT" \
	--prefix="/boot/grub" \
	--output="$ISO/boot/grub/disk-$GRUB_EFI" \
	--format="$GRUB_FMT" \
	--compression="xz" \
	all_video disk part_gpt part_msdos linux normal configfile search \
	search_label efi_gop efi_uga fat cat echo ls test true help gzio \
	font gfxterm gfxterm_background gfxmenu png
sed -e 's/ cherrystone\.live//' "$ISO/boot/grub/grub.cfg" |
	awk '/^menuentry "Recovery/ { skip = 1 } !skip' > "$ISO/boot/grub/disk.cfg"
# ---- grub (UEFI) end
mformat -i "$ISO/boot/grub/efi.img" -C -f 1440 -N 0 ::
mcopy -i "$ISO/boot/grub/efi.img" -s "$ISO/efi" ::

# ------------------------------------------------------------- squash + ISO
msg "Compressing the system image"
unmount_all
rm -rf "$R"/boot/* "$R"/tmp/* "$R"/var/cache/apk/*
# zstd: nearly as small as xz but much faster to read on old CPUs
mksquashfs "$R" "$ISO/cherrystone.sfs" -comp zstd -Xcompression-level $SQUASH_LEVEL \
	-b 256K -noappend -no-progress -quiet

msg "Writing ISO"
ISOFILE="$OUT/cherrystone-$ARCH.iso"
xorrisofs -quiet \
	-output "$ISOFILE" \
	-full-iso9660-filenames -joliet -rational-rock \
	-sysid LINUX -volid "$LABEL" \
	-isohybrid-mbr "$ISO/boot/syslinux/isohdpfx.bin" \
	-eltorito-boot boot/syslinux/isolinux.bin \
	-eltorito-catalog boot/syslinux/boot.cat \
	-no-emul-boot -boot-load-size 4 -boot-info-table \
	-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
	"$ISO"
chown "$(stat -c %u:%g "$OUT")" "$ISOFILE"

msg "System image: $(du -h "$ISO/cherrystone.sfs" | cut -f1) compressed, $(du -sh "$R" | cut -f1) unpacked"
msg "Done: $ISOFILE ($(du -h "$ISOFILE" | cut -f1))"
rm -rf "$WORK"
