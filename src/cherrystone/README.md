# Cherrystone

**Turn an old laptop into a simple, safe computer for the web.**

Got a netbook from 2009, or a laptop that got too slow for Windows? It still turns on, it just
can't keep up anymore. Cherrystone turns it into a computer that's just for the web: you switch it
on, sign in, and the browser is right there. Nothing to update, configure or break.

- **Switch it on and you're on the web.** A browser-first desktop with a shelf and a launcher
  that anyone can pick up.
- **It can't really break.** A sign-in screen with a password, guest mode, a reset button to start
  fresh, and a recovery USB that repairs an installed copy.
- **Runs on what you've got.** PCs from around 2008-2010 or newer, 32-bit or 64-bit, from 1 GB
  of memory. It runs straight from a
  USB stick without touching the computer's disk, or installs in a few minutes.
- **No account needed.** Nothing to sign up for, nothing to sync.

Under the hood it's Alpine Linux (musl, busybox, OpenRC) with a small, custom desktop, but you
never have to know that.

## Build

    ./build.sh            # 64-bit ISO  -> out/cherrystone-x86_64.iso   (needs docker)
    ./build.sh x86        # 32-bit ISO  -> out/cherrystone-x86.iso      (Atom N270, Pentium 4 and older)

    ./build-wsl.sh        # same, without docker (WSL or any Linux; asks for sudo)
    ./build-wsl.sh x86

Needs internet. Set `ALPINE_VERSION=3.xx` to pick a release.

## Test

    qemu-system-x86_64 -m 1024 -cdrom out/cherrystone-x86_64.iso     # 64-bit
    qemu-system-i386   -m 1024 -cdrom out/cherrystone-x86.iso        # 32-bit

Write to USB with `dd` or balenaEtcher.

## Boot menu
- **Cherrystone** (starts after 2 seconds).
- **Recovery (repair an installed Cherrystone):** a repair kit, like a recovery USB.
  Instead of the browser it starts the Recovery app, which finds Cherrystone installed on the
  computer's disk (and any Save my stuff drive) and offers to:
  - **Repair it:** checks the disk for errors, puts fresh system files on it from the USB stick
    (which also updates it) and fixes how it starts. Your settings and files are kept.
  - **Get your files** off it (read-only, in Files) to copy onto another USB stick.
  - **Reset it:** erases everything kept on it, after a "Woah there!" warning and typing `ERASE`.
  - Open a terminal, restart, shut down.

  Anything that touches the installation asks for its password, if it has one.

Cherrystone needs about **1 GB of memory**. On a computer with less it says so and shuts down
(press T on that screen to start anyway). Recovery works on less.

Started from the USB stick, Cherrystone always uses the USB stick's system, even when Cherrystone is
also installed on the computer's disk.

## Browser first
The browser *is* the computer. It's on the shelf and in the launcher; nothing opens by
itself when you sign in.
- **Sign-in screen:** your picture with your name and
  password under it, **Browse as Guest** and **Shut down** along the bottom, the time and battery in
  the top-right corner, on your wallpaper. A guest's session runs in RAM and is thrown away when they sign out, even when your
  stuff is being saved. Sign out from the power button, quick settings or the right-click menu.
- **Tour:** the first time you sign in, a note points to a short tour (**Tour** in the
  launcher).
- **Home page** (also every new tab): "Good morning, *your name*", the date, a search box and big tiles for web apps (Gmail, YouTube,
  Docs, Drive, Calendar, Maps, News, Wikipedia). Change them with
  **Edit tiles** on the page or Settings > Home page tiles. When you're offline it says so, with a
  Connect to Wi-Fi button and **Cherry Run**, a little pixel-art game.
- **Light and simple,** with one set of flat icons (Papirus).
- **Browser: Badwolf,** a small WebKit browser (Safari's engine) with modern web support and
  built-in ad and tracker blocking (EasyList). On 32-bit processors WebKit has no fast JavaScript
  compiler, so very script-heavy sites can be slow.
- **Shelf** along the bottom: the cherry launcher button and pinned apps (browser,
  Gmail, Docs, YouTube, Files, Settings) and open windows at the left; network, volume, battery,
  the clock (quick settings) and your picture (shut down, restart, sign out) at the right.
- **Launcher** (cherry button or the **Super/Windows key**): a card in the middle of the screen with
  a search box and a grid of apps. Type
  an app's name, a web address, or anything else to search the web. Web apps open as tabs.
- **Quick settings** (click the clock): Wi-Fi, Bluetooth, volume and brightness sliders,
  notifications, Settings, Lock, Sign out, Restart, Shut down.
- **Other apps,** when you need them: Files, Notes, Calculator, Photos, Videos and Music. Switch
  between them and the browser with Alt+Tab or the shelf. Terminal and Task Manager are hidden
  unless you turn on **Settings > Advanced > Linux apps** (off by default).
- **Welcome screen:** keyboard layout and time zone. It shows at every start until your stuff is saved.
- **Settings:** Wi-Fi, Bluetooth, sound, display (brightness, text size, a second screen),
  wallpaper, your name and picture, password, keyboard and time zone, touchpad, home page tiles,
  about. **Advanced:** Save my stuff, Install to disk, Reset, keyboard shortcuts, Linux
  apps, network details.
- **Notifications:** missed ones, Clear all, and Do not disturb (quick settings > Notifications).
- **Lock screen:** Ctrl+Alt+L, quick settings, or closing the lid. With no password set, Enter
  unlocks it; set one in Settings > Password (it's the sign-in password too).
- **Password:** once set, it also locks the rescue console (Ctrl+Alt+F2, log in as `root` with it)
  and the rescue shell on the "couldn't start" screen, and it still applies when starting with
  `cherrystone.nosave`. Recovery asks for it too.
  It keeps people out of your session; it isn't encryption, so someone who boots the computer
  from their own USB stick can still read the saved files.
- **USB sticks and SD cards** mount by themselves; a notification offers to open them in Files.
- **Battery:** warnings at 20% and 10%; at 4% Cherrystone shuts down safely after a minute unless
  you plug in the charger.
- **Bluetooth:** mice, keyboards and other devices (Settings or quick settings > Bluetooth).
  Bluetooth headphones and speakers don't work yet.
- **Touchpad:** tap to click is on; natural scrolling is in Settings > Touchpad.
- **Wallpapers:** five built-in ones or your own picture (Settings > Wallpaper). It shows behind
  the sign-in screen and the home page.
- **Volume and brightness keys** show a cherry-red level bar.
- **Small screens:** on 600-pixel-tall netbook screens (like the Aspire One's) text and controls
  are a little smaller so more fits.
- **Sounds:** `branding/startup.wav` plays when the sign-in screen comes up and
  `branding/shutdown.wav` when Cherrystone shuts down or restarts. Replace them before building to
  change them; `touch ~/.config/cherrystone/no-sound` turns both off.

- **Reset Cherrystone** in Settings: restarts and erases your stuff, after a
  "Woah there!" warning, your password and typing `ERASE`. Forgot the password? Then nothing in
  Cherrystone can reset it: reinstall (Install to disk from the USB stick) or reformat the save drive.

## Keeping your stuff
Running from a USB stick, Cherrystone forgets everything when it shuts down, unless:
- **Install to disk** (Settings): erases a disk in the computer and installs Cherrystone on it. It
  starts faster and keeps settings, Wi-Fi passwords and files automatically. BIOS computers only for
  now (that includes most PCs from before about 2012).
- **Save my stuff** (Settings): pick a second USB stick or SD card; it's erased and used to keep your
  settings and files. Whatever you've already set up this session is copied onto it. Keep it plugged
  in when you start Cherrystone.

To start once without your saved stuff (if something you changed broke it), add `cherrystone.nosave`
to the kernel command line (press Tab at the boot menu).

Keys:

| Key | Does |
| --- | --- |
| Super (Windows key) | Launcher |
| Ctrl+Alt+/ | All keyboard shortcuts |
| Ctrl+Alt+T | Terminal (with Linux apps on) |
| Ctrl+Alt+L | Lock the screen |
| Print Screen | Screenshot to Pictures |
| Volume keys, scroll on the ♪ in the panel | Volume (click the ♪ to mute) |
| Brightness keys | Brightness |
| Alt+Tab, Alt+F4 | Switch / close windows |
| Power button | Shut down |
| Closing the lid | Lock and suspend |

## How it works
- `packages`: the package list for the system.
- `rootfs-config.sh`: system config: services, autologin, theme, status strip, launcher, helper scripts.
- `features.sh`: quick settings, Wi-Fi picker, notification history, lock screen, web apps,
  install to disk and Save my stuff (sourced by `rootfs-config.sh`).
- `extras.sh`: the home page and its tiles, sign-in and guest mode,
  the shortcut list, the session watcher (offline, battery, USB), Bluetooth, startup sound.
- `extras2.sh`: Reset, the sign-in clock, the tour, touchpad settings,
  wallpapers and the shutdown sound.
- `mkiso.sh`: the build. Installs the packages into a directory, applies the config, compresses it
  into `cherrystone.sfs` (squashfs), and wraps kernel + initramfs + image into a BIOS/UEFI-bootable ISO.
  `build.sh` and `build-wsl.sh` just run it inside an Alpine environment. It also compiles
  Badwolf with JavaScript on by default (the packaged one has it off in every tab); that's done
  once per architecture and cached in `/var/tmp`.
- `initramfs-init`: early boot. Finds the boot media, mounts `cherrystone.sfs` read-only and puts a
  writable layer over it: on the installed disk, on a CHERRYSAVE drive, or in RAM.

The system is read from the USB/CD on demand rather than unpacked into RAM, so memory is only used
for what is running and what you change. Swap is compressed RAM (zram), which stretches 1 GB a long
way. Nothing is written to the PC's disk, and everything is forgotten on reboot. Don't unplug the
USB stick while it is running.

Boot messages are hidden behind the splash; press Ctrl+Alt+F12 to see them. Ctrl+Alt+F2 is a rescue
console (log in as `root`: no password, or your password once you've set one).

## Tuning for the oldest hardware
- **Wi-Fi firmware:** included for Intel, Realtek, Atheros, Broadcom and Ralink chips.
- **Graphics:** `vesa`/`fbdev` drivers work everywhere but are slow. Intel/ATI/Nouveau drivers are included for acceleration.
- **Slow USB sticks:** if Cherrystone says it couldn't find the USB stick, add `usbdelay=10` to the
  kernel command line.

## If it can't start
Problems before the desktop (USB stick unreadable, damaged image, broken saved stuff) show a white,
plain "Cherrystone couldn't start" screen that says what went wrong and what to try. Press R to restart or
Enter for a rescue shell (it asks for your password, if you've set one). Add `cherrystone.testerror` to the kernel command line to see the screen.

USB sticks can be written with balenaEtcher, Rufus (either mode) or `dd`.

## About the name
Cherrystone is a nod to Chromium OS Cherry, a hobby build from 2009-2010 that ran on netbooks like
the Acer Aspire One. Cherrystone is an independent project and isn't affiliated with Google. Chrome
OS and Chromium OS are trademarks of Google LLC.
