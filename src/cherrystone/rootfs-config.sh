#!/bin/sh
set -e
# Writes Cherrystone's configuration into the system image: services,
# autologin, X session, and a browser-first desktop. Called by mkiso.sh.
# Usage: rootfs-config.sh <rootfs dir> <branding dir>

tmp="$1"
BRAND="$2"
[ -d "$tmp" ] && [ -d "$BRAND" ] || { echo "usage: $0 rootfs-dir branding-dir" >&2; exit 1; }
HOSTNAME=cherrystone

makefile() {
	OWNER="$1"; PERMS="$2"; FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}
rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

mkdir -p "$tmp"/etc/apk "$tmp"/etc/skel/.config/openbox \
	"$tmp"/usr/local/bin

echo "$HOSTNAME" > "$tmp"/etc/hostname
# Let the hostname resolve (xauth complains otherwise)
printf '127.0.0.1\t%s localhost\n::1\t\tlocalhost\n' "$HOSTNAME" > "$tmp"/etc/hosts

# Autologin straight into the session on tty1; tty2 is a rescue login.
# Boot messages go to tty12 (Ctrl+Alt+F12) so the splash screen stays clean.
makefile root:root 0644 "$tmp"/etc/inittab <<'EOF'
::sysinit:/sbin/openrc sysinit >/dev/tty12 2>&1
::sysinit:/sbin/openrc boot >/dev/tty12 2>&1
::wait:/sbin/openrc default >/dev/tty12 2>&1
tty1::respawn:/usr/local/bin/cherrystone-session
tty2::respawn:/sbin/getty 38400 tty2
::ctrlaltdel:/sbin/reboot
::shutdown:/usr/local/sbin/cherrystone-bye
EOF

# Shutting down or restarting: close the desktop and show a plain
# Cherrystone screen instead of the system's messages
mkdir -p "$tmp"/usr/local/sbin "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-bye <<'EOF'
#!/bin/sh
pkill -x Xorg 2>/dev/null
sleep 1
chvt 1 2>/dev/null
{
	printf '\033]P1ffffff\033]P73a3a3a\033]PF3a3a3a\033]P2c0182f\033]PAc0182f'
	printf '\033[?25l\033[0;1;37;41m\033[2J\033[H'
	set -- $(stty size </dev/tty1 2>/dev/null)
	rows=${1:-25}; cols=${2:-80}
	i=$(( rows / 2 - 1 )); while [ "$i" -gt 0 ]; do echo; i=$((i - 1)); done
	printf "%$(( (cols - 11) / 2 ))s\033[1;32m%s\033[1;37m\n\n" "" "Cherrystone"
	printf "%$(( (cols - 11) / 2 ))s%s\n" "" "One moment."
} >/dev/tty1 2>/dev/null
exec /sbin/openrc shutdown >/dev/tty12 2>&1
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-session <<'EOF'
#!/bin/sh
# Starts the desktop on tty1; init starts it again whenever it ends (signing
# out). Normally as the cherrystone user. "Browse as guest" on the sign-in
# screen leaves /run/cherrystone-guest, and the next start is a guest one,
# whose home folder is in RAM so nothing they do is kept.
user=cherrystone
if [ -f /run/cherrystone-guest ]; then
	rm -f /run/cherrystone-guest
	user=guest
	umount -l /home/guest 2>/dev/null
	mount -t tmpfs -o mode=0700,size=50%,uid="$(id -u guest)",gid="$(id -g guest)" tmpfs /home/guest
	cp -a /etc/skel/. /home/guest/
	chown -R "guest:$(id -g guest)" /home/guest
fi
# X runs unprivileged, so the user must own the console it starts on
chown "$user" /dev/tty1
# (X's startup chatter goes to a log instead of over the splash screen)
su -l "$user" -c 'exec startx -- -nolisten tcp vt1 >/tmp/startx-$USER.log 2>&1'
if [ "$user" = guest ]; then
	pkill -u guest; sleep 1; pkill -9 -u guest
	umount -l /home/guest
fi
EOF

# One mode now (Cherrystone needs about 1 GB of memory). Kept for
# the scripts that ask.
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-mode <<'EOF'
#!/bin/sh
echo normal
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-browser <<'EOF'
#!/bin/sh
# Opens a browser window (Badwolf).
# NetSurf; each falls back to the other if its browser is missing.
# With --keep it reopens the browser whenever it is closed (kiosk style).
if [ "$(cherrystone-mode)" = lite ]; then
	browsers="badwolf"
else
	browsers="badwolf"
fi
home="file://$HOME/.local/share/cherrystone/home.html"
[ -f "$HOME/.local/share/cherrystone/home.html" ] || cherrystone-home
# New tabs open the Cherrystone home page (Cherrystone's Badwolf reads this);
# spell checking in English
export CHERRYSTONE_HOME="file://$HOME/.local/share/cherrystone/home.html"
export BADWOLF_L10N="${BADWOLF_L10N:-en_US:en_GB}"
# History (Ctrl+H): the page lives next to the history the browser keeps;
# only the newest 3000 visits are kept
d="$HOME/.local/share/cherrystone"
mkdir -p "$d"
cp /usr/share/cherrystone/history.html "$d/history.html" 2>/dev/null
if [ -f "$d/history.js" ] && [ "$(wc -l < "$d/history.js")" -gt 4000 ]; then
	tail -n 3000 "$d/history.js" > "$d/history.js.new" && mv "$d/history.js.new" "$d/history.js"
fi
export CHERRYSTONE_HISTORY="file://$d/history.html"
open_browser() {
	[ $# -eq 0 ] && set -- "$home"   # no address given: the Cherrystone home page
	for b in $browsers; do
		if command -v "$b" >/dev/null 2>&1; then
			"$b" "$@"
			return
		fi
	done
}
if [ "$1" = --keep ]; then shift
	open_browser "$@"
	while sleep 1; do open_browser; done
else
	open_browser "$@"
fi
EOF

# Let the desktop user power off and restart without a password
mkdir -p "$tmp"/etc/doas.d
makefile root:root 0600 "$tmp"/etc/doas.d/cherrystone.conf <<'EOF'
permit nopass cherrystone as root cmd /sbin/poweroff
permit nopass cherrystone as root cmd /sbin/reboot
permit nopass cherrystone as root cmd /usr/bin/brightnessctl
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-settz
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-checkpass
permit nopass cherrystone as root cmd /usr/local/sbin/cherrystone-guest
permit nopass guest as root cmd /sbin/poweroff
permit nopass guest as root cmd /sbin/reboot
permit nopass guest as root cmd /usr/bin/brightnessctl
EOF

# Right-click desktop menu (replaces Openbox's default, which lists apps
# that are not installed)
makefile root:root 0644 "$tmp"/etc/skel/.config/openbox/menu.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
<menu id="root-menu" label="Cherrystone">
  <item label="Web Browser"><action name="Execute"><command>cherrystone-browser</command></action></item>
  <item label="Files"><action name="Execute"><command>pcmanfm</command></action></item>
  <item label="Text Editor"><action name="Execute"><command>mousepad</command></action></item>
  <item label="Calculator"><action name="Execute"><command>cherrystone-calculator</command></action></item>
  <separator />
  <item label="Settings"><action name="Execute"><command>cherrystone-settings</command></action></item>
  <separator />
  <item label="Sign out"><action name="Exit"><prompt>no</prompt></action></item>
  <item label="Restart"><action name="Execute"><command>doas /sbin/reboot</command></action></item>
  <item label="Shut down"><action name="Execute"><command>doas /sbin/poweroff</command></action></item>
</menu>
</openbox_menu>
EOF

# ---- One look everywhere: flat, dark, cherry-red accent (same as the panel)

# Window frames and the right-click menu: light and plain
mkdir -p "$tmp"/usr/share/themes/Cherrystone/openbox-3
makefile root:root 0644 "$tmp"/usr/share/themes/Cherrystone/openbox-3/themerc <<'EOF'
border.width: 1
padding.width: 8
padding.height: 6
window.handle.width: 0
window.client.padding.width: 0
window.label.text.justify: center

window.active.border.color: #c4c7cc
window.inactive.border.color: #d7d9dc
window.active.title.bg: flat solid
window.active.title.bg.color: #e8eaed
window.inactive.title.bg: flat solid
window.inactive.title.bg.color: #f1f3f4
window.active.title.separator.color: #e8eaed
window.inactive.title.separator.color: #f1f3f4
window.active.label.bg: parentrelative
window.inactive.label.bg: parentrelative
window.active.label.text.color: #202124
window.inactive.label.text.color: #80868b
window.active.handle.bg: flat solid
window.active.handle.bg.color: #e8eaed
window.inactive.handle.bg: flat solid
window.inactive.handle.bg.color: #f1f3f4
window.active.grip.bg: parentrelative
window.inactive.grip.bg: parentrelative

window.active.button.unpressed.bg: parentrelative
window.active.button.unpressed.image.color: #3c4043
window.active.button.hover.bg: flat solid
window.active.button.hover.bg.color: #d81e3c
window.active.button.hover.image.color: #ffffff
window.active.button.pressed.bg: flat solid
window.active.button.pressed.bg.color: #a81530
window.active.button.pressed.image.color: #ffffff
window.active.button.toggled.bg: parentrelative
window.active.button.toggled.image.color: #3c4043
window.active.button.disabled.bg: parentrelative
window.active.button.disabled.image.color: #bdc1c6
window.inactive.button.unpressed.bg: parentrelative
window.inactive.button.unpressed.image.color: #9aa0a6
window.inactive.button.hover.bg: parentrelative
window.inactive.button.hover.image.color: #3c4043
window.inactive.button.pressed.bg: parentrelative
window.inactive.button.pressed.image.color: #3c4043
window.inactive.button.toggled.bg: parentrelative
window.inactive.button.toggled.image.color: #9aa0a6
window.inactive.button.disabled.bg: parentrelative
window.inactive.button.disabled.image.color: #dadce0

menu.border.width: 1
menu.border.color: #dadce0
menu.overlap.x: 0
menu.overlap.y: 0
menu.title.bg: flat solid
menu.title.bg.color: #f1f3f4
menu.title.text.color: #202124
menu.title.text.justify: center
menu.items.bg: flat solid
menu.items.bg.color: #ffffff
menu.items.text.color: #202124
menu.items.disabled.text.color: #9aa0a6
menu.items.active.bg: flat solid
menu.items.active.bg.color: #fbe3e8
menu.items.active.text.color: #202124
menu.separator.color: #dadce0
menu.separator.width: 1
menu.separator.padding.width: 6
menu.separator.padding.height: 4

osd.border.width: 1
osd.border.color: #dadce0
osd.bg: flat solid
osd.bg.color: #ffffff
osd.label.bg: parentrelative
osd.label.text.color: #202124
osd.hilight.bg: flat solid
osd.hilight.bg.color: #d81e3c
osd.unhilight.bg: flat solid
osd.unhilight.bg.color: #dadce0
EOF

# Font: Cantarell for everything that asks for "sans" (shelf, menus, pages);
# DejaVu stays as the fallback for symbols and other alphabets
mkdir -p "$tmp"/etc/fonts/conf.d
makefile root:root 0644 "$tmp"/etc/fonts/conf.d/60-cherrystone.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias><family>sans-serif</family><prefer><family>Cantarell</family><family>DejaVu Sans</family></prefer></alias>
  <alias><family>sans</family><prefer><family>Cantarell</family><family>DejaVu Sans</family></prefer></alias>
</fontconfig>
EOF

# Apps (all GTK 3): light theme with the cherry accent, flat icons (Papirus), modern cursor
mkdir -p "$tmp"/etc/skel/.config/gtk-3.0 "$tmp"/etc/skel/.icons/default
makefile root:root 0644 "$tmp"/etc/skel/.config/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-application-prefer-dark-theme=0
gtk-icon-theme-name=Papirus
gtk-cursor-theme-name=Adwaita
gtk-font-name=Cantarell 10
EOF
makefile root:root 0644 "$tmp"/etc/skel/.config/gtk-3.0/gtk.css <<'EOF'
@define-color theme_selected_bg_color #d81e3c;
@define-color theme_selected_fg_color #ffffff;
selection, *:selected { background-color: #d81e3c; color: #ffffff; }
scale highlight, progressbar progress { background-color: #d81e3c; border-color: #d81e3c; }
checkbutton check:checked, radiobutton radio:checked, switch:checked { background-color: #d81e3c; border-color: #d81e3c; }
/* Flat, light toolbars and menus (Files, Photos) */
menubar, toolbar { background: #ffffff; border-bottom: 1px solid #e8eaed; }
toolbar { padding: 4px 6px; }
toolbar button { border-radius: 0; }
statusbar { background: #f8f9fa; color: #5f6368; }
/* Plain dialogs (install, reset, save my stuff) in the same white look */
window.background, dialog { background-color: #ffffff; }
button { border-radius: 0; }
button.suggested-action:hover { background: #b3122f; }
entry { border-radius: 0; }
button.suggested-action { background: #d81e3c; background-image: none; color: #ffffff; border-color: #b3122f; }
button, row, menuitem { transition: background-color 150ms ease-out, color 150ms ease-out; }
/* Flat: no bevels, gradients or shadows anywhere, square corners */
* { box-shadow: none; text-shadow: none; -gtk-icon-shadow: none; }
button, combobox button, spinbutton button, headerbar, menubar, toolbar, notebook > header, tab {
	background-image: none; border-radius: 0; }
button { background-color: #f1f3f4; border: 1px solid transparent; color: #202124; }
button:hover { background-color: #e8eaed; }
button:active, button:checked { background-color: #dadce0; }
button.flat, button.image-button.flat { background-color: transparent; }
button.suggested-action, button.suggested-action:hover { color: #ffffff; border-color: transparent; }
entry, spinbutton, combobox entry { background-image: none; background-color: #f1f3f4; border-radius: 0;
	border: 1px solid transparent; }
entry:focus, spinbutton:focus { background-color: #ffffff; border-color: #d81e3c; }
check, radio { background-image: none; background-color: #ffffff; border: 2px solid #5f6368; border-radius: 0; }
radio { border-radius: 100px; }
check:checked, radio:checked { border-color: #d81e3c; color: #ffffff; }
switch { background-image: none; border-radius: 0; border: none; background-color: #dadce0; }
switch slider { background-image: none; border-radius: 0; border: none; background-color: #ffffff; }
menu, popover, popover.background, .csd popover, tooltip, tooltip.background { border-radius: 0; }
tooltip, tooltip.background { background-color: #ffffff; border-top: 2px solid #d81e3c; }
tooltip label { color: #202124; }
menu, popover { border: 1px solid #dadce0; }
headerbar, .titlebar { background-color: #ffffff; border-bottom: 1px solid #e8eaed; }
scrollbar slider { border-radius: 0; min-width: 6px; min-height: 6px; background-color: #bdc1c6; }
progressbar trough, progressbar progress, scale trough, scale highlight { border-radius: 0; }
EOF
# Animations (picom): windows grow in and fade, the launcher and shelf
# popups rise out of the shelf, notifications slide in from the right, and
# the shelf rises in after you sign in. No shadows or blur: old computers.
# Big windows (the browser, videos) just appear, which keeps them fast.
# Settings > Display > Animations turns it off.
makefile root:root 0644 "$tmp"/etc/xdg/picom.conf <<'EOF'
backend = "xrender";
vsync = false;
use-damage = true;
unredir-if-possible = true;
shadow = false;
fading = true;
fade-in-step = 0.1;
fade-out-step = 0.12;
fade-delta = 10;
# Most windows grow in a little and fade
animations = (
  { triggers = ["open", "show"]; preset = "appear"; scale = 0.95; duration = 0.15; },
  { triggers = ["close", "hide"]; preset = "disappear"; scale = 0.95; duration = 0.1; }
);
rules = (
  # The launcher and the shelf popups rise up out of the shelf
  { match = "class_g = 'Rofi' || class_g = 'CherryQuick'";
    animations = (
      { triggers = ["open", "show"];
        opacity = { duration = 0.15; start = 0; end = 1; curve = "cubic-bezier(0.2, 0.8, 0.3, 1)"; };
        offset-y = { duration = 0.15; start = 24; end = 0; curve = "cubic-bezier(0.2, 0.8, 0.3, 1)"; }; },
      { triggers = ["close", "hide"];
        opacity = { duration = 0.1; start = 1; end = 0; };
        offset-y = { duration = 0.1; start = 0; end = 16; }; }
    ); },
  # Notifications slide in from the right
  { match = "class_g = 'Dunst'";
    animations = (
      { triggers = ["open", "show"];
        opacity = { duration = 0.18; start = 0; end = 1; };
        offset-x = { duration = 0.18; start = 40; end = 0; curve = "cubic-bezier(0.2, 0.8, 0.3, 1)"; }; },
      { triggers = ["close", "hide"];
        opacity = { duration = 0.15; start = 1; end = 0; };
        offset-x = { duration = 0.15; start = 0; end = 40; }; }
    ); },
  # The shelf rises in once, right after you sign in
  { match = "class_g = 'Tint2'";
    animations = (
      { triggers = ["open"];
        offset-y = { duration = 0.3; start = 40; end = 0; curve = "cubic-bezier(0.2, 0.8, 0.3, 1)"; }; }
    ); },
  # Big windows (the browser, videos) and the lock screen just appear: fast
  { match = "class_g = 'Badwolf' || class_g = 'mpv' || class_g = 'i3lock' || window_type = 'desktop'";
    animations = (); fade = false; }
);
EOF

makefile root:root 0644 "$tmp"/etc/skel/.icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=Adwaita
EOF

# Openbox settings: start from the stock rc.xml, then use the theme above,
# open browsers maximized (netbook screens are small) and add shortcuts.
# Just one desktop: with more, Ctrl+Alt+arrows or scrolling on the
# background switches to an empty one and it looks like everything vanished.
cat > "$tmp"/tmp/cs-keys.xml <<'EOF'
    <keybind key="Super_L"><action name="Execute"><command>cherrystone-launcher</command></action></keybind>
    <keybind key="Print"><action name="Execute"><command>cherrystone-screenshot</command></action></keybind>
    <keybind key="S-Print"><action name="Execute"><command>cherrystone-screenshot area</command></action></keybind>
    <keybind key="C-A-t"><action name="Execute"><command>cherrystone-terminal</command></action></keybind>
    <keybind key="XF86AudioRaiseVolume"><action name="Execute"><command>cherrystone-volume up</command></action></keybind>
    <keybind key="XF86AudioLowerVolume"><action name="Execute"><command>cherrystone-volume down</command></action></keybind>
    <keybind key="XF86AudioMute"><action name="Execute"><command>cherrystone-volume mute</command></action></keybind>
    <keybind key="XF86MonBrightnessUp"><action name="Execute"><command>cherrystone-brightness up</command></action></keybind>
    <keybind key="XF86MonBrightnessDown"><action name="Execute"><command>cherrystone-brightness down</command></action></keybind>
    <keybind key="XF86WWW"><action name="Execute"><command>cherrystone-browser</command></action></keybind>
    <keybind key="XF86HomePage"><action name="Execute"><command>cherrystone-browser</command></action></keybind>
    <keybind key="C-A-l"><action name="Execute"><command>cherrystone-lock</command></action></keybind>
    <keybind key="C-A-slash"><action name="Execute"><command>cherrystone-shortcuts</command></action></keybind>
    <keybind key="F11"><action name="ToggleFullscreen"/></keybind>
    <keybind key="XF86ScreenSaver"><action name="Execute"><command>cherrystone-lock</command></action></keybind>
EOF
cat > "$tmp"/tmp/cs-apps.xml <<'EOF'
    <application class="Badwolf"><maximized>yes</maximized></application>
    <application class="badwolf"><maximized>yes</maximized></application>
    <application class="Netsurf*"><decor>no</decor><maximized>yes</maximized></application>
    <application class="Yad"><decor>yes</decor><focus>yes</focus><layer>above</layer></application>
    <application class="Cherry*"><focus>yes</focus><layer>above</layer></application>
EOF
if [ -f "$tmp"/etc/xdg/openbox/rc.xml ]; then
	sed -e 's|<name>Clearlooks</name>|<name>Cherrystone</name>|' \
	    -e 's|<number>[0-9]*</number>|<number>1</number>|' \
	    "$tmp"/etc/xdg/openbox/rc.xml |
	awk -v keys="$tmp/tmp/cs-keys.xml" -v apps="$tmp/tmp/cs-apps.xml" '
		/<\/keyboard>/     { while ((getline l < keys) > 0) print l }
		/<\/applications>/ { while ((getline l < apps) > 0) print l }
		{ print }' > "$tmp"/etc/skel/.config/openbox/rc.xml
fi
rm -f "$tmp"/tmp/cs-keys.xml "$tmp"/tmp/cs-apps.xml

# App launcher: a grid of apps with a search box, opened from the cherry
# button or the Super key. Typing something that isn't an app searches the web.
mkdir -p "$tmp"/usr/share/cherrystone
makefile root:root 0644 "$tmp"/usr/share/cherrystone/apps <<'EOF'
Web Browser|web-browser|cherrystone-browser
Files|system-file-manager|pcmanfm
Notes|accessories-text-editor|cherrystone-notes
Calculator|accessories-calculator|cherrystone-calculator
Photos|gpicview|gpicview
Media Player|mpv|mpv --player-operation-mode=pseudo-gui
Settings|preferences-system|cherrystone-settings
EOF

# Linux tools, shown only after Settings > Advanced > Advanced tools (like the
# Linux switch, off by default)
makefile root:root 0644 "$tmp"/usr/share/cherrystone/apps-linux <<'EOF'
Terminal|utilities-terminal|lxterminal
Task Manager|utilities-system-monitor|lxterminal -e htop
EOF

# Files > Tools > "Open as root": only with Advanced tools on, and it asks
# for the password in a terminal (if there is one)
makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-asroot <<'EOF'
#!/bin/sh
if [ -f ~/.config/cherrystone/linux-apps ]; then exec lxterminal -e su -c "$*"; fi
notify-send -i dialog-password "Advanced tools are off" "Turn them on in Settings > Advanced > Advanced tools."
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-terminal <<'EOF'
#!/bin/sh
if [ -f ~/.config/cherrystone/linux-apps ]; then exec lxterminal "$@"; fi
notify-send -i utilities-terminal "Advanced tools are off" "Turn them on in Settings > Advanced > Advanced tools."
EOF

makefile root:root 0644 "$tmp"/usr/share/cherrystone/launcher.rasi <<'EOF'
configuration { icon-theme: "Papirus"; show-icons: true; }
/* Sits right on top of the shelf, above the cherry button, in the same
   white-and-cherry look as quick settings and Settings */
* {
    bg: #ffffff; field: #f1f3f4; fg: #202124; dim: #5f6368; hover: #fde4e8; cherry: #d81e3c;
    background-color: transparent; text-color: @fg; font: "Cantarell 10";
}
window {
    location: south west; anchor: south west; x-offset: 0; y-offset: -40px;
    width: 420px; height: 520px; background-color: @bg;
    border: 3px 0 0 0; border-color: @cherry; padding: 18px 20px 14px;
}
mainbox { children: [ message, inputbar, textbox-apps, listview, textbox-hint ]; spacing: 12px; }
message { padding: 0 2px; }
textbox { text-color: @fg; font: "Cantarell Light 22"; }
inputbar {
    children: [ icon-search, entry ]; spacing: 10px;
    background-color: @field; padding: 10px 16px; border-radius: 0;
}
icon-search { expand: false; filename: "system-search-symbolic"; size: 16px; vertical-align: 0.5; }
entry { placeholder: "Search apps or the web"; placeholder-color: @dim; vertical-align: 0.5; }
textbox-apps {
    expand: false;
    content: "apps";
    font: "Cantarell Light 16";
    text-color: @cherry;
    padding: 4px 2px 0;
}
/* One app per row, big text: easy to hit on a small screen */
listview {
    columns: 1; lines: 10; fixed-height: false;
    spacing: 0; scrollbar: false;
}
element { orientation: horizontal; padding: 6px 4px; spacing: 14px; border-radius: 0; }
element selected, element selected.normal, element selected.active { background-color: @hover; }
element-icon { size: 28px; vertical-align: 0.5; }
element-text { font: "Cantarell Light 15"; vertical-align: 0.5; text-color: inherit; }
element selected.normal { text-color: @cherry; }
textbox-hint {
    expand: false;
    content: "Not an app? Press Enter to search the web.";
    font: "Cantarell 8";
    text-color: @dim;
    horizontal-align: 0.5;
}
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-launcher <<'EOF'
#!/bin/sh
# Pressing the button again closes the launcher
pkill -x rofi && exit 0
apps="/tmp/cherrystone-apps.$(id -u)"
cat /usr/share/cherrystone/apps > "$apps"
[ -f ~/.config/cherrystone/linux-apps ] && cat /usr/share/cherrystone/apps-linux >> "$apps"
# "Good evening, Sam" at the top
h="$(date +%H)"
case "$h" in 0[5-9]|1[01]) hi="Good morning" ;; 1[2-7]) hi="Good afternoon" ;; *) hi="Good evening" ;; esac
name="$(head -n1 ~/.config/cherrystone/name 2>/dev/null | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g')"
[ "$USER" = guest ] && name=""
greeting="$hi${name:+, $name}"
choice="$(while IFS='|' read -r name icon cmd; do
		printf '%s\0icon\037%s\n' "$name" "$icon"
	done < "$apps" |
	rofi -dmenu -i -p "" -mesg "$greeting" -theme /usr/share/cherrystone/launcher.rasi)"
[ -n "$choice" ] || exit 0
cmd="$(awk -F'|' -v n="$choice" '$1 == n { print $3; exit }' "$apps")"
[ -n "$cmd" ] && exec sh -c "$cmd"
# Not an app: open it as a web address, or search for it
case "$choice" in
	*://*) url="$choice" ;;
	*' '*) url="" ;;
	*.*) url="https://$choice" ;;
	*) url="" ;;
esac
if [ -z "$url" ]; then
	q="$(printf '%s' "$choice" | sed -e 's/%/%25/g' -e 's/&/%26/g' -e 's/#/%23/g' \
		-e 's/+/%2B/g' -e 's/?/%3F/g' -e 's/ /+/g')"
	if [ "$(cherrystone-mode)" = lite ]; then
		url="https://www.google.com/search?q=$q"
	else
		url="https://www.google.com/search?q=$q"
	fi
fi
exec cherrystone-browser "$url"
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-power <<'EOF'
#!/bin/sh
# Your picture on the shelf: lock, sign out, restart, shut down (part of cherrystone-ui)
exec cherrystone-ui power
EOF

# Hide menu entries that only confuse: the raw browser entries (the
# "Web Browser" entry picks the right one) and settings tools for the panel/WM
mkdir -p "$tmp"/usr/local/share/applications
for app in firefox badwolf netsurf tint2 tint2conf openbox feh rofi rofi-theme-selector gcr-prompter gcr-viewer \
		libfm-pref-apps lxshortcut pcmanfm-desktop-pref org.xfce.mousepad-settings \
		xfce4-about nm-applet nm-connection-editor arandr yad-icon-browser yad-settings \
		dunst lxterminal-preferences; do
	printf '[Desktop Entry]\nType=Application\nName=%s\nNoDisplay=true\n' "$app" \
		> "$tmp"/usr/local/share/applications/"$app".desktop
done

makefile root:root 0644 "$tmp"/etc/skel/.xinitrc <<'EOF'
export XCURSOR_THEME=Adwaita
xsetroot -cursor_name left_ptr
# 600-pixel-tall netbook screens (like the Aspire One's 1024x600): a bit
# smaller text and controls so more of the page fits
# smaller text and controls so more of the page fits; Settings > Display >
# Text size makes everything bigger on top of that
h="$(xrandr --current 2>/dev/null | awk '/\*/ { split($1, a, "x"); print a[2]; exit }')"
scale=100
[ "${h:-768}" -le 640 ] && scale=90
size="$(cat ~/.config/cherrystone/textsize 2>/dev/null)"
case "$size" in 115|130) scale=$(( scale * size / 100 )) ;; esac
if [ "$scale" != 100 ]; then
	CHERRYSTONE_SCALE="$(awk -v s="$scale" 'BEGIN { printf "%.2f", s / 100 }')"
	export CHERRYSTONE_SCALE GDK_DPI_SCALE="$CHERRYSTONE_SCALE"
fi
# Old computers (2 GB or less, or no 3D graphics driver, like the Aspire
# One's GMA 950): the browser draws pages itself instead of through OpenGL,
# which there means slow software 3D. Games and scrolling go from ~7 to 30
# frames a second.
mem="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
if [ "${mem:-0}" -le 2100000 ] || [ ! -e /dev/dri/renderD128 ]; then
	export WEBKIT_DISABLE_COMPOSITING_MODE=1
	export CHERRYSTONE_OLD_PC=1     # also: animations start off (Settings > Display)
fi
# A private folder for this session's sockets (PipeWire's sound needs one)
if [ -z "$XDG_RUNTIME_DIR" ]; then
	XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
	mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
	export XDG_RUNTIME_DIR
fi
# A session message bus: notifications and USB-stick mounting need it
exec dbus-run-session openbox-session
EOF

makefile root:root 0755 "$tmp"/etc/skel/.config/openbox/autostart <<'EOF'
# Started from the boot menu's Recovery entry: just the Recovery app
if grep -qw cherrystone.recovery /proc/cmdline; then
	# White and light, like the early-boot recovery screens
	export GTK_THEME=Adwaita
	feh --no-fehbg --bg-fill /usr/share/backgrounds/cherrystone-white.png
	dunst &
	pcmanfm --daemon-mode &
	while :; do cherrystone-recovery; sleep 1; done
fi
# How long the computer took to start (shown in Settings > About)
[ -f /tmp/cherrystone-started ] || cut -d. -f1 /proc/uptime > /tmp/cherrystone-started
# Sound server (64-bit only: newer laptops and Chromebooks need it for
# their speaker profiles); the startup sound waits a moment for it
if [ -x /usr/libexec/pipewire-launcher ]; then
	/usr/libexec/pipewire-launcher &
	(sleep 2; cherrystone-chime) &
elif command -v pipewire >/dev/null 2>&1; then
	(pipewire & sleep 1; wireplumber & pipewire-pulse &) &
	(sleep 2; cherrystone-chime) &
else
	cherrystone-chime &
fi
cherrystone-touchpad apply &
# Animations: Settings > Display turns them on or off. Until you choose,
# they're on, except on old computers, where every moving thing (games,
# videos, scrolling) would pay for them.
anim="$(cat ~/.config/cherrystone/animations 2>/dev/null)"
[ -f ~/.config/cherrystone/no-animations ] && anim=off
[ -n "$anim" ] || { [ -n "$CHERRYSTONE_OLD_PC" ] && anim=off || anim=on; }
[ "$anim" = on ] && picom -b
# Sign-in screen with a big clock, on your wallpaper or a plain background
# (guests skip it)
if [ "$USER" != guest ]; then
	wall="$(cat ~/.config/cherrystone/wallpaper 2>/dev/null)"
	[ -f "$wall" ] || wall=/usr/share/backgrounds/cherrystone/blossom-light.png
	feh --no-fehbg --bg-fill "$wall"
	until cherrystone-signin; do sleep 1; done
fi
if [ -x ~/.fehbg ]; then ~/.fehbg; else feh --bg-fill /usr/share/backgrounds/cherrystone/blossom-light.png; fi
cherrystone-shelf &
dunst &
cherrystone-home
# Nothing opens by itself after signing in: the browser is on the shelf
# and in the launcher. The welcome screen only shows until it has been
# answered once (which is every boot unless your stuff is being saved).
# The tour is linked from the home page (no pop-up).
(if [ "$USER" != guest ] && [ ! -f ~/.config/cherrystone/welcomed ]; then cherrystone-welcome; fi) &
# The rest can wait: on a single-core netbook the desktop gets the
# processor to itself while it starts
(sleep 10
 pcmanfm --daemon-mode &
 cherrystone-watch &
 ls /sys/class/bluetooth/hci* >/dev/null 2>&1 && blueman-applet &
 wait) &
if [ "$USER" = guest ]; then
	notify-send -i cherrystone -t 10000 "You're browsing as a guest" \
		"Nothing you do is kept. Sign out (power button) when you're done."
fi
EOF

# Branding: icon theme entries, wallpaper, launcher entry, panel config
for s in 16 24 32 48 64 128 256 512; do
	mkdir -p "$tmp"/usr/share/icons/hicolor/${s}x${s}/apps
	cp "$BRAND"/cherrystone-$s.png \
		"$tmp"/usr/share/icons/hicolor/${s}x${s}/apps/cherrystone.png
done
mkdir -p "$tmp"/usr/share/icons/hicolor/scalable/apps \
	"$tmp"/usr/share/backgrounds "$tmp"/usr/share/applications \
	"$tmp"/etc/skel/.config/tint2
cp "$BRAND"/cherrystone.svg "$tmp"/usr/share/icons/hicolor/scalable/apps/cherrystone.svg
cp "$BRAND"/wallpaper-small.png "$tmp"/usr/share/backgrounds/cherrystone.png

makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-browser.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Web Browser
Exec=cherrystone-browser
Icon=web-browser
Categories=Network;WebBrowser;
EOF

# Files on the shelf, with an icon the icon theme has
makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-files.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Files
Exec=pcmanfm
Icon=system-file-manager
NoDisplay=true
EOF

makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-power.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Power
Exec=cherrystone-power
Icon=cherrystone-shutdown
NoDisplay=true
EOF

# The shelf along the bottom: the launcher button and
# pinned apps at the left, then open windows; network, volume, battery, the
# clock (quick settings) and your picture (power, sign out) at the right.
makefile root:root 0644 "$tmp"/usr/share/cherrystone/shelf.tint2rc <<'EOF'
# background 1: the shelf
rounded = 0
border_width = 0
background_color = #12050a 92
border_color = #000000 0

# background 2: the window you're using (red underline)
rounded = 0
border_width = 2
border_sides = B
background_color = #ffffff 12
border_color = #d81e3c 100

# background 3: other open windows (grey underline)
rounded = 0
border_width = 2
border_sides = B
background_color = #000000 0
border_color = #b89aa2 100

# background 4: the Install button (cherry red)
rounded = 0
border_width = 0
background_color = #d81e3c 100
border_color = #000000 0

# background 5: the labels when you hover over something (flat white, cherry line on top)
rounded = 0
border_width = 2
border_sides = T
background_color = #ffffff 100
border_color = #d81e3c 100

tooltip_background_id = 5
tooltip_font = Cantarell 10
tooltip_font_color = #202124 100
tooltip_padding = 10 6
tooltip_show_timeout = 0.4
tooltip_hide_timeout = 0.1

panel_items = PLTSEEEECP
panel_size = 100% 40
panel_position = bottom center horizontal
panel_background_id = 1
panel_padding = 6 0 6
panel_layer = top
mouse_effects = 1
mouse_hover_icon_asb = 100 0 15

# Launcher button: apps and search (or the Windows key)
button = new
button_icon = /usr/share/icons/hicolor/48x48/apps/cherrystone.png
button_lclick_command = cherrystone-launcher
button_tooltip = Apps and search
button_max_icon_size = 26
button_padding = 8 0

# Pinned apps
launcher_icon_size = 26
launcher_icon_theme = Papirus
launcher_icon_theme_override = 1
launcher_padding = 6 0 6
launcher_tooltip = 1
launcher_item_app = /usr/share/applications/cherrystone-browser.desktop
launcher_item_app = /usr/share/applications/cherrystone-gmail.desktop
launcher_item_app = /usr/share/applications/cherrystone-docs.desktop
launcher_item_app = /usr/share/applications/cherrystone-youtube.desktop
launcher_item_app = /usr/share/applications/cherrystone-files.desktop
launcher_item_app = /usr/share/applications/cherrystone-settings.desktop

# Open windows: icons
taskbar_padding = 6 0 4
task_icon = 1
task_text = 0
task_tooltip = 1
task_maximum_size = 40 40
task_padding = 7 5 0
task_background_id = 3
task_active_background_id = 2
task_iconified_background_id = 3

# Status icons: network (click for Wi-Fi), volume (scroll to change,
# click to mute), battery (nothing on machines without one)
# Bluetooth (nothing on computers without it): click for Bluetooth settings
execp = new
execp_command = cherrystone-status bt
execp_interval = 10
execp_has_icon = 1
execp_icon_w = 18
execp_icon_h = 18
execp_padding = 5 0
execp_tooltip = Bluetooth
execp_lclick_command = cherrystone-bluetooth

execp = new
execp_command = cherrystone-status net
execp_interval = 5
execp_has_icon = 1
execp_icon_w = 18
execp_icon_h = 18
execp_padding = 5 0
execp_tooltip = Wi-Fi
execp_lclick_command = cherrystone-wifi

execp = new
execp_command = cherrystone-status vol
execp_interval = 2
execp_has_icon = 1
execp_icon_w = 18
execp_icon_h = 18
execp_padding = 5 0
execp_tooltip = Scroll to change the volume, click to mute
execp_lclick_command = cherrystone-volume mute
execp_uwheel_command = cherrystone-volume up
execp_dwheel_command = cherrystone-volume down

execp = new
execp_command = cherrystone-status bat
execp_interval = 30
execp_has_icon = 1
execp_icon_w = 18
execp_icon_h = 18
execp_padding = 5 0
execp_tooltip = Battery
execp_lclick_command = cherrystone-quick

# Install (only while running from the USB stick; cherrystone-shelf
# removes this block otherwise)
#INSTALL{
button = new
button_icon = /usr/share/cherrystone/shelf/install.svg
button_text = Install
button_font = sans bold 9
button_font_color = #ffffff 100
button_background_id = 4
button_lclick_command = cherrystone-installer
button_tooltip = Put Cherrystone on this computer: it starts faster and keeps your stuff
button_max_icon_size = 18
button_padding = 10 0 6
#}INSTALL

systray_padding = 4 2 4
systray_icon_size = 18
# blueman's own coloured tray icon is hidden (the white Bluetooth icon replaces it)
systray_name_filter = lueman

time1_format = %H:%M
time1_font = sans bold 10
clock_font_color = #ffffff 100
clock_padding = 8 0
clock_tooltip = Quick settings
clock_lclick_command = cherrystone-quick

# Your picture: power, restart, sign out
button = new
button_icon = @AVATAR@
button_lclick_command = cherrystone-power
button_tooltip = Shut down, restart or sign out
button_max_icon_size = 24
button_padding = 8 0
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-shelf <<'EOF'
#!/bin/sh
# Starts the shelf, with your picture (Settings > Your name and picture) at
# the right end, or the power symbol if you haven't set one
face=/usr/share/icons/hicolor/48x48/apps/cherrystone-shutdown.png
[ -f "$HOME/.face" ] && face="$HOME/.face"
d=~/.config/tint2
mkdir -p "$d"
# From the USB stick: a red Install button next to the status icons
if grep -qw cherrystone.live /proc/cmdline && [ "$USER" != guest ]; then
	edit='s/^panel_items = PLTSEEEECP$/panel_items = PLTPSEEEECP/'
else
	edit='/^#INSTALL{$/,/^#}INSTALL$/d'
fi
sed -e "s#@AVATAR@#$face#" -e "$edit" /usr/share/cherrystone/shelf.tint2rc > "$d/shelf.tint2rc"
pkill -x tint2
exec tint2 -c "$d/shelf.tint2rc"
EOF

# Badwolf: block ads and trackers (a big speed-up on old computers). The
# EasyList content-blocker list is downloaded while building; without
# network the build carries on without it.
mkdir -p "$tmp"/etc/skel/.config/badwolf "$tmp"/etc/skel/.local/share/badwolf
if wget -q -T 60 -O "$tmp"/etc/skel/.config/badwolf/content-filters.json \
		https://easylist-downloads.adblockplus.org/easylist_min_content_blocker.json; then
	chmod 0644 "$tmp"/etc/skel/.config/badwolf/content-filters.json
else
	rm -f "$tmp"/etc/skel/.config/badwolf/content-filters.json
	echo "warning: couldn't download the ad-block list; building without it" >&2
fi
makefile root:root 0644 "$tmp"/etc/skel/.local/share/badwolf/interface.css <<'EOF'
/* Badwolf in Cherrystone: light, roomy tabs and address bar */
/* same corners, greys and cherry as the rest of Cherrystone */
notebook > header { background: #f1f3f4; border: none; padding: 4px 6px 0; box-shadow: none; }
notebook > header tab { padding: 6px 12px; margin: 0 2px; border: none; border-radius: 0;
                        background: transparent; color: #5f6368; box-shadow: none; min-height: 0; }
notebook > header tab:hover { background: #e8eaed; }
notebook > header tab:checked { background: #ffffff; color: #202124; box-shadow: none; }
notebook > header tab button { padding: 0; min-width: 18px; min-height: 18px; border-radius: 0;
                               background: transparent; border: none; box-shadow: none; }
notebook > header tab button:hover { background: #dadce0; }
#cherry_tabplus { margin-left: 10px; padding: 2px; min-width: 22px; min-height: 22px; border-radius: 0;
                  color: #5f6368; background: transparent; border: none; box-shadow: none; }
#cherry_tabplus:hover { background: #dadce0; }
notebook > stack { border: none; }
box > box > button { border-radius: 0; border: none; background: transparent; box-shadow: none; }
box > box > button:hover { background: #f1f3f4; }
entry { border-radius: 0; padding: 5px 14px; background: #f1f3f4; border: 1px solid transparent;
        box-shadow: none; }
entry:focus { background: #ffffff; border-color: #d81e3c; }
entry progress { background: none; border-bottom: 2px solid #d81e3c; border-radius: 0; }
EOF


# ---------------------------------------------------------------- hardware keys

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-volume <<'EOF'
#!/bin/sh
# cherrystone-volume up|down|mute|status  (keys, panel indicator)
ctl=Master
amixer sget "$ctl" >/dev/null 2>&1 || ctl=PCM
amixer sget "$ctl" >/dev/null 2>&1 || exit 0     # no sound card
case "$1" in
	up)   amixer -q sset "$ctl" 5%+ unmute ;;
	down) amixer -q sset "$ctl" 5%- ;;
	mute) amixer -q sset "$ctl" toggle ;;
esac
info="$(amixer sget "$ctl")"
vol="$(echo "$info" | grep -o '[0-9]*%' | head -n1)"
if echo "$info" | grep -q '\[off\]'; then label="muted"; else label="$vol"; fi
if [ "$1" = status ]; then
	echo "♪ $label"
else
	v="${vol%\%}"
	if [ "$label" = muted ] || [ "${v:-0}" -eq 0 ]; then icon=audio-volume-muted
	elif [ "$v" -lt 34 ]; then icon=audio-volume-low
	elif [ "$v" -lt 67 ]; then icon=audio-volume-medium
	else icon=audio-volume-high; fi
	notify-send -a osd -i "$icon" -t 1500 -h string:x-dunst-stack-tag:volume \
		-h "int:value:${v:-0}" "Volume  $label" "
fi
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-brightness <<'EOF'
#!/bin/sh
# cherrystone-brightness up|down
case "$1" in
	up)   doas /usr/bin/brightnessctl -c backlight -q set 10%+ ;;
	down) doas /usr/bin/brightnessctl -c backlight -q -n 5% set 10%- ;;
esac
pct=$(( $(brightnessctl -c backlight get) * 100 / $(brightnessctl -c backlight max) ))
notify-send -a osd -i display-brightness -t 1500 -h string:x-dunst-stack-tag:brightness \
	-h "int:value:$pct" "Brightness  $pct%" "
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-screenshot <<'EOF'
#!/bin/sh
# Print Screen: the whole screen. Shift+Print Screen (cherrystone-screenshot
# area): drag a box. Saved to ~/Pictures, with Open and Copy buttons.
mkdir -p "$HOME/Pictures"
f="$HOME/Pictures/Screenshot $(date '+%Y-%m-%d %H.%M.%S').png"
if [ "$1" = area ]; then
	scrot -s -f "$f" || exit 0
else
	scrot "$f" || exit 0
fi
a="$(notify-send -i "$f" -t 15000 "Screenshot saved" "In Pictures" -A open=Open -A copy=Copy)"
case "$a" in
	open) xdg-open "$f" ;;
	copy) xclip -selection clipboard -t image/png -i "$f" &&
		notify-send -i edit-copy "Screenshot copied" "Paste it with Ctrl+V." ;;
esac
EOF

# Notifications (volume/brightness popups, screenshots) in the Cherrystone colours
mkdir -p "$tmp"/etc/skel/.config/dunst
makefile root:root 0644 "$tmp"/etc/skel/.config/dunst/dunstrc <<'EOF'
[global]
    width = 300
    height = 120
    origin = bottom-right
    offset = 8x48
    gap_size = 6
    padding = 12
    horizontal_padding = 14
    text_icon_padding = 12
    frame_width = 0
    frame_color = "#202124"
    separator_color = frame
    corner_radius = 0
    font = Cantarell 10
    format = "<span size='large' weight='light'>%s</span>\n<span foreground='#bdc1c6'>%b</span>"
    progress_bar = true
    progress_bar_height = 6
    progress_bar_frame_width = 0
    highlight = "#d81e3c"
    icon_position = left
    min_icon_size = 32
    max_icon_size = 32
    mouse_left_click = do_action, close_current
    icon_theme = "Papirus, Adwaita"
    enable_recursive_icon_lookup = true

[osd]
    appname = osd
    history_ignore = true

[nm-disconnected]
    summary = "Disconnected"
    skip_display = true
    history_ignore = true

[urgency_low]
    highlight = "#d81e3c"
    background = "#202124"
    foreground = "#ffffff"
    timeout = 3

[urgency_normal]
    background = "#202124"
    foreground = "#ffffff"
    highlight = "#d81e3c"
    timeout = 5

[urgency_critical]
    background = "#d81e3c"
    foreground = "#ffffff"
    format = "<span size='large' weight='light'>%s</span>\n%b"
    timeout = 0
EOF

# --------------------------------------------------------- welcome + settings

# Sets the system time zone. Runs as root through doas, so it only accepts
# zone names that exist in the tz database.
mkdir -p "$tmp"/usr/local/sbin
makefile root:root 0755 "$tmp"/usr/local/sbin/cherrystone-settz <<'EOF'
#!/bin/sh
zone="$1"
case "$zone" in ''|*..*|/*) echo "bad time zone" >&2; exit 1 ;; esac
[ -f "/usr/share/zoneinfo/$zone" ] || { echo "unknown time zone: $zone" >&2; exit 1; }
ln -sf "/usr/share/zoneinfo/$zone" /etc/localtime
echo "$zone" > /etc/timezone
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-welcome <<'EOF'
#!/usr/bin/env python3
# Welcome screen shown at startup: keyboard layout, time zone, Wi-Fi hint.
# "cherrystone-welcome --settings" shows the same choices from Settings.
# Enter (or the button) continues.
import os
import subprocess
import sys

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

GLib.set_prgname("CherryWelcome")   # window class Cherry*: the window manager focuses it
SETTINGS = "--settings" in sys.argv[1:]
LAYOUTS = ("us gb de fr es it pt br latam ca nl be ch at se no dk fi is ie pl cz sk hu ro bg "
           "gr tr ru ua by lt lv ee si hr rs il ara in jp kr cn th vn").split()


def current_layout():
    try:
        out = subprocess.run(["setxkbmap", "-query"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            if line.startswith("layout:"):
                return line.split()[1].split(",")[0]
    except OSError:
        pass
    return "us"


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip() or default
    except OSError:
        return default


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


win = Gtk.Window(title="Keyboard and time zone" if SETTINGS else "Welcome to Cherrystone")
win.set_icon_name("cherrystone")
win.set_position(Gtk.WindowPosition.CENTER)
win.set_resizable(False)
win.set_border_width(20)
win.connect("destroy", Gtk.main_quit)

outer = Gtk.Box(spacing=18)
outer.pack_start(Gtk.Image.new_from_file("/usr/share/cherrystone/stony/stony-excited-small.png"), False, False, 0)
col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
outer.pack_start(col, True, True, 0)

title = Gtk.Label(xalign=0)
if SETTINGS:
    title.set_markup("<b>Keyboard and time zone</b>")
else:
    title.set_markup("<span size='x-large' weight='bold'>Welcome to Cherrystone</span>")
col.pack_start(title, False, False, 0)
if not SETTINGS:
    col.pack_start(Gtk.Label(xalign=0, label="Get online, then pick your keyboard layout and time zone."),
                   False, False, 0)

grid = Gtk.Grid(column_spacing=12, row_spacing=8)
cur_kb, cur_tz = current_layout(), read("/etc/timezone", "UTC")
tz_list = zones()
kb_box, tz_box = combo(LAYOUTS, cur_kb), combo(tz_list, cur_tz)
for row, (label, box) in enumerate((("Keyboard layout", kb_box), ("Time zone", tz_box))):
    grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)
    box.set_hexpand(True)
    grid.attach(box, 1, row, 1, 1)
col.pack_start(grid, False, False, 0)

# Internet: shows whether you're online, with a button to pick a Wi-Fi network
if not SETTINGS:
    net_label = Gtk.Label(xalign=0)
    wifi = Gtk.Button(label="Connect to Wi-Fi")
    wifi.connect("clicked", lambda *_: subprocess.Popen(["cherrystone-wifi"]))

    def refresh():
        r = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True)
        on = r.stdout.strip() == "connected"
        net_label.set_markup("<b>Connected</b>" if on else "Not connected")
        wifi.set_visible(not on)
        return True
    grid.attach(Gtk.Label(label="Internet", xalign=0), 0, 2, 1, 1)
    nbox = Gtk.Box(spacing=10)
    nbox.pack_start(net_label, False, False, 0)
    nbox.pack_end(wifi, False, False, 0)
    grid.attach(nbox, 1, 2, 1, 1)
    GLib.timeout_add_seconds(3, refresh)

go = Gtk.Button(label="Apply" if SETTINGS else "Done")
go.set_can_default(True)
go.get_style_context().add_class("suggested-action")
row = Gtk.Box()
row.pack_end(go, False, False, 0)
col.pack_start(row, False, False, 4)


def done(*args):
    kb, tz = kb_box.get_active_text(), tz_box.get_active_text()
    os.makedirs(os.path.expanduser("~/.config/cherrystone"), exist_ok=True)
    open(os.path.expanduser("~/.config/cherrystone/welcomed"), "a").close()
    if kb in LAYOUTS and kb != cur_kb:
        subprocess.run(["setxkbmap", "-layout", kb])
    if tz and tz != cur_tz:
        if subprocess.run(["doas", "/usr/local/sbin/cherrystone-settz", tz]).returncode == 0:
            subprocess.run(["pkill", "-USR1", "-x", "tint2"])   # the clock picks up the new zone
    Gtk.main_quit()


go.connect("clicked", done)
win.add(outer)
win.set_default(go)
win.show_all()
if not SETTINGS:
    refresh()
go.grab_focus()          # Enter = Done
Gtk.main()
EOF

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-about <<'EOF'
#!/bin/sh
# Settings > About (part of cherrystone-ui)
exec cherrystone-ui about
EOF

# Settings (and quick settings): a small Python GTK app, settings.py, next
# to these scripts. Same look as the sign-in screen.
install -m 0755 "$BRAND"/../settings.py "$tmp"/usr/local/bin/cherrystone-settings
# ui.py: all the other small screens (Wi-Fi, power, display, ...) in that look
install -m 0755 "$BRAND"/../ui.py "$tmp"/usr/local/bin/cherrystone-ui

makefile root:root 0644 "$tmp"/usr/share/applications/cherrystone-settings.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Settings
Exec=cherrystone-settings
Icon=preferences-system
Categories=Settings;
EOF

# --------------------------------------------------------- USB sticks, SD cards

# Mount removable drives automatically and show them in Files
mkdir -p "$tmp"/etc/skel/.config/pcmanfm/default "$tmp"/etc/skel/.config/libfm
makefile root:root 0644 "$tmp"/etc/skel/.config/pcmanfm/default/pcmanfm.conf <<'EOF'
[volume]
mount_on_startup=1
mount_removable=1
autorun=0

[ui]
show_hidden=0
side_pane_mode=places
view_mode=icon
toolbar=navigation;home;
pathbar_mode_buttons=1
show_statusbar=1
splitter_pos=190
win_width=860
win_height=540
EOF
makefile root:root 0644 "$tmp"/etc/skel/.config/libfm/libfm.conf <<'EOF'
[config]
terminal=cherrystone-terminal -e %s
su_cmd=cherrystone-asroot %s
quick_exec=1
big_icon_size=64
small_icon_size=24
pane_icon_size=24
thumbnail_size=128
show_thumbnail=1

[places]
places_home=1
places_desktop=0
places_root=0
places_computer=0
places_trash=1
places_applications=0
places_network=0
places_unmounted=0
EOF
# The usual folders, and none of Alpine's default empty drive entries
mkdir -p "$tmp"/etc/skel/Documents "$tmp"/etc/skel/Pictures "$tmp"/etc/skel/Music "$tmp"/etc/skel/Videos
[ -f "$tmp"/etc/fstab ] && sed -i '/\/media\/\(cdrom\|floppy\|usb\)/d' "$tmp"/etc/fstab

# Let the desktop user mount drives and manage Wi-Fi without a password
mkdir -p "$tmp"/etc/polkit-1/rules.d
makefile root:root 0644 "$tmp"/etc/polkit-1/rules.d/50-cherrystone.rules <<'EOF'
polkit.addRule(function(action, subject) {
	if ((subject.user == "cherrystone" || subject.user == "guest") &&
	    (action.id.indexOf("org.freedesktop.udisks2.") == 0 ||
	     action.id.indexOf("org.freedesktop.NetworkManager.") == 0 ||
	     action.id.indexOf("org.blueman.") == 0)) {
		return polkit.Result.YES;
	}
});
EOF

# ------------------------------------------------------ power button and lid

makefile root:root 0755 "$tmp"/etc/acpi/handler.sh <<'EOF'
#!/bin/sh
# acpid calls this with the event, e.g. "button/lid LID close"
case "$1" in
	button/power)
		poweroff ;;
	button/lid)
		if [ "$3" = close ]; then
			# some laptops send "close" twice: only sleep once
			mkdir /run/cherrystone-lid 2>/dev/null || exit 0
			trap 'rmdir /run/cherrystone-lid' EXIT
			# don't sleep halfway through installing or saving
			pgrep -f 'cherrystone-ui install' >/dev/null && exit 0
			pgrep -f 'cherrystone-ui save' >/dev/null && exit 0
			# lock the screen first, so it's locked when the lid opens
			su -l "$(stat -c %U /dev/tty1)" -s /bin/sh -c \
				'DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority cherrystone-lock' >/dev/null 2>&1 &
			sleep 1
			sync
			echo mem > /sys/power/state
		fi ;;
esac
EOF

# ------------------------------------------------- zram: compressed swap in RAM
# Old machines have little memory. Pages that are swapped out get compressed
# (2-3x) instead of being thrown away, so a 1 GB machine behaves like ~1.5 GB.

mkdir -p "$tmp"/etc/local.d "$tmp"/etc/sysctl.d
makefile root:root 0755 "$tmp"/etc/local.d/zram.start <<'EOF'
#!/bin/sh
modprobe zram num_devices=1 2>/dev/null || exit 0
[ -e /sys/block/zram0 ] || exit 0
grep -q zram0 /proc/swaps && exit 0
for alg in lz4 lzo-rle lzo zstd; do
	if grep -qw "$alg" /sys/block/zram0/comp_algorithm; then
		echo "$alg" > /sys/block/zram0/comp_algorithm
		break
	fi
done
kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
echo "$((kb * 1024))" > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null && swapon -p 100 /dev/zram0
EOF
makefile root:root 0644 "$tmp"/etc/sysctl.d/90-cherrystone.conf <<'EOF'
# Swap is compressed RAM (zram), which is cheap: use it readily
vm.swappiness = 100
vm.page-cluster = 0
EOF

# Show a cursor again on the rescue console (the splash hides it)
makefile root:root 0755 "$tmp"/etc/local.d/cursor.start <<'EOF'
#!/bin/sh
printf '\033[?25h' > /dev/tty2
EOF

# ------------------------------------------------------------- boot splash
# Just the cherry, in colour, in the middle of a black screen while the
# system starts (like a phone). Drawn as soon as a graphics driver is up;
# before that the screen is plain black.

makefile root:root 0755 "$tmp"/etc/init.d/cherrystone-splash <<'EOF'
#!/sbin/openrc-run
description="Cherrystone boot splash"

depend() {
	after udev-settle
	before hostname
}

start() {
	img=/usr/share/cherrystone/splash.ppm
	[ -e /dev/fb0 ] && [ -f "$img" ] || return 0
	# The visible screen size (the "U:1024x600p-60" line), not virtual_size:
	# some graphics drivers make that twice as tall, which pushed the logo
	# off the middle
	mode="$(head -n1 /sys/class/graphics/fb0/modes 2>/dev/null | sed -n 's/^[A-Z]*:\([0-9]*\)x\([0-9]*\).*/\1 \2/p')"
	if [ -n "$mode" ]; then
		w="${mode% *}"; h="${mode#* }"
	else
		size="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)"
		w="${size%,*}"; h="${size#*,}"
	fi
	set -- $(head -c 64 "$img" | tr -s ' \n' ' ' | cut -d' ' -f2,3)
	iw="$1"; ih="$2"
	left=$(( (w - iw) / 2 )); top=$(( (h - ih) / 2 ))
	[ "$left" -ge 0 ] && [ "$top" -ge 0 ] || return 0
	printf 'IMG_LEFT=%s\nIMG_TOP=%s\n' "$left" "$top" > /run/fbsplash.cfg
	printf '\033[2J\033[?25l' > /dev/tty1
	fbsplash -c -s "$img" -i /run/fbsplash.cfg >/dev/null 2>&1 || true
	return 0
}
EOF

mkdir -p "$tmp"/usr/share/cherrystone
if command -v magick >/dev/null 2>&1; then
	# Black, with only the cherry (no words)
	magick -size 160x160 xc:black \
		\( "$BRAND"/cherrystone-256.png -resize 140x140 \) \
		-gravity center -composite \
		-alpha off -depth 8 "ppm:$tmp/usr/share/cherrystone/splash.ppm" \
		|| echo "warning: could not make the splash image; booting without one" >&2

	# Simple white symbols for menu entries the icon theme has no colour icon for
	for pair in "settings:⚙" "restart:↻"; do
		name="${pair%%:*}"; glyph="${pair#*:}"
		magick -background none -fill white \
			-font /usr/share/fonts/dejavu/DejaVuSans.ttf -size 48x48 -gravity center \
			"label:$glyph" "$tmp/usr/share/icons/hicolor/48x48/apps/cherrystone-$name.png" \
			|| echo "warning: could not make the $name icon" >&2
	done
	# The power symbol isn't in DejaVu, so draw it: an open ring and a bar
	magick -size 48x48 xc:none -stroke white -strokewidth 3 -fill none \
		-draw "arc 13,14 35,36 -55,235" -draw "line 24,9 24,24" \
		"$tmp/usr/share/icons/hicolor/48x48/apps/cherrystone-shutdown.png" \
		|| echo "warning: could not make the shutdown icon" >&2
	# Dark versions for light windows (the Recovery app)
	for name in restart shutdown; do
		magick "$tmp/usr/share/icons/hicolor/48x48/apps/cherrystone-$name.png" \
			-channel RGB -fill '#3a3a3a' -colorize 100 \
			"$tmp/usr/share/icons/hicolor/48x48/apps/cherrystone-$name-dark.png" \
			|| echo "warning: could not make the dark $name icon" >&2
	done
fi

# Lock screen: with no password set, Enter unlocks
makefile root:root 0644 "$tmp"/etc/pam.d/i3lock <<'EOF'
auth     required  pam_unix.so nullok
account  required  pam_unix.so
EOF

# Flat icons (Papirus), trimmed to the main set and the sizes Cherrystone uses
I="$tmp"/usr/share/icons
rm -rf "$I"/Papirus-Dark "$I"/Papirus-Light "$I"/ePapirus "$I"/ePapirus-Dark
for d in "$I"/Papirus/[0-9]*x[0-9]*; do
	case "${d##*/}" in 16x16|22x22|24x24|32x32|48x48|64x64) ;; *) rm -rf "$d" ;; esac
done

# White copies of the status icons for the (dark) shelf
mkdir -p "$tmp"/usr/share/cherrystone/shelf
for n in bluetooth-active bluetooth-disabled network-wireless-signal-excellent network-wireless-signal-good network-wireless-signal-ok 		network-wireless-signal-weak network-wireless-offline network-wired network-offline 		audio-volume-high audio-volume-medium audio-volume-low audio-volume-muted 		battery-level-0 battery-level-10 battery-level-20 battery-level-30 battery-level-40 		battery-level-50 battery-level-60 battery-level-70 battery-level-80 battery-level-90 		battery-level-100 battery-level-0-charging battery-level-10-charging 		battery-level-20-charging battery-level-30-charging battery-level-40-charging 		battery-level-50-charging battery-level-60-charging battery-level-70-charging 		battery-level-80-charging battery-level-90-charging; do
	f="$I"/Papirus/symbolic/status/$n-symbolic.svg
	[ -f "$f" ] && sed 's/#444444/#ffffff/g' "$f" > "$tmp"/usr/share/cherrystone/shelf/$n.svg
done
sed 's/#444444/#ffffff/g' "$I"/Papirus/symbolic/apps/system-software-install-symbolic.svg 	> "$tmp"/usr/share/cherrystone/shelf/install.svg
[ -f "$tmp"/usr/share/cherrystone/shelf/battery-level-100.svg ] &&
	cp "$tmp"/usr/share/cherrystone/shelf/battery-level-100.svg "$tmp"/usr/share/cherrystone/shelf/battery-level-100-charging.svg

makefile root:root 0755 "$tmp"/usr/local/bin/cherrystone-status <<'EOF'
#!/bin/sh
# cherrystone-status bt|net|vol|bat: the icon for the shelf
d=/usr/share/cherrystone/shelf
case "$1" in
net)
	sig="$(nmcli -t -f active,signal dev wifi 2>/dev/null | awk -F: '$1 == "yes" { print $2; exit }')"
	if [ -n "$sig" ]; then
		if [ "$sig" -ge 75 ]; then n=excellent; elif [ "$sig" -ge 50 ]; then n=good
		elif [ "$sig" -ge 25 ]; then n=ok; else n=weak; fi
		echo "$d/network-wireless-signal-$n.svg"
	elif nmcli -t -f type,state dev 2>/dev/null | grep -q '^ethernet:connected'; then
		echo "$d/network-wired.svg"
	else
		echo "$d/network-wireless-offline.svg"
	fi ;;
vol)
	ctl=Master
	amixer sget "$ctl" >/dev/null 2>&1 || ctl=PCM
	info="$(amixer sget "$ctl" 2>/dev/null)" || exit 0     # no sound card: no icon
	v="$(echo "$info" | grep -o '[0-9]*%' | head -n1 | tr -d %)"
	if echo "$info" | grep -q '\[off\]' || [ "${v:-0}" -eq 0 ]; then n=muted
	elif [ "$v" -lt 34 ]; then n=low; elif [ "$v" -lt 67 ]; then n=medium; else n=high; fi
	echo "$d/audio-volume-$n.svg" ;;
bt)
	ls /sys/class/bluetooth/hci* >/dev/null 2>&1 || exit 0      # no Bluetooth: no icon
	if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
		echo "$d/bluetooth-active.svg"
	else
		echo "$d/bluetooth-disabled.svg"
	fi ;;
bat)
	for b in /sys/class/power_supply/BAT*; do
		[ -r "$b/capacity" ] || continue
		c=$(( ($(cat "$b/capacity") + 5) / 10 * 10 ))
		[ "$c" -gt 100 ] && c=100
		ch=""; [ "$(cat "$b/status" 2>/dev/null)" = Charging ] && ch=-charging
		echo "$d/battery-level-$c$ch.svg"
		exit 0
	done ;;
esac
EOF

# Quick settings, Wi-Fi picker, notification history, lock screen, web apps,
# install to disk, "Save my stuff"
. "$(dirname "$0")/features.sh"
# Home page tiles, sign-in and guest, shortcuts, watcher,
# Bluetooth, startup sound
. "$(dirname "$0")/extras.sh"
# Reset, sign-in clock, tour, touchpad, wallpapers,
# shutdown sound
. "$(dirname "$0")/extras2.sh"
. "$(dirname "$0")/extras3.sh"

# Start services in parallel (faster boot)
sed -i 's/^#*rc_parallel=.*/rc_parallel="YES"/' "$tmp"/etc/rc.conf

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add cherrystone-splash boot

rc_add dbus default
rc_add seatd default
rc_add networkmanager default
rc_add acpid default
rc_add local default
rc_add udev-postmount default
# Bluetooth only starts on computers that have it (see bluetooth.start)
makefile root:root 0755 "$tmp"/etc/local.d/bluetooth.start <<'EOF'
#!/bin/sh
ls /sys/class/bluetooth/hci* >/dev/null 2>&1 && rc-service bluetooth start >/dev/null 2>&1
exit 0
EOF

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown
